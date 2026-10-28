import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FinalExamEntry } from '../model/JwModels';
import { ExamDateUtils } from '../utils/ExamDateUtils';

const TAG: string = 'CardDataStore';
const DOMAIN: number = 0x0000;
const PREF_NAME: string = 'jw_card_data';
const KEY_PAYLOAD: string = 'payload';
const KEY_FORM_IDS: string = 'formIds';
const KEY_FORM_ENTRIES: string = 'formEntries';
const KEY_APP_CACHE: string = 'appCache';
const KEY_REMINDER_SETTINGS: string = 'reminderSettings';
const KEY_DISABLED_COURSES: string = 'reminderDisabledCourses';
const KEY_FINAL_EXAMS: string = 'finalExamDates';
const KEY_PRIVACY_MODE: string = 'privacyMode';
const KEY_EXAM_FORM_IDS: string = 'examFormIds';

/** 持久化的课表单元格（紧凑字段，仅本周与下周数据） */
export class CardCellItem {
  d: number = 1;
  s: number = 1;
  e: number = 1;
  n: string = '';
  p: string = '';
  t: string = '';
  w: string = '';
  c: string = '';
  r: string = '';
}

/** 下发给卡片的课程条目 */
export class CardCourseData {
  time: string = '';
  name: string = '';
  place: string = '';
}

/** 下发给卡片周网格的课程格 */
export class WeekCellData {
  d: number = 1;
  s: number = 1;
  e: number = 1;
  n: string = '';
  p: string = '';
  r: string = '';
  c: string = '';
}

/** 已添加卡片的登记项（记录各自展示的课程数上限） */
export class FormEntry {
  id: string = '';
  max: number = 3;
}

/** 上课提醒设置 */
export class ReminderSettings {
  enabled: boolean = true;
  advanceMinutes: number = 10;
}

/** 下发给期末倒计时卡片的条目（紧凑字段） */
export class ExamCardItem {
  n: string = '';
  d: string = '';
  t: string = '';
  x: number = 0;
}

/** 构建期末卡片数据时的中间项（已解析的日期与距考天数） */
class ExamUpcomingItem {
  entry: FinalExamEntry = new FinalExamEntry();
  days: number = 0;
}

interface CardPayloadRaw {
  week?: number;
  cells?: CardCellItem[];
}

interface FormEntryRaw {
  id?: string;
  max?: number;
}

interface ReminderSettingsRaw {
  enabled?: boolean;
  advance?: number;
}

interface FinalExamRaw {
  course?: string;
  date?: string;
}

/**
 * 服务卡片数据仓库：
 * 主应用同步后把本周/下周课表持久化到 preferences（应用级目录），
 * FormExtensionAbility 在添加/更新卡片时读取并计算"今日课程"推送到卡片。
 */
export class CardDataStore {
  /** 2*4 卡片最多展示课程数 */
  static readonly MAX_SMALL: number = 3;
  /** 4*4 卡片最多展示课程数 */
  static readonly MAX_LARGE: number = 6;

  private static store(context: common.Context): preferences.Preferences {
    return preferences.getPreferencesSync(context.getApplicationContext(), { name: PREF_NAME });
  }

  /**
   * 保存课表数据（JSON），并尝试刷新已添加的卡片。
   */
  static saveAndRefresh(context: common.Context, payloadJson: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_PAYLOAD, payloadJson);
      pref.flushSync();
      CardDataStore.refreshAllCards(context);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'saveAndRefresh failed: %{public}s', `${error}`);
    }
  }

  /** 保存应用内离线缓存（最近一次同步的完整数据 JSON），会话过期时供界面回显 */
  static saveAppCache(context: common.Context, cacheJson: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_APP_CACHE, cacheJson);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'saveAppCache failed: %{public}s', `${error}`);
    }
  }

  static loadAppCache(context: common.Context): string {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      return CardDataStore.readString(pref, KEY_APP_CACHE);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadAppCache failed: %{public}s', `${error}`);
      return '';
    }
  }

  static clearAppCache(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_APP_CACHE);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clearAppCache failed: %{public}s', `${error}`);
    }
  }

  /** 读取上课提醒设置（未配置时返回默认值：开启、提前 10 分钟） */
  static loadReminderSettings(context: common.Context): ReminderSettings {
    const settings: ReminderSettings = new ReminderSettings();
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const json: string = CardDataStore.readString(pref, KEY_REMINDER_SETTINGS);
      if (json.length > 0) {
        const raw: ReminderSettingsRaw = JSON.parse(json) as ReminderSettingsRaw;
        settings.enabled = typeof raw.enabled === 'boolean' ? raw.enabled : true;
        settings.advanceMinutes =
          typeof raw.advance === 'number' && raw.advance > 0 && raw.advance <= 120 ? raw.advance : 10;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadReminderSettings failed: %{public}s', `${error}`);
    }
    return settings;
  }

  /** 保存上课提醒设置 */
  static saveReminderSettings(context: common.Context, enabled: boolean, advanceMinutes: number): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const payload: ReminderSettingsRaw = { enabled: enabled, advance: advanceMinutes };
      pref.putSync(KEY_REMINDER_SETTINGS, JSON.stringify(payload));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'saveReminderSettings failed: %{public}s', `${error}`);
    }
  }

  /** 读取被单独关闭上课提醒的课程名单（按课程名，默认空 = 全部跟随全局开关） */
  static loadDisabledCourses(context: common.Context): string[] {
    const result: string[] = [];
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const json: string = CardDataStore.readString(pref, KEY_DISABLED_COURSES);
      if (json.length > 0) {
        const raw: Object[] = JSON.parse(json) as Object[];
        for (const item of raw) {
          if (typeof item === 'string') {
            result.push(item);
          }
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadDisabledCourses failed: %{public}s', `${error}`);
    }
    return result;
  }

  /** 保存被单独关闭上课提醒的课程名单 */
  static saveDisabledCourses(context: common.Context, courses: string[]): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_DISABLED_COURSES, JSON.stringify(courses));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'saveDisabledCourses failed: %{public}s', `${error}`);
    }
  }

  /** 读取各课程期末考试日期设置（按课程名，默认空 = 未设置） */
  static loadFinalExams(context: common.Context): FinalExamEntry[] {
    const result: FinalExamEntry[] = [];
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const json: string = CardDataStore.readString(pref, KEY_FINAL_EXAMS);
      if (json.length > 0) {
        const raw: FinalExamRaw[] = JSON.parse(json) as FinalExamRaw[];
        for (const item of raw) {
          if (typeof item.course === 'string' && item.course.length > 0
            && typeof item.date === 'string' && item.date.length > 0) {
            const entry: FinalExamEntry = new FinalExamEntry();
            entry.courseName = item.course;
            entry.examDate = item.date;
            result.push(entry);
          }
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadFinalExams failed: %{public}s', `${error}`);
    }
    return result;
  }

  /** 保存各课程期末考试日期设置 */
  static saveFinalExams(context: common.Context, exams: FinalExamEntry[]): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const raw: FinalExamRaw[] = [];
      for (const entry of exams) {
        raw.push({ course: entry.courseName, date: entry.examDate });
      }
      pref.putSync(KEY_FINAL_EXAMS, JSON.stringify(raw));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'saveFinalExams failed: %{public}s', `${error}`);
    }
  }

  /** 读取隐私模式（standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存，未配置默认 standard） */
  static loadPrivacyMode(context: common.Context): string {
    let mode: string = 'standard';
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const stored: string = CardDataStore.readString(pref, KEY_PRIVACY_MODE);
      if (stored === 'standard' || stored === 'restricted' || stored === 'strict') {
        mode = stored;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'loadPrivacyMode failed: %{public}s', `${error}`);
    }
    return mode;
  }

  /** 保存隐私模式 */
  static savePrivacyMode(context: common.Context, mode: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_PRIVACY_MODE, mode);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'savePrivacyMode failed: %{public}s', `${error}`);
    }
  }

  /** 清除持久化的卡片课表数据（严格隐私模式启用或退至后台时调用） */
  static clearCardPayload(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_PAYLOAD);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clearCardPayload failed: %{public}s', `${error}`);
    }
  }

  /** 清除期末考试日期设置（严格隐私模式清理时调用） */
  static clearFinalExams(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_FINAL_EXAMS);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clearFinalExams failed: %{public}s', `${error}`);
    }
  }

  /** 清除单课提醒关闭名单（严格隐私模式清理时调用） */
  static clearDisabledCourses(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_DISABLED_COURSES);
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clearDisabledCourses failed: %{public}s', `${error}`);
    }
  }

  static addFormEntry(context: common.Context, formId: string, maxCourses: number): void {
    if (formId.length === 0) {
      return;
    }
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const entries: FormEntry[] = CardDataStore.readEntries(pref);
      const kept: FormEntry[] = entries.filter((e: FormEntry): boolean => e.id !== formId);
      const entry: FormEntry = new FormEntry();
      entry.id = formId;
      entry.max = maxCourses;
      kept.push(entry);
      pref.putSync(KEY_FORM_ENTRIES, JSON.stringify(kept));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addFormEntry failed: %{public}s', `${error}`);
    }
  }

  static removeFormEntry(context: common.Context, formId: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const entries: FormEntry[] = CardDataStore.readEntries(pref);
      const kept: FormEntry[] = entries.filter((e: FormEntry): boolean => e.id !== formId);
      pref.putSync(KEY_FORM_ENTRIES, JSON.stringify(kept));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'removeFormEntry failed: %{public}s', `${error}`);
    }
  }

  /**
   * 构建卡片绑定数据：解析持久化课表，计算今日课程（按卡片上限截断，超出记余量）。
   */
  static buildBindingData(context: common.Context, maxCourses: number): formBindingData.FormBindingData {
    if (CardDataStore.loadPrivacyMode(context) === 'strict') {
      const disabled: Record<string, string> = {
        'weekText': '',
        'coursesJson': '[]',
        'moreText': '',
        'emptyText': '',
        'weekCellsJson': '[]',
        'todayD': '0',
        'privacyDisabledText': '当前隐私设置无法使用卡片'
      };
      return formBindingData.createFormBindingData(disabled);
    }
    let week: number = 0;
    let cells: CardCellItem[] = [];
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const payloadJson: string = CardDataStore.readString(pref, KEY_PAYLOAD);
      if (payloadJson.length > 0) {
        const raw: CardPayloadRaw = JSON.parse(payloadJson) as CardPayloadRaw;
        week = raw.week ?? 0;
        cells = raw.cells ?? [];
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'read payload failed: %{public}s', `${error}`);
    }
    const day: number = new Date().getDay();
    const today: number = day === 0 ? 7 : day;
    const todayCells: CardCellItem[] = cells
      .filter((c: CardCellItem): boolean => c.d === today && CardDataStore.cellInWeek(c, week))
      .sort((a: CardCellItem, b: CardCellItem): number => a.s - b.s);
    const shown: CardCellItem[] = todayCells.slice(0, maxCourses);
    const more: number = todayCells.length - shown.length;
    hilog.info(DOMAIN, TAG,
      'buildBindingData max:%{public}d week:%{public}d cells:%{public}d todayCells:%{public}d',
      maxCourses, week, cells.length, todayCells.length);
    const courseData: CardCourseData[] = [];
    for (const cell of shown) {
      const course: CardCourseData = new CardCourseData();
      course.time = cell.t;
      course.name = cell.n;
      course.place = cell.p;
      courseData.push(course);
    }
    const weekCells: CardCellItem[] =
      cells.filter((c: CardCellItem): boolean => CardDataStore.cellInWeek(c, week));
    const gridCells: WeekCellData[] = [];
    for (const cell of weekCells) {
      const grid: WeekCellData = new WeekCellData();
      grid.d = cell.d;
      grid.s = cell.s;
      grid.e = cell.e;
      grid.n = cell.n;
      grid.p = cell.p;
      grid.r = cell.r;
      grid.c = cell.c;
      gridCells.push(grid);
    }
    const data: Record<string, string> = {
      'weekText': week > 0 ? '第' + week + '周' : '',
      'coursesJson': JSON.stringify(courseData),
      'moreText': more > 0 ? '还有' + more + '门课' : '',
      'emptyText': todayCells.length === 0 ? '今天没有课程安排' : '',
      'weekCellsJson': JSON.stringify(gridCells),
      'todayD': `${today}`,
      'privacyDisabledText': ''
    };
    return formBindingData.createFormBindingData(data);
  }

  /**
   * 刷新所有已添加的卡片（数据变更后由主应用调用）。
   */
  static refreshAllCards(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const entries: FormEntry[] = CardDataStore.readEntries(pref);
      if (entries.length === 0) {
        return;
      }
      for (const entry of entries) {
        const binding: formBindingData.FormBindingData =
          CardDataStore.buildBindingData(context, entry.max);
        formProvider.updateForm(entry.id, binding).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', entry.id, `${error}`);
          if (`${error}`.includes('does not exist')) {
            CardDataStore.removeFormEntry(context, entry.id);
          }
        });
      }
      hilog.info(DOMAIN, TAG, 'refresh cards: %{public}s', `${entries.length}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'refreshAllCards failed: %{public}s', `${error}`);
    }
  }

  /** 登记已添加的期末倒计时卡片 */
  static addExamFormEntry(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const ids: string[] = CardDataStore.readExamFormIds(pref);
      if (ids.indexOf(formId) < 0) {
        ids.push(formId);
        pref.putSync(KEY_EXAM_FORM_IDS, JSON.stringify(ids));
        pref.flushSync();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'addExamFormEntry failed: %{public}s', `${error}`);
    }
  }

  /** 移除已删除的期末倒计时卡片登记 */
  static removeExamFormEntry(context: common.Context, formId: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const ids: string[] = CardDataStore.readExamFormIds(pref);
      const kept: string[] = ids.filter((id: string): boolean => id !== formId);
      pref.putSync(KEY_EXAM_FORM_IDS, JSON.stringify(kept));
      pref.flushSync();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'removeExamFormEntry failed: %{public}s', `${error}`);
    }
  }

  /**
   * 构建期末倒计时卡片绑定数据：
   * 严格/限制隐私模式下返回不可用提示（期末日期仅标准模式缓存）；
   * 否则读取持久化的期末日期，过滤已结束科目，按考试时间从近到远
   * 取最近 3 条（含距考天数驱动的徽配色信息），无数据时返回空态文案。
   */
  static buildExamBindingData(context: common.Context): formBindingData.FormBindingData {
    const mode: string = CardDataStore.loadPrivacyMode(context);
    if (mode === 'strict' || mode === 'restricted') {
      const disabled: Record<string, string> = {
        'examsJson': '[]',
        'totalText': '',
        'emptyText': '',
        'privacyDisabledText': mode === 'strict' ?
          '当前隐私设置无法使用卡片' : '限制隐私模式下无法使用该卡片'
      };
      return formBindingData.createFormBindingData(disabled);
    }
    const exams: FinalExamEntry[] = CardDataStore.loadFinalExams(context);
    const upcoming: ExamUpcomingItem[] = [];
    for (const entry of exams) {
      const parsed: Date | null = ExamDateUtils.parseYmd(entry.examDate);
      if (parsed === null) {
        continue;
      }
      const days: number = ExamDateUtils.daysFromDate(parsed);
      if (days < 0) {
        continue;
      }
      const item: ExamUpcomingItem = new ExamUpcomingItem();
      item.entry = entry;
      item.days = days;
      upcoming.push(item);
    }
    upcoming.sort((a: ExamUpcomingItem, b: ExamUpcomingItem): number =>
      a.entry.examDate < b.entry.examDate ? -1 : (a.entry.examDate > b.entry.examDate ? 1 : 0));
    const shown: ExamUpcomingItem[] = upcoming.slice(0, 3);
    const items: ExamCardItem[] = [];
    for (const item of shown) {
      const card: ExamCardItem = new ExamCardItem();
      card.n = item.entry.courseName;
      card.d = ExamDateUtils.formatDisplay(item.entry.examDate);
      card.t = ExamDateUtils.countdownText(item.days);
      card.x = item.days;
      items.push(card);
    }
    let emptyText: string = '';
    if (upcoming.length === 0) {
      emptyText = exams.length > 0 ? '暂无即将到来的期末考试' : '在课表课程详情中设置期末时间';
    }
    hilog.info(DOMAIN, TAG, 'buildExamBindingData exams:%{public}d upcoming:%{public}d shown:%{public}d',
      exams.length, upcoming.length, shown.length);
    const data: Record<string, string> = {
      'examsJson': JSON.stringify(items),
      'totalText': upcoming.length > 0 ? '共' + upcoming.length + '场考试' : '',
      'emptyText': emptyText,
      'privacyDisabledText': ''
    };
    return formBindingData.createFormBindingData(data);
  }

  /** 刷新所有已添加的期末倒计时卡片（期末日期变更、隐私模式切换或系统周期更新时调用） */
  static refreshExamCards(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const ids: string[] = CardDataStore.readExamFormIds(pref);
      if (ids.length === 0) {
        return;
      }
      const binding: formBindingData.FormBindingData = CardDataStore.buildExamBindingData(context);
      for (const id of ids) {
        formProvider.updateForm(id, binding).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'exam updateForm %{public}s failed: %{public}s', id, `${error}`);
          if (`${error}`.includes('does not exist')) {
            CardDataStore.removeExamFormEntry(context, id);
          }
        });
      }
      hilog.info(DOMAIN, TAG, 'refresh exam cards: %{public}s', `${ids.length}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'refreshExamCards failed: %{public}s', `${error}`);
    }
  }

  private static readExamFormIds(pref: preferences.Preferences): string[] {
    const idsJson: string = CardDataStore.readString(pref, KEY_EXAM_FORM_IDS);
    if (idsJson.length === 0) {
      return [];
    }
    try {
      const rawList: string[] = JSON.parse(idsJson) as string[];
      const ids: string[] = [];
      for (const id of rawList) {
        if (typeof id === 'string' && id.length > 0) {
          ids.push(id);
        }
      }
      return ids;
    } catch (error) {
      return [];
    }
  }

  /**
   * 读取卡片登记表；兼容迁移旧 formIds 记录（默认小卡上限）。
   */
  private static readEntries(pref: preferences.Preferences): FormEntry[] {
    const entriesJson: string = CardDataStore.readString(pref, KEY_FORM_ENTRIES);
    if (entriesJson.length > 0) {
      try {
        const rawList: FormEntryRaw[] = JSON.parse(entriesJson) as FormEntryRaw[];
        const entries: FormEntry[] = [];
        for (const item of rawList) {
          if (typeof item.id === 'string' && item.id.length > 0) {
            const entry: FormEntry = new FormEntry();
            entry.id = item.id;
            entry.max = typeof item.max === 'number' && item.max > 0 ? item.max : CardDataStore.MAX_SMALL;
            entries.push(entry);
          }
        }
        if (entries.length > 0) {
          return entries;
        }
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'parse entries failed: %{public}s', `${error}`);
      }
    }
    const legacyIds: string[] = CardDataStore.readFormIds(pref);
    const entries: FormEntry[] = [];
    for (const id of legacyIds) {
      const entry: FormEntry = new FormEntry();
      entry.id = id;
      entry.max = CardDataStore.MAX_SMALL;
      entries.push(entry);
    }
    return entries;
  }

  private static readFormIds(pref: preferences.Preferences): string[] {
    const idsJson: string = CardDataStore.readString(pref, KEY_FORM_IDS);
    if (idsJson.length === 0) {
      return [];
    }
    try {
      const rawList: string[] = JSON.parse(idsJson) as string[];
      const ids: string[] = [];
      for (const id of rawList) {
        if (typeof id === 'string' && id.length > 0) {
          ids.push(id);
        }
      }
      return ids;
    } catch (error) {
      return [];
    }
  }

  private static readString(pref: preferences.Preferences, key: string): string {
    const value: preferences.ValueType = pref.getSync(key, '');
    if (typeof value === 'string') {
      return value;
    }
    return '';
  }

  private static cellInWeek(cell: CardCellItem, week: number): boolean {
    if (week <= 0 || cell.w.length === 0) {
      return true;
    }
    const idx: number = week - 1;
    if (idx >= cell.w.length) {
      return false;
    }
    return cell.w.charAt(idx) === '1';
  }
}
