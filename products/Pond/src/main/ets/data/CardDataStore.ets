import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'CardDataStore';
const DOMAIN: number = 0x0000;
const PREF_NAME: string = 'jw_card_data';
const KEY_PAYLOAD: string = 'payload';
const KEY_FORM_IDS: string = 'formIds';
const KEY_FORM_ENTRIES: string = 'formEntries';

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

interface CardPayloadRaw {
  week?: number;
  cells?: CardCellItem[];
}

interface FormEntryRaw {
  id?: string;
  max?: number;
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
      'todayD': `${today}`
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
