import { webview } from '@kit.ArkWeb';
import { AppLog } from './AppLog';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { CardDataStore, ReminderSettings } from './CardDataStore';
import { ReminderScheduler } from './ReminderScheduler';
import { GradeCategory, GradeEntry, PlanCategory, ScheduleCellInfo, SectionTimeInfo, StudentProfile, TermStatus } from '../model/JwModels';
import { CurrentUserRaw, GradeEnvelopeRaw, GradeReportRaw, ScheduleEnvelopeRaw, StudentEnvelopeRaw, TermQueryRaw, TermRowRaw } from '../model/JwRawModels';
import { parseScheduleCells, parseSections, filterCurrentAndNextWeek } from '../jwxt/parsers/ScheduleParser';
import { parseGrades, parseGradeCategories } from '../jwxt/parsers/GradeParser';
import { parseTrainingPlan, extractPyfadm } from '../jwxt/parsers/TrainingPlanParser';
import { parseStudent } from '../jwxt/parsers/StudentParser';
import { ZcpRepository } from './ZcpRepository';
import { PrivacyController } from './PrivacyController';
import { JwxtCacheStore } from './JwxtCacheStore';
import { JW_APP_ROOT, postForm, getForm, getContext, attachContext as transportAttachContext, clearLastCookie } from '../net/JwTransport';

const JW_LOGIN_URL: string = JW_APP_ROOT + '/sys/homeapp/index.do';
const JW_CURRENT_USER: string = '/sys/homeapp/api/home/currentUser.do';
const JW_ROLE_ID: string = '211f2678b90149c395a84fe610a3f9cd';
const JW_SET_APP_ROLE: string = '/sys/jwpubapp/pub/setJwCommonAppRole.do';
const JW_SCHEDULE_DETAIL: string = '/sys/kbapp/api/wdkbcx/getMyScheduleDetail.do';
const JW_SCHEDULE_SECTIONS: string = '/sys/kbapp/api/wdkbcx/getMySectionList.do';
const JW_QUERY_GRADES: string = '/sys/byshapp/api/grbg/queryXyzhbx.do';
const JW_QUERY_STUDENT: string = '/sys/byshapp/api/grbg/queryXsjbxx.do';
const JW_QUERY_CURRENT_TERM: string = '/sys/jwpubapp/modules/gg/cxmrxnxq.do';
const TAG: string = 'JwxtRepository';
const DOMAIN: number = 0x0000;

/**
 * 教务会话仓库（自 JwxtRepository 拆出）：
 * 持有加载状态（currentLoad/loadedOnce/pendingReload），
 * 负责会话探测、登录地址与 Cookie 获取、在线同步加载周期、
 * 退出登录（按隐私模式分级处理）与上课提醒调度。
 */
export class JwxtSessionRepository {
  private static currentLoad: Promise<boolean> | null = null;
  private static loadedOnce: boolean = false;
  private static pendingReload: boolean = false;

  /** 供 UI 层获取主 Ability 上下文（如 openLink 拉起浏览器）；未注入时返回 null */
  static getUiAbilityContext(): common.UIAbilityContext | null {
    return getContext();
  }

  /**
   * 注入主 Ability 上下文（PondAbility 启动时调用），
   * 用于服务卡片/离线缓存持久化与通知授权弹窗；
   * 同时把持久化的上课提醒设置载入 AppStorage。
   */
  static attachContext(context: common.UIAbilityContext): void {
    transportAttachContext(context);
    const settings: ReminderSettings = CardDataStore.loadReminderSettings(context);
    AppStorage.setOrCreate('jwReminderEnabled', settings.enabled);
    AppStorage.setOrCreate('jwReminderAdvance', settings.advanceMinutes);
    AppStorage.setOrCreate('jwReminderAgentEnabled', settings.agentEnabled);
    AppStorage.setOrCreate('jwReminderDisabledSessions', CardDataStore.loadDisabledSessions(context));
    AppStorage.setOrCreate('jwFinalExams', CardDataStore.loadFinalExams(context));
    AppStorage.setOrCreate('jwPrivacyMode', CardDataStore.loadPrivacyMode(context));
    AppStorage.setOrCreate('jwDeveloperMode', CardDataStore.loadDeveloperMode(context));
  }

  static loginUrl(): string {
    return JW_LOGIN_URL;
  }

  static async fetchSessionCookie(): Promise<string> {
    const cookie: string = webview.WebCookieManager.fetchCookieSync(JW_APP_ROOT + '/');
    return cookie;
  }

  /**
   * 会话有效性探针（currentUser.do，code=="0" 即有效）。
   * 记录返回码/长度/解析失败片段，用于诊断登录探测不生效的设备差异。
   */
  static async probeSession(): Promise<boolean> {
    try {
      const text: string = await getForm(JW_CURRENT_USER);
      let code: string = '';
      let ok: boolean = false;
      try {
        const raw: CurrentUserRaw = JSON.parse(text) as CurrentUserRaw;
        code = raw.code ?? '';
        ok = raw.code === '0' && raw.datas !== undefined && raw.datas.userId !== undefined;
      } catch (parseError) {
        AppLog.error(DOMAIN, TAG,
          'probe: json parse failed, len=%{public}s, head=%{public}s',
          `${text.length}`, text.length > 0 ? text.substring(0, 80) : '(empty)');
        return false;
      }
      AppLog.info(DOMAIN, TAG, 'probe: code=%{public}s len=%{public}s ok=%{public}s',
        code, `${text.length}`, `${ok}`);
      return ok;
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'probeSession failed: %{public}s', `${error}`);
      return false;
    }
  }

  /**
   * 确保数据已加载：仅首次调用生效，此后由 reload 显式刷新。
   */
  static ensureLoaded(): void {
    if (JwxtSessionRepository.loadedOnce || JwxtSessionRepository.currentLoad !== null) {
      return;
    }
    JwxtSessionRepository.reload();
  }

  /**
   * 重新拉取并返回结果：登录成功、手动刷新、重试时调用。
   * 若已有加载在途则排队（pendingReload），完成后自动补拉，并返回在途 Promise。
   */
  static reload(): Promise<boolean> {
    if (JwxtSessionRepository.currentLoad !== null) {
      JwxtSessionRepository.pendingReload = true;
      return JwxtSessionRepository.currentLoad;
    }
    const load: Promise<boolean> = JwxtSessionRepository.runLoadCycle();
    JwxtSessionRepository.currentLoad = load;
    load.then((ok: boolean) => {
      JwxtSessionRepository.currentLoad = null;
      if (JwxtSessionRepository.pendingReload) {
        JwxtSessionRepository.pendingReload = false;
        JwxtSessionRepository.reload();
      }
    });
    return load;
  }

  private static async runLoadCycle(): Promise<boolean> {
    let ok: boolean = false;
    try {
      ok = await JwxtSessionRepository.tryLoadOnline();
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'load cycle error: %{public}s', `${error}`);
      ok = false;
    }
    if (!ok) {
      // 回放离线缓存成功时置位 loadedOnce（原实现写在 applyAppCache 内部，行为等价）
      if (!JwxtCacheStore.applyAppCache()) {
        JwxtSessionRepository.applyEmpty('offline');
      } else {
        JwxtSessionRepository.loadedOnce = true;
      }
    } else {
      JwxtCacheStore.persistCardData();
      JwxtCacheStore.persistAppCache();
    }
    JwxtSessionRepository.rescheduleReminders();
    return ok;
  }

  /**
   * 重新调度上课提醒（数据同步或应用启动后调用）。
   * 严格隐私模式下不发布任何含课程信息的提醒，并取消全部已有提醒。
   */
  static rescheduleReminders(): void {
    if (PrivacyController.privacyMode() === 'strict') {
      AppStorage.setOrCreate('jwNextReminder', '');
      ReminderScheduler.cancelAll();
      return;
    }
    ReminderScheduler.schedule(
      AppStorage.get<ScheduleCellInfo[]>('jwSchedule') ?? [],
      AppStorage.get<TermStatus>('jwTerm') ?? new TermStatus(),
      getContext()
    );
  }

  /** 更新上课提醒设置：写入 AppStorage、持久化并立即重新调度 */
  static updateReminderSettings(enabled: boolean, advanceMinutes: number, agentEnabled: boolean): void {
    AppStorage.setOrCreate('jwReminderEnabled', enabled);
    AppStorage.setOrCreate('jwReminderAdvance', advanceMinutes);
    AppStorage.setOrCreate('jwReminderAgentEnabled', agentEnabled);
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null) {
      CardDataStore.saveReminderSettings(context, enabled, advanceMinutes, agentEnabled);
    }
    JwxtSessionRepository.rescheduleReminders();
  }

  /** 更新单节课的上课提醒开关（按会话键：课程名|星期|起始节次），写入 AppStorage、持久化并立即重新调度 */
  static updateSessionReminder(sessionKey: string, enabled: boolean): void {
    const disabled: string[] =
      (AppStorage.get<string[]>('jwReminderDisabledSessions') ?? []).slice();
    const index: number = disabled.indexOf(sessionKey);
    if (enabled) {
      if (index >= 0) {
        disabled.splice(index, 1);
      }
    } else {
      if (index < 0) {
        disabled.push(sessionKey);
      }
    }
    AppStorage.setOrCreate('jwReminderDisabledSessions', disabled);
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null && PrivacyController.privacyMode() === 'standard') {
      CardDataStore.saveDisabledSessions(context, disabled);
    }
    JwxtSessionRepository.rescheduleReminders();
  }

  /**
   * 应用进入后台或退出（PondAbility 生命周期回调）：
   * 严格隐私模式下清理全部含课程信息的数据并退出登录，下次使用需重新登录。
   */
  static handleAppHide(): void {
    if (PrivacyController.privacyMode() !== 'strict') {
      return;
    }
    AppLog.info(DOMAIN, TAG, 'strict privacy: cleanup and logout on app hide');
    JwxtSessionRepository.logout();
  }

  /**
   * 退出登录：清除 WebView 会话 Cookie 与教务登录状态，按隐私模式分级处理数据：
   * 标准模式保留应用内离线缓存与内存数据，页面继续显示离线数据（横幅切换为离线提示）；
   * 限制模式清除课表以外的离线缓存与内存数据（页面不再显示数据），桌面课表卡片不受影响；
   * 严格模式进一步清除桌面课表卡片等全部含课程信息的数据并刷新卡片。
   */
  static logout(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLog.error(DOMAIN, TAG, "clearAllCookiesSync failed: %{public}s %{public}s", `${err.code}`, `${err.message}`);
    }
    clearLastCookie();
    const mode: string = PrivacyController.privacyMode();
    if (mode === 'standard') {
      // 保留离线数据：仅失效 xgfw 会话标记，页面继续显示已获取的离线数据
      ZcpRepository.invalidateSession();
      AppStorage.setOrCreate<string>('jwDataMode', 'offlineCache');
      AppStorage.setOrCreate<boolean>('jwLoaded', true);
      return;
    }
    if (mode === 'strict') {
      PrivacyController.clearStrictData();
      JwxtSessionRepository.applyEmpty('offline');
      return;
    }
    // 限制模式：清除课表以外的离线缓存与内存数据，桌面课表卡片不受影响
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null) {
      CardDataStore.clearAppCache(context);
    }
    ZcpRepository.clearSession();
    ZcpRepository.clearCache();
    JwxtSessionRepository.applyEmpty('offline');
  }

  private static async tryLoadOnline(): Promise<boolean> {
    if (!await JwxtSessionRepository.probeSession()) {
      AppLog.error(DOMAIN, TAG, 'tryLoadOnline stop: probe failed, not logged in');
      return false;
    }
    try {
      await postForm(JW_SET_APP_ROLE, 'ROLEID=' + JW_ROLE_ID);
      AppLog.info(DOMAIN, TAG, 'step: role set');

      const userText: string = await getForm(JW_CURRENT_USER);
      const userRaw: CurrentUserRaw = JSON.parse(userText) as CurrentUserRaw;
      const currentWeek: number = userRaw.datas?.welcomeInfo?.classWeek ?? 0;
      let termCode: string = userRaw.datas?.welcomeInfo?.xnxqdm ?? '';
      let termName: string = userRaw.datas?.welcomeInfo?.xnxqmc ?? '';
      if (termName.length === 0) {
        termName = termCode;
      }

      try {
        const termText: string =
          await postForm(JW_QUERY_CURRENT_TERM, 'CSDM=SYS&ZCSDM=DQXNXQDM&SFSY=1');
        const termRaw: TermQueryRaw = JSON.parse(termText) as TermQueryRaw;
        const rows: TermRowRaw[] | undefined = termRaw.datas?.cxmrxnxq?.rows;
        if (rows !== undefined && rows.length > 0) {
          const rowCode: string | undefined = rows[0].XNXQDM;
          if (rowCode !== undefined && rowCode.length > 0) {
            termCode = rowCode;
            const rowName: string | undefined = rows[0].XNXQMC;
            termName = rowName !== undefined && rowName.length > 0 ? rowName : rowCode;
          }
        }
      } catch (termError) {
        AppLog.error(DOMAIN, TAG, 'term query failed, keep welcomeInfo term: %{public}s', `${termError}`);
      }

      if (termCode.length === 0) {
        AppLog.error(DOMAIN, TAG, 'tryLoadOnline stop: no term code');
        return false;
      }
      AppLog.info(DOMAIN, TAG, 'step: term %{public}s', termCode);

      const studentText: string = await postForm(JW_QUERY_STUDENT, '');
      const studentEnvelope: StudentEnvelopeRaw = JSON.parse(studentText) as StudentEnvelopeRaw;
      const student: StudentProfile = parseStudent(studentEnvelope.datas?.queryXsjbxx?.jbxx);
      const pyfadm: string = extractPyfadm(studentEnvelope.datas?.queryXsjbxx?.faArr);
      if (userRaw.datas?.userName !== undefined && student.name.length === 0) {
        student.name = userRaw.datas.userName;
      }
      AppLog.info(DOMAIN, TAG, 'step: student %{public}s pyfadm=%{public}s', student.name, pyfadm);

      const scheduleText: string =
        await postForm(JW_SCHEDULE_DETAIL, 'XNXQDM=' + termCode + '&XQDM=1');
      const sectionsText: string =
        await postForm(JW_SCHEDULE_SECTIONS, 'XNXQDM=' + termCode + '&XQDM=1');
      const scheduleEnvelope: ScheduleEnvelopeRaw = JSON.parse(scheduleText) as ScheduleEnvelopeRaw;
      const scheduleCells: ScheduleCellInfo[] =
        parseScheduleCells(scheduleEnvelope.datas?.getMyScheduleDetail?.arrangedList);

      const sectionsEnvelope: ScheduleEnvelopeRaw = JSON.parse(sectionsText) as ScheduleEnvelopeRaw;
      const sections: SectionTimeInfo[] =
        parseSections(scheduleCells, sectionsEnvelope.datas?.getMySectionList);
      // 仅保留当前周与下一周的课程，不保存整学期课表
      const weeklyCells: ScheduleCellInfo[] =
        filterCurrentAndNextWeek(scheduleCells, currentWeek);
      AppLog.info(DOMAIN, TAG,
        'step: schedule %{public}s -> weekly %{public}s (week %{public}d-%{public}d) sections %{public}s',
        `${scheduleCells.length}`, `${weeklyCells.length}`, `${currentWeek}`, `${currentWeek + 1}`,
        `${sections.length}`);

      let grades: GradeEntry[] = [];
      let gradeCategories: GradeCategory[] = [];
      let trainingPlan: PlanCategory[] = [];
      if (pyfadm.length > 0) {
        const gradesText: string = await postForm(JW_QUERY_GRADES,
          'fromPage=grxyjcbg&PYFADM=' + pyfadm + '&SCLX=04&XDLX=01');
        const gradeEnvelope: GradeEnvelopeRaw = JSON.parse(gradesText) as GradeEnvelopeRaw;
        const report: GradeReportRaw | null | undefined = gradeEnvelope.datas?.queryXyzhbx;
        grades = parseGrades(report?.fawbxMap ?? report?.fawbx);
        gradeCategories = parseGradeCategories(report?.fanbx);
        trainingPlan = parseTrainingPlan(report?.fanbx);
      } else {
        AppLog.error(DOMAIN, TAG, 'faArr empty, skip grades query');
      }

      const term: TermStatus = new TermStatus();
      term.termCode = termCode;
      term.termName = termName;
      term.currentWeek = currentWeek;

      AppStorage.setOrCreate<StudentProfile>('jwStudent', student);
      AppStorage.setOrCreate<ScheduleCellInfo[]>('jwSchedule', weeklyCells);
      AppStorage.setOrCreate<GradeEntry[]>('jwGrades', grades);
      AppStorage.setOrCreate<GradeCategory[]>('jwGradeCategories', gradeCategories);
      AppStorage.setOrCreate<PlanCategory[]>('jwTrainingPlan', trainingPlan);
      AppStorage.setOrCreate<SectionTimeInfo[]>('jwSections', sections);
      AppStorage.setOrCreate<TermStatus>('jwTerm', term);
      AppStorage.setOrCreate<string>('jwDataMode', 'online');
      AppStorage.setOrCreate<boolean>('jwLoaded', true);
      JwxtSessionRepository.loadedOnce = true;
      AppLog.info(DOMAIN, TAG,
        'sync ok: cells=%{public}s grades=%{public}s cats=%{public}s plan=%{public}s sections=%{public}s',
        `${scheduleCells.length}`, `${grades.length}`, `${gradeCategories.length}`,
        `${trainingPlan.length}`, `${sections.length}`);
      return true;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLog.error(DOMAIN, TAG, 'tryLoadOnline failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
      return false;
    }
  }

  /**
   * 未登录/失败时的空数据状态：不包含任何内置数据，由界面引导登录。
   */
  private static applyEmpty(mode: string): void {
    AppStorage.setOrCreate<StudentProfile>('jwStudent', new StudentProfile());
    AppStorage.setOrCreate<ScheduleCellInfo[]>('jwSchedule', []);
    AppStorage.setOrCreate<GradeEntry[]>('jwGrades', []);
    AppStorage.setOrCreate<GradeCategory[]>('jwGradeCategories', []);
    AppStorage.setOrCreate<PlanCategory[]>('jwTrainingPlan', []);
    AppStorage.setOrCreate<SectionTimeInfo[]>('jwSections', []);
    AppStorage.setOrCreate<TermStatus>('jwTerm', new TermStatus());
    AppStorage.setOrCreate<string>('jwDataMode', mode);
    AppStorage.setOrCreate<boolean>('jwLoaded', true);
    JwxtSessionRepository.loadedOnce = true;
  }
}
