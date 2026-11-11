import { common } from '@kit.AbilityKit';
import { CardDataStore } from './CardDataStore';
import { ReminderScheduler } from './ReminderScheduler';
import { FinalExamEntry } from '../model/JwModels';
import { PrivacyController } from './PrivacyController';
import { JwxtCacheStore } from './JwxtCacheStore';
import { JwxtSessionRepository } from './JwxtSessionRepository';
import { getContext } from '../net/JwTransport';

/**
 * jwxt 教务系统数据仓库（门面层）：
 * 对外保持原有 static API 不变，内部转发到拆分后的模块：
 * 会话/加载/登出 → JwxtSessionRepository；
 * 隐私模式/严格清理 → PrivacyController；
 * 缓存统计与离线缓存 → JwxtCacheStore。
 * 仅调用教务系统真实接口；数据需在 WebView 登录（CAS）获得会话后在线拉取，
 * 未登录或网络失败时进入空数据状态，由界面引导用户登录，不内置任何演示/抓取数据。
 */
export class JwxtRepository {
  // ---------- 会话与加载（转发 JwxtSessionRepository） ----------

  /** 供 UI 层获取主 Ability 上下文（如 openLink 拉起浏览器）；未注入时返回 null */
  static getUiAbilityContext(): common.UIAbilityContext | null {
    return JwxtSessionRepository.getUiAbilityContext();
  }

  /**
   * 注入主 Ability 上下文（PondAbility 启动时调用），
   * 用于服务卡片/离线缓存持久化与通知授权弹窗；
   * 同时把持久化的上课提醒设置载入 AppStorage。
   */
  static attachContext(context: common.UIAbilityContext): void {
    JwxtSessionRepository.attachContext(context);
  }

  /** 教务登录页地址（WebView CAS 登录） */
  static loginUrl(): string {
    return JwxtSessionRepository.loginUrl();
  }

  /** 获取当前教务会话 Cookie（登录页检测会话用） */
  static fetchSessionCookie(): Promise<string> {
    return JwxtSessionRepository.fetchSessionCookie();
  }

  /** 会话有效性探针（currentUser.do，code=="0" 即有效） */
  static async probeSession(): Promise<boolean> {
    return JwxtSessionRepository.probeSession();
  }

  /** 确保数据已加载：仅首次调用生效，此后由 reload 显式刷新 */
  static ensureLoaded(): void {
    JwxtSessionRepository.ensureLoaded();
  }

  /** 重新拉取并返回结果：登录成功、手动刷新、重试时调用 */
  static reload(): Promise<boolean> {
    return JwxtSessionRepository.reload();
  }

  /**
   * 退出登录：清除 WebView 会话 Cookie 与教务登录状态，按隐私模式分级处理数据。
   */
  static logout(): void {
    JwxtSessionRepository.logout();
  }

  /**
   * 应用进入后台或退出（PondAbility 生命周期回调）：
   * 严格隐私模式下清理全部含课程信息的数据并退出登录，下次使用需重新登录。
   */
  static handleAppHide(): void {
    JwxtSessionRepository.handleAppHide();
  }

  /**
   * 重新调度上课提醒（数据同步或应用启动后调用）。
   * 严格隐私模式下不发布任何含课程信息的提醒，并取消全部已有提醒。
   */
  static rescheduleReminders(): void {
    JwxtSessionRepository.rescheduleReminders();
  }

  /** 更新上课提醒设置：写入 AppStorage、持久化并立即重新调度 */
  static updateReminderSettings(enabled: boolean, advanceMinutes: number, agentEnabled: boolean): void {
    JwxtSessionRepository.updateReminderSettings(enabled, advanceMinutes, agentEnabled);
  }

  /** 更新单节课的上课提醒开关（按会话键：课程名|星期|起始节次），写入 AppStorage、持久化并立即重新调度 */
  static updateSessionReminder(sessionKey: string, enabled: boolean): void {
    JwxtSessionRepository.updateSessionReminder(sessionKey, enabled);
  }

  /** 发送一条测试通知（设置页验证通知链路） */
  static sendTestReminder(): void {
    ReminderScheduler.publishTest(getContext());
  }

  // ---------- 隐私与开发者选项（转发 PrivacyController） ----------

  /** 当前隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  static privacyMode(): string {
    return PrivacyController.privacyMode();
  }

  /** 切换开发者选项开关：立即生效并持久化 */
  static updateDeveloperMode(enabled: boolean): void {
    PrivacyController.updateDeveloperMode(enabled);
  }

  /** 切换隐私模式并按模式分级清理 */
  static updatePrivacyMode(mode: string): void {
    PrivacyController.updatePrivacyMode(mode);
  }

  /**
   * 应用回前台（PondAbility onForeground）：更新前台时刻戳，
   * 驱动视图跨天刷新"今日课程"与课表"今天"高亮。
   */
  static notifyForeground(): void {
    PrivacyController.notifyForeground();
  }

  // ---------- 本地缓存（转发 JwxtCacheStore） ----------

  /** 查询本地缓存大小（字节），无上下文时返回 0 */
  static getCacheSizeBytes(): number {
    return JwxtCacheStore.getCacheSizeBytes();
  }

  /** 清理本地缓存 */
  static clearLocalCaches(): void {
    JwxtCacheStore.clearLocalCaches();
  }

  // ---------- 期末考试 ----------

  /** 设置/清除单门课程期末考试日期（examDate 为空表示清除），写入 AppStorage 并持久化 */
  static updateFinalExam(courseName: string, examDate: string): void {
    const exams: FinalExamEntry[] =
      (AppStorage.get<FinalExamEntry[]>('jwFinalExams') ?? []).slice();
    const index: number =
      exams.findIndex((e: FinalExamEntry): boolean => e.courseName === courseName);
    if (examDate.length === 0) {
      if (index >= 0) {
        exams.splice(index, 1);
      }
    } else {
      const entry: FinalExamEntry = new FinalExamEntry();
      entry.courseName = courseName;
      entry.examDate = examDate;
      if (index >= 0) {
        exams[index] = entry;
      } else {
        exams.push(entry);
      }
    }
    AppStorage.setOrCreate('jwFinalExams', exams);
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null && JwxtRepository.privacyMode() === 'standard') {
      CardDataStore.saveFinalExams(context, exams);
      CardDataStore.refreshExamCards(context);
    }
  }
}
