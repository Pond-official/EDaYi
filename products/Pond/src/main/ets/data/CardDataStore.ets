import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppLog } from './AppLog';
import { SecureStore } from './SecureStore';
import { FinalExamEntry } from '../model/JwModels';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { TermWeekUtils } from '../utils/TermWeekUtils';

const TAG: string = 'CardDataStore';
const DOMAIN: number = 0x0000;
const PREF_NAME: string = 'jw_card_data';
const KEY_PAYLOAD: string = 'payload';
const KEY_FORM_IDS: string = 'formIds';
const KEY_FORM_ENTRIES: string = 'formEntries';
const KEY_APP_CACHE: string = 'appCache';
/** 离线缓存归属学号（B1，加密） */
const KEY_CACHE_OWNER_SID: string = 'cacheOwnerSid';
/** 离线缓存归属探针标识（B1，加密；与 KEY_CACHE_OWNER_SID 同步写入/清除） */
const KEY_CACHE_PROBE_UID: string = 'cacheProbeUid';
const KEY_REMINDER_SETTINGS: string = 'reminderSettings';
const KEY_DISABLED_SESSIONS: string = 'reminderDisabledSessions';
const KEY_FINAL_EXAMS: string = 'finalExamDates';
const KEY_PRIVACY_MODE: string = 'privacyMode';
const KEY_EXAM_FORM_IDS: string = 'examFormIds';
const KEY_DEVELOPER_MODE: string = 'developerMode';
const KEY_LIGHT_EFFECT_COLOR: string = 'lightEffectColor';
const KEY_MATERIAL_LEVEL: string = 'materialLevel';
const KEY_CARD_NIGHT: string = 'cardNightTomorrow';
const KEY_BACKGROUND_URI: string = 'appBackgroundUri';
const KEY_BACKGROUND_MODE: string = 'appBackgroundMode';

/** 持久化的课表单元格（紧凑字段，整学期数据，按周位图过滤展示） */
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
  /** 代理提醒（系统后台代理发布，应用退出后仍送达）开关 */
  agentEnabled: boolean = true;
}

/** 2*4 课表小卡"晚间显示明日课程"设置 */
export class CardNightSetting {
  enabled: boolean = false;
  /** 每天开始默认展示明日课程的时刻（当日分钟数，0-1439，默认 1200=20:00） */
  minutes: number = 1200;
}

/** 下发给期末倒计时卡片的条目（紧凑字段） */
export class ExamCardItem {
  n: string = '';
  d: string = '';
  t: string = '';
  x: number = 0;
}

/** 构建期末卡片数据时的中间项（已解析的考试时刻与距考日历天数） */
class ExamUpcomingItem {
  entry: FinalExamEntry = new FinalExamEntry();
  /** 已解析的考试时刻（精确到分钟） */
  date: Date = new Date();
  days: number = 0;
}

interface CardPayloadRaw {
  week?: number;
  anchor?: string;
  cells?: CardCellItem[];
}

interface FormEntryRaw {
  id?: string;
  max?: number;
}

interface ReminderSettingsRaw {
  enabled?: boolean;
  advance?: number;
  agent?: boolean;
}

interface CardNightRaw {
  enabled?: boolean;
  minutes?: number;
}

interface FinalExamRaw {
  course?: string;
  date?: string;
}

/**
 * 服务卡片数据仓库：
 * 主应用同步后把整学期课表（含周次与周一锚点）持久化到 preferences（应用级目录），
 * FormExtensionAbility 在添加/更新卡片时读取，按锚点自推算当前周次，
 * 计算"今日课程"与本周/下周网格推送到卡片。
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
   * 课表卡片数据为高频同步读路径（加卡/每小时刷新/前台跨天），不加密落盘以消除卡片链路解密开销。
   */
  static saveAndRefresh(context: common.Context, payloadJson: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_PAYLOAD, payloadJson);
      pref.flushSync();
      // C1：直接把原串传下去，避免刷新循环每张卡重复读回同一份课表
      CardDataStore.refreshAllCards(context, payloadJson);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveAndRefresh failed: %{public}s', `${error}`);
    }
  }

  /** 保存应用内离线缓存（最近一次同步的完整数据 JSON，含学生身份/成绩等，加密落盘），会话过期时供界面回显 */
  static saveAppCache(context: common.Context, cacheJson: string): void {
    try {
      SecureStore.putString(context, KEY_APP_CACHE, cacheJson);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveAppCache failed: %{public}s', `${error}`);
    }
  }

  static loadAppCache(context: common.Context): string {
    try {
      return SecureStore.getString(context, KEY_APP_CACHE);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadAppCache failed: %{public}s', `${error}`);
      return '';
    }
  }

  static clearAppCache(context: common.Context): void {
    try {
      SecureStore.remove(context, KEY_APP_CACHE);
      // 归属键随缓存一并清除：缓存不存在后归属链无意义（B1）
      SecureStore.remove(context, KEY_CACHE_OWNER_SID);
      SecureStore.remove(context, KEY_CACHE_PROBE_UID);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'clearAppCache failed: %{public}s', `${error}`);
    }
  }

  /**
   * 记录离线缓存归属（B1）：ownerSid=同步时的学号，probeUid=同步时教务探针返回的会话用户标识；
   * 回放前与缓存内学号/当前探针比对，换账号后不再回放上一账号的数据。
   */
  static saveCacheOwner(context: common.Context, ownerSid: string, probeUid: string): void {
    try {
      SecureStore.putString(context, KEY_CACHE_OWNER_SID, ownerSid);
      SecureStore.putString(context, KEY_CACHE_PROBE_UID, probeUid);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveCacheOwner failed: %{public}s', `${error}`);
    }
  }

  /** 读缓存归属学号（未记录/降级返回 ''，调用方按无法验证处理） */
  static loadCacheOwnerSid(context: common.Context): string {
    try {
      return SecureStore.getString(context, KEY_CACHE_OWNER_SID);
    } catch (error) {
      return '';
    }
  }

  /** 读缓存归属探针标识（未记录/降级返回 ''） */
  static loadCacheProbeUid(context: common.Context): string {
    try {
      return SecureStore.getString(context, KEY_CACHE_PROBE_UID);
    } catch (error) {
      return '';
    }
  }

  /** 断开缓存归属链（退出登录时调用）：保留缓存供界面继续显示，但不再允许后续回放 */
  static clearCacheOwner(context: common.Context): void {
    try {
      SecureStore.remove(context, KEY_CACHE_OWNER_SID);
      SecureStore.remove(context, KEY_CACHE_PROBE_UID);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'clearCacheOwner failed: %{public}s', `${error}`);
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
        settings.agentEnabled = typeof raw.agent === 'boolean' ? raw.agent : true;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadReminderSettings failed: %{public}s', `${error}`);
    }
    return settings;
  }

  /** 保存上课提醒设置 */
  static saveReminderSettings(context: common.Context, enabled: boolean, advanceMinutes: number,
    agentEnabled: boolean): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const payload: ReminderSettingsRaw = { enabled: enabled, advance: advanceMinutes, agent: agentEnabled };
      pref.putSync(KEY_REMINDER_SETTINGS, JSON.stringify(payload));
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveReminderSettings failed: %{public}s', `${error}`);
    }
  }

  /** 读取小卡"晚间显示明日课程"设置（未配置时返回默认值：关闭、20:00） */
  static loadCardNightSetting(context: common.Context): CardNightSetting {
    const setting: CardNightSetting = new CardNightSetting();
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const json: string = CardDataStore.readString(pref, KEY_CARD_NIGHT);
      if (json.length > 0) {
        const raw: CardNightRaw = JSON.parse(json) as CardNightRaw;
        setting.enabled = typeof raw.enabled === 'boolean' ? raw.enabled : false;
        setting.minutes = typeof raw.minutes === 'number' && raw.minutes >= 0 && raw.minutes <= 1439
          ? Math.floor(raw.minutes) : 1200;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadCardNightSetting failed: %{public}s', `${error}`);
    }
    return setting;
  }

  /** 保存小卡"晚间显示明日课程"设置 */
  static saveCardNightSetting(context: common.Context, enabled: boolean, minutes: number): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const payload: CardNightRaw = { enabled: enabled, minutes: minutes };
      pref.putSync(KEY_CARD_NIGHT, JSON.stringify(payload));
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveCardNightSetting failed: %{public}s', `${error}`);
    }
  }

  /** 读取被单独关闭上课提醒的课程名单（按会话键：课程名|星期|起始节次，默认空 = 全部跟随全局开关） */
  static loadDisabledSessions(context: common.Context): string[] {
    const result: string[] = [];
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const json: string = CardDataStore.readString(pref, KEY_DISABLED_SESSIONS);
      if (json.length > 0) {
        const raw: Object[] = JSON.parse(json) as Object[];
        for (const item of raw) {
          if (typeof item === 'string') {
            result.push(item);
          }
        }
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadDisabledSessions failed: %{public}s', `${error}`);
    }
    return result;
  }

  /** 保存被单独关闭上课提醒的课程名单（按会话键） */
  static saveDisabledSessions(context: common.Context, sessionKeys: string[]): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_DISABLED_SESSIONS, JSON.stringify(sessionKeys));
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveDisabledSessions failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'loadFinalExams failed: %{public}s', `${error}`);
    }
    return result;
  }

  /** 保存各课程期末考试日期设置 */
  static saveFinalExams(context: common.Context, exams: FinalExamEntry[]): void {
    try {
      const raw: FinalExamRaw[] = [];
      for (const entry of exams) {
        raw.push({ course: entry.courseName, date: entry.examDate });
      }
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_FINAL_EXAMS, JSON.stringify(raw));
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveFinalExams failed: %{public}s', `${error}`);
    }
  }

  /**
   * 合并导入期末考试时间（分享目标页确认导入时调用）：按课程名 upsert，返回发生变化的条目数。
   * 基线取本机持久化数据（主应用可能未运行，AppStorage 基线可能为空，不能以之为准覆盖落盘）；
   * 始终同步 AppStorage（主应用在运行则页面/卡片即时刷新）；
   * 标准隐私模式才持久化并刷新期末倒计时卡片，限制/严格模式与主应用「设置考试时间」行为一致（不落盘）。
   */
  static importFinalExams(context: common.Context, incoming: FinalExamEntry[]): number {
    const mode: string = CardDataStore.loadPrivacyMode(context);
    const merged: FinalExamEntry[] = mode === 'standard'
      ? CardDataStore.loadFinalExams(context)
      : (AppStorage.get<FinalExamEntry[]>('jwFinalExams') ?? []).slice();
    let changed: number = 0;
    for (const entry of incoming) {
      const index: number = merged.findIndex((e: FinalExamEntry): boolean => e.courseName === entry.courseName);
      if (index >= 0) {
        if (merged[index].examDate !== entry.examDate) {
          merged[index] = entry;
          changed += 1;
        }
      } else {
        merged.push(entry);
        changed += 1;
      }
    }
    AppStorage.setOrCreate('jwFinalExams', merged);
    if (mode === 'standard') {
      CardDataStore.saveFinalExams(context, merged);
      CardDataStore.refreshExamCards(context);
    }
    return changed;
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
      AppLog.error(DOMAIN, TAG, 'loadPrivacyMode failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'savePrivacyMode failed: %{public}s', `${error}`);
    }
  }

  /** 读取开发者选项是否已开启（连续点击版本号 5 次开启，未配置默认关闭） */
  static loadDeveloperMode(context: common.Context): boolean {
    let enabled: boolean = false;
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const value: preferences.ValueType = pref.getSync(KEY_DEVELOPER_MODE, false);
      if (typeof value === 'boolean') {
        enabled = value;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadDeveloperMode failed: %{public}s', `${error}`);
    }
    return enabled;
  }

  /** 保存开发者选项开关状态 */
  static saveDeveloperMode(context: common.Context, enabled: boolean): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_DEVELOPER_MODE, enabled);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveDeveloperMode failed: %{public}s', `${error}`);
    }
  }

  /** 读取底栏光效颜色（#RRGGBB 十六进制串，未配置默认白色） */
  static loadLightEffectColor(context: common.Context): string {
    let color: string = '#FFFFFF';
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const stored: string = CardDataStore.readString(pref, KEY_LIGHT_EFFECT_COLOR);
      if (/^#[0-9A-Fa-f]{6}$/.test(stored)) {
        color = stored;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadLightEffectColor failed: %{public}s', `${error}`);
    }
    return color;
  }

  /** 保存底栏光效颜色（#RRGGBB 十六进制串） */
  static saveLightEffectColor(context: common.Context, color: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_LIGHT_EFFECT_COLOR, color);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveLightEffectColor failed: %{public}s', `${error}`);
    }
  }

  /** 读取底栏材质档位（ADAPTIVE/EXQUISITE/GENTLE/SMOOTH，未配置默认 ADAPTIVE） */
  static loadMaterialLevel(context: common.Context): string {
    let level: string = 'ADAPTIVE';
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const stored: string = CardDataStore.readString(pref, KEY_MATERIAL_LEVEL);
      if (stored === 'ADAPTIVE' || stored === 'EXQUISITE' || stored === 'GENTLE' || stored === 'SMOOTH') {
        level = stored;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadMaterialLevel failed: %{public}s', `${error}`);
    }
    return level;
  }

  /** 保存底栏材质档位（ADAPTIVE/EXQUISITE/GENTLE/SMOOTH） */
  static saveMaterialLevel(context: common.Context, level: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_MATERIAL_LEVEL, level);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveMaterialLevel failed: %{public}s', `${error}`);
    }
  }

  /** 读取自定义背景图片沙箱路径（未设置返回空串） */
  static loadBackgroundUri(context: common.Context): string {
    let uri: string = '';
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const stored: string = CardDataStore.readString(pref, KEY_BACKGROUND_URI);
      if (stored.length > 0 && fs.accessSync(stored)) {
        uri = stored;
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadBackgroundUri failed: %{public}s', `${error}`);
    }
    return uri;
  }

  /** 保存自定义背景图片沙箱路径（空串表示未设置） */
  static saveBackgroundUri(context: common.Context, uri: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_BACKGROUND_URI, uri);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveBackgroundUri failed: %{public}s', `${error}`);
    }
  }

  /** 删除沙箱内已导入的背景图片文件（保留 keepPath 指定的文件） */
  private static removeBackgroundFiles(context: common.Context, keepPath: string): void {
    try {
      const names: string[] = fs.listFileSync(context.filesDir);
      for (let i: number = 0; i < names.length; i++) {
        if (names[i].startsWith('app_background.')) {
          const filePath: string = `${context.filesDir}/${names[i]}`;
          if (filePath !== keepPath) {
            try {
              fs.unlinkSync(filePath);
            } catch (unlinkError) {
              AppLog.warn(DOMAIN, TAG, 'removeBackgroundFiles unlink failed: %{public}s', `${unlinkError}`);
            }
          }
        }
      }
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'removeBackgroundFiles failed: %{public}s', `${error}`);
    }
  }

  /** 读取自定义背景模式（system=跟随系统 / white=纯白 / image=自定义图片），mode=image 且图片缺失时回退 system */
  static loadBackgroundMode(context: common.Context): string {
    let mode: string = 'system';
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const stored: string = CardDataStore.readString(pref, KEY_BACKGROUND_MODE);
      if (stored === 'system' || stored === 'white' || stored === 'image') {
        mode = stored;
      }
      if (mode === 'image' && CardDataStore.loadBackgroundUri(context) === '') {
        mode = 'system';
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadBackgroundMode failed: %{public}s', `${error}`);
    }
    return mode;
  }

  /** 保存背景模式（system/white/image） */
  static saveBackgroundMode(context: common.Context, mode: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.putSync(KEY_BACKGROUND_MODE, mode);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'saveBackgroundMode failed: %{public}s', `${error}`);
    }
  }

  /** 从相册 URI 导入背景图片到应用沙箱（filesDir），持久化并返回沙箱路径（失败返回空串） */
  static importBackgroundImage(context: common.Context, srcUri: string): string {
    try {
      const extStart: number = srcUri.lastIndexOf('.');
      const rawExt: string = extStart >= 0 ? srcUri.substring(extStart + 1).toLowerCase() : '';
      const ext: string = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'].indexOf(rawExt) >= 0 ? rawExt : 'jpg';
      const destPath: string = `${context.filesDir}/app_background.${ext}`;
      const srcFile: fs.File = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      try {
        fs.copyFileSync(srcFile.fd, destPath);
      } finally {
        fs.closeSync(srcFile);
      }
      CardDataStore.removeBackgroundFiles(context, destPath);
      CardDataStore.saveBackgroundUri(context, destPath);
      return destPath;
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'importBackgroundImage failed: %{public}s', `${error}`);
      return '';
    }
  }

  /** 清除持久化的卡片课表数据（严格隐私模式启用或退至后台时调用） */
  static clearCardPayload(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_PAYLOAD);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'clearCardPayload failed: %{public}s', `${error}`);
    }
  }

  /** 清除期末考试日期设置（严格隐私模式清理时调用） */
  static clearFinalExams(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_FINAL_EXAMS);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'clearFinalExams failed: %{public}s', `${error}`);
    }
  }

  /** 清除单课提醒关闭名单（严格隐私模式清理时调用） */
  static clearDisabledSessions(context: common.Context): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      pref.deleteSync(KEY_DISABLED_SESSIONS);
      pref.flushSync();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'clearDisabledSessions failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'addFormEntry failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'removeFormEntry failed: %{public}s', `${error}`);
    }
  }

  /** buildBindingData 复用取时实例：系统周期触发（约每小时）串行调用，进入时 setTime 重设；
   *  仅在同一线程同步窗口内读取，无并发共享风险 */
  private static readonly nowScratch: Date = new Date();

  /**
   * 构建卡片绑定数据：解析持久化的整学期课表，按周一锚点自推算当前周次
   * （卡片更新不依赖打开应用，跨周时与主应用同规则推进），
   * 计算今日/明日课程（按卡片上限截断，超出记余量）
   * 与本周/下周周网格数据（供卡片切换查看下周、明天）。
   * @param payloadJson 调用方已持有的课表原文（C1：批量刷新时传入避免逐卡重复读取），未传则自行读取
   */
  static buildBindingData(context: common.Context, maxCourses: number,
    payloadJson?: string): formBindingData.FormBindingData {
    if (CardDataStore.loadPrivacyMode(context) === 'strict') {
      const disabled: Record<string, string> = {
        'weekText': '',
        'coursesJson': '[]',
        'moreText': '',
        'emptyText': '',
        'tomorrowJson': '[]',
        'tomorrowMoreText': '',
        'tomorrowEmptyText': '',
        'tomorrowWeekText': '',
        'weekCellsJson': '[]',
        'nextWeekCellsJson': '[]',
        'nextWeekText': '',
        'todayD': '0',
        'tomorrowDefault': 'false',
        'privacyDisabledText': '当前隐私设置无法使用卡片'
      };
      return formBindingData.createFormBindingData(disabled);
    }
    let week: number = 0;
    let anchor: string = '';
    let cells: CardCellItem[] = [];
    try {
      let storedPayload: string = payloadJson ?? '';
      if (storedPayload.length === 0) {
        const pref: preferences.Preferences = CardDataStore.store(context);
        storedPayload = CardDataStore.readString(pref, KEY_PAYLOAD);
      }
      // 旧版本曾加密本键：迁移完成前读到密文按未同步处理（主应用 hydrate 后自动转明文），不误报"无课"
      if (storedPayload.length > 0 && !SecureStore.isEnvelopeValue(storedPayload)) {
        const raw: CardPayloadRaw = JSON.parse(storedPayload) as CardPayloadRaw;
        week = raw.week ?? 0;
        anchor = raw.anchor ?? '';
        cells = raw.cells ?? [];
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'read payload failed: %{public}s', `${error}`);
    }
    // 跨周自推进：卡片更新由系统周期触发（约每小时），不依赖打开应用；
    // 以最近同步的周一锚点推算经过的整周数，与应用内 advanceTermWeek 同规则
    const now: Date = CardDataStore.nowScratch;
    now.setTime(Date.now());
    if (anchor.length > 0) {
      const advanced: number | null = TermWeekUtils.weeksBetween(anchor, now);
      if (advanced !== null && advanced > 0) {
        week += advanced;
      }
    }
    const day: number = now.getDay();
    const today: number = day === 0 ? 7 : day;
    const tomorrow: number = today === 7 ? 1 : today + 1;
    const tomorrowWeek: number = today === 7 ? week + 1 : week;
    // 设置页"晚间显示明日课程"：到设定时刻后下发 tomorrowDefault=true，卡片据此默认展示明日课程
    const night: CardNightSetting = CardDataStore.loadCardNightSetting(context);
    const nowMinutes: number = now.getHours() * 60 + now.getMinutes();
    const tomorrowDefault: boolean = night.enabled && nowMinutes >= night.minutes;
    const todayCells: CardCellItem[] = cells
      .filter((c: CardCellItem): boolean => c.d === today && CardDataStore.cellInWeek(c, week))
      .sort((a: CardCellItem, b: CardCellItem): number => a.s - b.s);
    const tomorrowCells: CardCellItem[] = cells
      .filter((c: CardCellItem): boolean => c.d === tomorrow && CardDataStore.cellInWeek(c, tomorrowWeek))
      .sort((a: CardCellItem, b: CardCellItem): number => a.s - b.s);
    const more: number = Math.max(0, todayCells.length - maxCourses);
    const tomorrowMore: number = Math.max(0, tomorrowCells.length - maxCourses);
    AppLog.info(DOMAIN, TAG,
      'buildBindingData max:%{public}d week:%{public}d cells:%{public}d todayCells:%{public}d tomorrowCells:%{public}d',
      maxCourses, week, cells.length, todayCells.length, tomorrowCells.length);
    const courseData: CardCourseData[] =
      CardDataStore.toCourseData(todayCells.slice(0, maxCourses));
    const tomorrowData: CardCourseData[] =
      CardDataStore.toCourseData(tomorrowCells.slice(0, maxCourses));
    const gridCells: WeekCellData[] = CardDataStore.toGridCells(
      cells.filter((c: CardCellItem): boolean => CardDataStore.cellInWeek(c, week)));
    const nextGridCells: WeekCellData[] = CardDataStore.toGridCells(
      cells.filter((c: CardCellItem): boolean => CardDataStore.cellInWeek(c, week + 1)));
    // 区分"从未同步"（无周次信息）与"已同步但今日无课"：前者引导登录同步，后者提示无课
    const neverSynced: boolean = week <= 0;
    const data: Record<string, string> = {
      'weekText': week > 0 ? '第' + week + '周' : '',
      'coursesJson': JSON.stringify(courseData),
      'moreText': more > 0 ? '还有' + more + '门课' : '',
      'emptyText': neverSynced ? '登录教务系统后同步课表'
        : (todayCells.length === 0 ? '今天没有课程安排' : ''),
      'tomorrowJson': JSON.stringify(tomorrowData),
      'tomorrowMoreText': tomorrowMore > 0 ? '还有' + tomorrowMore + '门课' : '',
      'tomorrowEmptyText': neverSynced ? '登录教务系统后同步课表'
        : (tomorrowCells.length === 0 ? '明天没有课程安排' : ''),
      'tomorrowWeekText': week > 0 ? '第' + tomorrowWeek + '周' : '',
      'weekCellsJson': JSON.stringify(gridCells),
      'nextWeekCellsJson': JSON.stringify(nextGridCells),
      'nextWeekText': week > 0 ? '第' + (week + 1) + '周' : '',
      'todayD': `${today}`,
      'tomorrowDefault': tomorrowDefault ? 'true' : 'false',
      'privacyDisabledText': ''
    };
    return formBindingData.createFormBindingData(data);
  }

  private static toCourseData(shown: CardCellItem[]): CardCourseData[] {
    const courseData: CardCourseData[] = [];
    for (const cell of shown) {
      const course: CardCourseData = new CardCourseData();
      course.time = cell.t;
      course.name = cell.n;
      course.place = cell.p;
      courseData.push(course);
    }
    return courseData;
  }

  private static toGridCells(weekCells: CardCellItem[]): WeekCellData[] {
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
    return gridCells;
  }

  /**
   * 刷新所有已添加的卡片（数据变更后由主应用调用）。
   * @param payloadJson 调用方已持有的课表原文（C1：批量刷新时传入避免逐卡重复读取），未传则各卡自行读取
   */
  static refreshAllCards(context: common.Context, payloadJson?: string): void {
    try {
      const pref: preferences.Preferences = CardDataStore.store(context);
      const entries: FormEntry[] = CardDataStore.readEntries(pref);
      if (entries.length === 0) {
        return;
      }
      for (const entry of entries) {
        const binding: formBindingData.FormBindingData =
          CardDataStore.buildBindingData(context, entry.max, payloadJson);
        formProvider.updateForm(entry.id, binding).catch((error: Error) => {
          AppLog.error(DOMAIN, TAG, 'updateForm %{public}s failed: %{public}s', entry.id, `${error}`);
          if (`${error}`.includes('does not exist')) {
            CardDataStore.removeFormEntry(context, entry.id);
          }
        });
      }
      AppLog.info(DOMAIN, TAG, 'refresh cards: %{public}s', `${entries.length}`);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'refreshAllCards failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'addExamFormEntry failed: %{public}s', `${error}`);
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
      AppLog.error(DOMAIN, TAG, 'removeExamFormEntry failed: %{public}s', `${error}`);
    }
  }

  /**
   * 构建期末倒计时卡片绑定数据：
   * 严格/限制隐私模式下返回不可用提示（期末日期仅标准模式缓存）；
   * 否则读取持久化的期末日期，过滤已结束科目，按考试时间从近到远
   * 取最近 10 条（含距考天数驱动的徽配色信息），卡片按自身高度自适应
   * 展示尽可能多的条目，无数据时返回空态文案。
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
      const parsed: Date | null = ExamDateUtils.parseExamDate(entry.examDate);
      if (parsed === null) {
        continue;
      }
      if (ExamDateUtils.remainingMs(parsed) <= 0) {
        continue;
      }
      const item: ExamUpcomingItem = new ExamUpcomingItem();
      item.entry = entry;
      item.date = parsed;
      item.days = ExamDateUtils.calendarDaysFrom(parsed);
      upcoming.push(item);
    }
    upcoming.sort((a: ExamUpcomingItem, b: ExamUpcomingItem): number => a.date.getTime() - b.date.getTime());
    const shown: ExamUpcomingItem[] = upcoming.slice(0, 10);
    const items: ExamCardItem[] = [];
    for (const item of shown) {
      const card: ExamCardItem = new ExamCardItem();
      card.n = item.entry.courseName;
      card.d = ExamDateUtils.formatDisplay(item.entry.examDate);
      card.t = ExamDateUtils.countdownTextOf(item.date);
      card.x = item.days;
      items.push(card);
    }
    let emptyText: string = '';
    if (upcoming.length === 0) {
      emptyText = exams.length > 0 ? '暂无即将到来的期末考试' : '在"设置-期末倒计时"中设置考试时间';
    }
    AppLog.info(DOMAIN, TAG, 'buildExamBindingData exams:%{public}d upcoming:%{public}d shown:%{public}d',
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
          AppLog.error(DOMAIN, TAG, 'exam updateForm %{public}s failed: %{public}s', id, `${error}`);
          if (`${error}`.includes('does not exist')) {
            CardDataStore.removeExamFormEntry(context, id);
          }
        });
      }
      AppLog.info(DOMAIN, TAG, 'refresh exam cards: %{public}s', `${ids.length}`);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'refreshExamCards failed: %{public}s', `${error}`);
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
        AppLog.error(DOMAIN, TAG, 'parse entries failed: %{public}s', `${error}`);
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
    // 无位图时无法判断，保守视为有课；有位图但周次未知（<=0）时不可归入本周，宁可不放行
    if (cell.w.length === 0) {
      return true;
    }
    if (week <= 0) {
      return false;
    }
    const idx: number = week - 1;
    if (idx >= cell.w.length) {
      return false;
    }
    return cell.w.charAt(idx) === '1';
  }
}
