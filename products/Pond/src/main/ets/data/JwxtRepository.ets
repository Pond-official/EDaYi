import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { CardCellItem, CardDataStore } from './CardDataStore';
import { ElectiveCourseInfo, GradeCategory, GradeEntry, ScheduleCellInfo, SectionTimeInfo, StudentProfile, TermStatus } from '../model/JwModels';

const JW_DOMAIN: string = 'https://jwxt.dmu.edu.cn';
const JW_APP_ROOT: string = JW_DOMAIN + '/jwapp';
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

interface CurrentUserRaw {
  code?: string;
  datas?: CurrentUserDataRaw;
}

interface CurrentUserDataRaw {
  userName?: string;
  userId?: string;
  welcomeInfo?: WelcomeInfoRaw;
}

interface WelcomeInfoRaw {
  classWeek?: number;
  xnxqdm?: string;
  xnxqmc?: string;
}

interface TermQueryRaw {
  code?: string;
  datas?: TermQueryDataRaw;
}

interface TermQueryDataRaw {
  cxmrxnxq?: TermCodeRaw;
}

interface TermCodeRaw {
  rows?: TermRowRaw[];
}

interface TermRowRaw {
  XNXQDM?: string;
  XNXQMC?: string;
}

interface ScheduleEnvelopeRaw {
  code?: string;
  datas?: ScheduleDatasRaw;
}

interface ScheduleDatasRaw {
  getMyScheduleDetail?: ScheduleDetailRaw;
  getMySectionList?: SectionItemRaw[];
}

interface ScheduleDetailRaw {
  arrangedList?: ScheduleItemRaw[];
}

interface ScheduleItemRaw {
  courseName?: string;
  dayOfWeek?: number;
  beginSection?: number;
  endSection?: number;
  week?: string;
  beginTime?: string;
  endTime?: string;
  placeName?: string;
  weeksAndTeachers?: string;
  color?: string;
  courseSerialNo?: string;
}interface SectionItemRaw {
  code?: number;
  name?: string;
}

interface GradeEnvelopeRaw {
  code?: string;
  datas?: GradeDatasRaw;
}

interface GradeDatasRaw {
  queryXyzhbx?: GradeReportRaw;
}

interface GradeReportRaw {
  fawbx?: GradeItemRaw[];
  fanbx?: FanTreeRaw;
  calculatedTime?: string;
}

interface FanTreeRaw {
  children?: FanCategoryRaw[];
}

interface FanCategoryRaw {
  courseCategoryName?: string;
  checkCourseVOS?: GradeItemRaw[];
}

interface GradeItemRaw {
  courseName?: string;
  scoreView?: string;
  gpa?: number;
  credit?: number;
  courseSelectionSchoolYearTermCode?: string;
  courseNature?: string;
  passed?: boolean;
}

interface StudentEnvelopeRaw {
  code?: string;
  datas?: StudentDatasRaw;
}

interface StudentDatasRaw {
  queryXsjbxx?: StudentDetailRaw;
}

interface StudentDetailRaw {
  jbxx?: StudentBasicRaw;
  faArr?: StudentFaRaw[];
}

interface StudentBasicRaw {
  XM?: string;
  XH?: string;
  BJDM_DISPLAY?: string;
  ZYDM_DISPLAY?: string;
  YXDM_DISPLAY?: string;
  XZNJ_DISPLAY?: string;
}

interface StudentFaRaw {
  PYFADM?: string;
  PYFAMC?: string;
  XDLXDM?: string;
}

/**
 * jwxt 教务系统数据仓库：
 * 仅调用教务系统真实接口；数据需在 WebView 登录（CAS）获得会话后在线拉取，
 * 未登录或网络失败时进入空数据状态，由界面引导用户登录，不内置任何演示/抓取数据。
 */
export class JwxtRepository {
  private static currentLoad: Promise<boolean> | null = null;
  private static loadedOnce: boolean = false;
  private static pendingReload: boolean = false;
  private static lastCookie: string = '';
  private static appContext: common.Context | null = null;

  /**
   * 注入应用上下文（主页面启动时调用），用于服务卡片数据持久化。
   */
  static attachContext(context: common.Context): void {
    JwxtRepository.appContext = context;
  }

  static loginUrl(): string {
    return JW_LOGIN_URL;
  }

  static async fetchSessionCookie(): Promise<string> {
    const cookie: string = webview.WebCookieManager.fetchCookieSync(JW_APP_ROOT + '/');
    return cookie;
  }

  private static syncCookie(): string {
    let cookie: string = '';
    try {
      cookie = webview.WebCookieManager.fetchCookieSync(JW_APP_ROOT + '/');
      JwxtRepository.lastCookie = cookie;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
      cookie = JwxtRepository.lastCookie;
    }
    return cookie;
  }

  private static async request(path: string, form: string, method: http.RequestMethod): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json'
      };
      const cookie: string = JwxtRepository.syncCookie();
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: 8000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      };
      if (form.length > 0) {
        options.extraData = form;
      }
      const response: http.HttpResponse = await client.request(JW_APP_ROOT + path, options);
      if (response.responseCode !== 200) {
        hilog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s', `${response.responseCode}`, path);
        throw new Error('HTTP ' + response.responseCode);
      }
      let text: string = '';
      if (typeof response.result === 'string') {
        text = response.result;
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  private static async postForm(path: string, form: string): Promise<string> {
    return JwxtRepository.request(path, form, http.RequestMethod.POST);
  }

  private static async getForm(path: string): Promise<string> {
    return JwxtRepository.request(path, '', http.RequestMethod.GET);
  }

  /**
   * 会话有效性探针（currentUser.do，code=="0" 即有效）。
   * 记录返回码/长度/解析失败片段，用于诊断登录探测不生效的设备差异。
   */
  static async probeSession(): Promise<boolean> {
    try {
      const text: string = await JwxtRepository.getForm(JW_CURRENT_USER);
      let code: string = '';
      let ok: boolean = false;
      try {
        const raw: CurrentUserRaw = JSON.parse(text) as CurrentUserRaw;
        code = raw.code ?? '';
        ok = raw.code === '0' && raw.datas !== undefined && raw.datas.userId !== undefined;
      } catch (parseError) {
        hilog.error(DOMAIN, TAG,
          'probe: json parse failed, len=%{public}s, head=%{public}s',
          `${text.length}`, text.length > 0 ? text.substring(0, 80) : '(empty)');
        return false;
      }
      hilog.info(DOMAIN, TAG, 'probe: code=%{public}s len=%{public}s ok=%{public}s',
        code, `${text.length}`, `${ok}`);
      return ok;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'probeSession failed: %{public}s', `${error}`);
      return false;
    }
  }

  /**
   * 确保数据已加载：仅首次调用生效，此后由 reload 显式刷新。
   */
  static ensureLoaded(): void {
    if (JwxtRepository.loadedOnce || JwxtRepository.currentLoad !== null) {
      return;
    }
    JwxtRepository.reload();
  }

  /**
   * 重新拉取并返回结果：登录成功、手动刷新、重试时调用。
   * 若已有加载在途则排队（pendingReload），完成后自动补拉，并返回在途 Promise。
   */
  static reload(): Promise<boolean> {
    if (JwxtRepository.currentLoad !== null) {
      JwxtRepository.pendingReload = true;
      return JwxtRepository.currentLoad;
    }
    const load: Promise<boolean> = JwxtRepository.runLoadCycle();
    JwxtRepository.currentLoad = load;
    load.then((ok: boolean) => {
      JwxtRepository.currentLoad = null;
      if (JwxtRepository.pendingReload) {
        JwxtRepository.pendingReload = false;
        JwxtRepository.reload();
      }
    });
    return load;
  }

  private static async runLoadCycle(): Promise<boolean> {
    let ok: boolean = false;
    try {
      ok = await JwxtRepository.tryLoadOnline();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load cycle error: %{public}s', `${error}`);
      ok = false;
    }
    if (!ok) {
      JwxtRepository.applyEmpty('offline');
    } else {
      JwxtRepository.persistCardData();
    }
    return ok;
  }

  /**
   * 把本周/下周课表持久化到应用级 preferences（单 key 覆盖旧数据），
   * 并刷新已添加的服务卡片。仅在同步成功后调用；
   * 退出登录或离线失败时不清除，卡片继续显示最近一次课表。
   */
  private static persistCardData(): void {
    const context: common.Context | null = JwxtRepository.appContext;
    if (context === null) {
      return;
    }
    const cells: ScheduleCellInfo[] =
      AppStorage.get<ScheduleCellInfo[]>('jwSchedule') ?? [];
    const term: TermStatus = AppStorage.get<TermStatus>('jwTerm') ?? new TermStatus();
    const payload: Record<string, Object> = {
      'week': term.currentWeek,
      'cells': JwxtRepository.toCardCells(cells)
    };
    CardDataStore.saveAndRefresh(context, JSON.stringify(payload));
  }

  private static toCardCells(cells: ScheduleCellInfo[]): CardCellItem[] {
    const list: CardCellItem[] = [];
    for (const cell of cells) {
      const item: CardCellItem = new CardCellItem();
      item.d = cell.dayOfWeek;
      item.s = cell.startSection;
      item.e = cell.endSection;
      item.n = cell.courseName;
      item.p = cell.location;
      item.t = cell.startTime;
      item.w = cell.weekBitmap;
      item.c = cell.colorHex;
      item.r = cell.teacher;
      list.push(item);
    }
    return list;
  }

  private static async tryLoadOnline(): Promise<boolean> {
    if (!await JwxtRepository.probeSession()) {
      hilog.error(DOMAIN, TAG, 'tryLoadOnline stop: probe failed, not logged in');
      return false;
    }
    try {
      await JwxtRepository.postForm(JW_SET_APP_ROLE, 'ROLEID=' + JW_ROLE_ID);
      hilog.info(DOMAIN, TAG, 'step: role set');

      const userText: string = await JwxtRepository.getForm(JW_CURRENT_USER);
      const userRaw: CurrentUserRaw = JSON.parse(userText) as CurrentUserRaw;
      const currentWeek: number = userRaw.datas?.welcomeInfo?.classWeek ?? 0;
      let termCode: string = userRaw.datas?.welcomeInfo?.xnxqdm ?? '';
      let termName: string = userRaw.datas?.welcomeInfo?.xnxqmc ?? '';
      if (termName.length === 0) {
        termName = termCode;
      }

      try {
        const termText: string =
          await JwxtRepository.postForm(JW_QUERY_CURRENT_TERM, 'CSDM=SYS&ZCSDM=DQXNXQDM&SFSY=1');
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
        hilog.error(DOMAIN, TAG, 'term query failed, keep welcomeInfo term: %{public}s', `${termError}`);
      }

      if (termCode.length === 0) {
        hilog.error(DOMAIN, TAG, 'tryLoadOnline stop: no term code');
        return false;
      }
      hilog.info(DOMAIN, TAG, 'step: term %{public}s', termCode);

      const studentText: string = await JwxtRepository.postForm(JW_QUERY_STUDENT, '');
      const studentEnvelope: StudentEnvelopeRaw = JSON.parse(studentText) as StudentEnvelopeRaw;
      const student: StudentProfile = JwxtRepository.parseStudent(studentEnvelope.datas?.queryXsjbxx?.jbxx);
      const pyfadm: string = JwxtRepository.extractPyfadm(studentEnvelope.datas?.queryXsjbxx?.faArr);
      if (userRaw.datas?.userName !== undefined && student.name.length === 0) {
        student.name = userRaw.datas.userName;
      }
      hilog.info(DOMAIN, TAG, 'step: student %{public}s pyfadm=%{public}s', student.name, pyfadm);

      const scheduleText: string =
        await JwxtRepository.postForm(JW_SCHEDULE_DETAIL, 'XNXQDM=' + termCode + '&XQDM=1');
      const sectionsText: string =
        await JwxtRepository.postForm(JW_SCHEDULE_SECTIONS, 'XNXQDM=' + termCode + '&XQDM=1');
      const scheduleEnvelope: ScheduleEnvelopeRaw = JSON.parse(scheduleText) as ScheduleEnvelopeRaw;
      const scheduleCells: ScheduleCellInfo[] =
        JwxtRepository.parseScheduleCells(scheduleEnvelope.datas?.getMyScheduleDetail?.arrangedList);

      const sectionsEnvelope: ScheduleEnvelopeRaw = JSON.parse(sectionsText) as ScheduleEnvelopeRaw;
      const sections: SectionTimeInfo[] =
        JwxtRepository.parseSections(scheduleCells, sectionsEnvelope.datas?.getMySectionList);
      // 仅保留当前周与下一周的课程，不保存整学期课表
      const weeklyCells: ScheduleCellInfo[] =
        JwxtRepository.filterCurrentAndNextWeek(scheduleCells, currentWeek);
      hilog.info(DOMAIN, TAG,
        'step: schedule %{public}s -> weekly %{public}s (week %{public}d-%{public}d) sections %{public}s',
        `${scheduleCells.length}`, `${weeklyCells.length}`, `${currentWeek}`, `${currentWeek + 1}`,
        `${sections.length}`);

      let grades: GradeEntry[] = [];
      let gradeCategories: GradeCategory[] = [];
      if (pyfadm.length > 0) {
        const gradesText: string = await JwxtRepository.postForm(JW_QUERY_GRADES,
          'fromPage=grxyjcbg&PYFADM=' + pyfadm + '&SCLX=04&XDLX=01');
        const gradeEnvelope: GradeEnvelopeRaw = JSON.parse(gradesText) as GradeEnvelopeRaw;
        grades = JwxtRepository.parseGrades(gradeEnvelope.datas?.queryXyzhbx?.fawbx);
        gradeCategories =
          JwxtRepository.parseGradeCategories(gradeEnvelope.datas?.queryXyzhbx?.fanbx);
      } else {
        hilog.error(DOMAIN, TAG, 'faArr empty, skip grades query');
      }

      const term: TermStatus = new TermStatus();
      term.termCode = termCode;
      term.termName = termName;
      term.currentWeek = currentWeek;

      AppStorage.setOrCreate<StudentProfile>('jwStudent', student);
      AppStorage.setOrCreate<ScheduleCellInfo[]>('jwSchedule', weeklyCells);
      AppStorage.setOrCreate<GradeEntry[]>('jwGrades', grades);
      AppStorage.setOrCreate<GradeCategory[]>('jwGradeCategories', gradeCategories);
      AppStorage.setOrCreate<SectionTimeInfo[]>('jwSections', sections);
      AppStorage.setOrCreate<TermStatus>('jwTerm', term);
      AppStorage.setOrCreate<string>('jwDataMode', 'online');
      AppStorage.setOrCreate<boolean>('jwLoaded', true);
      JwxtRepository.loadedOnce = true;
      hilog.info(DOMAIN, TAG, 'sync ok: cells=%{public}s grades=%{public}s cats=%{public}s sections=%{public}s',
        `${scheduleCells.length}`, `${grades.length}`, `${gradeCategories.length}`, `${sections.length}`);
      return true;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'tryLoadOnline failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
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
    AppStorage.setOrCreate<ElectiveCourseInfo[]>('jwElectives', []);
    AppStorage.setOrCreate<SectionTimeInfo[]>('jwSections', []);
    AppStorage.setOrCreate<TermStatus>('jwTerm', new TermStatus());
    AppStorage.setOrCreate<string>('jwDataMode', mode);
    AppStorage.setOrCreate<boolean>('jwLoaded', true);
    JwxtRepository.loadedOnce = true;
  }

  /**
   * 退出登录：清除 WebView 会话 Cookie 并回到未登录空态。
   * 不清除已持久化的卡片课表，桌面卡片继续显示最近一次同步的数据。
   */
  static logout(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'clearAllCookiesSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
    }
    JwxtRepository.lastCookie = '';
    JwxtRepository.applyEmpty('offline');
  }

  private static extractPyfadm(faArr?: StudentFaRaw[]): string {
    if (faArr === undefined || faArr.length === 0) {
      return '';
    }
    for (const fa of faArr) {
      if (fa.PYFADM !== undefined && fa.PYFADM.length > 0) {
        return fa.PYFADM;
      }
    }
    return '';
  }

  /**
   * 只保留当前周（currentWeek）与下一周（currentWeek+1）有课的课程。
   * 接口仅支持整学期拉取，此处在客户端按周位图过滤，
   * 保存与应用内流转的数据仅覆盖这两周；周次未知时保留全部。
   */
  private static filterCurrentAndNextWeek(cells: ScheduleCellInfo[], currentWeek: number): ScheduleCellInfo[] {
    if (currentWeek <= 0) {
      hilog.warn(DOMAIN, TAG, 'week filter skipped: unknown current week');
      return cells;
    }
    return cells.filter((cell: ScheduleCellInfo): boolean =>
      cell.activeInWeek(currentWeek) || cell.activeInWeek(currentWeek + 1));
  }

  private static parseScheduleCells(items?: ScheduleItemRaw[]): ScheduleCellInfo[] {
    const list: ScheduleCellInfo[] = [];
    if (items === undefined) {
      return list;
    }
    for (const item of items) {
      if (item.courseName === undefined || item.dayOfWeek === undefined || item.beginSection === undefined) {
        continue;
      }
      const cell: ScheduleCellInfo = new ScheduleCellInfo();
      cell.courseName = item.courseName;
      cell.dayOfWeek = item.dayOfWeek;
      cell.startSection = item.beginSection;
      cell.endSection = item.endSection ?? item.beginSection;
      cell.weekBitmap = item.week ?? '';
      cell.startTime = item.beginTime ?? '';
      cell.endTime = item.endTime ?? '';
      cell.location = JwxtRepository.firstSegment(item.placeName ?? '', ';');
      cell.colorHex = item.color ?? '#E8F3DB';
      cell.courseSerialNo = item.courseSerialNo ?? '';
      const wt: string = item.weeksAndTeachers ?? '';
      cell.weeksText = JwxtRepository.weeksPart(wt);
      cell.teacher = JwxtRepository.teacherPart(wt);
      list.push(cell);
    }
    return list;
  }

  private static parseGrades(items?: GradeItemRaw[]): GradeEntry[] {
    const list: GradeEntry[] = [];
    if (items === undefined) {
      return list;
    }
    for (const item of items) {
      if (item.courseName === undefined) {
        continue;
      }
      const scoreView: string = item.scoreView ?? '';
      if (scoreView.length === 0 || scoreView === '0') {
        continue;
      }
      const grade: GradeEntry = new GradeEntry();
      grade.courseName = item.courseName;
      grade.scoreView = scoreView;
      grade.gpaPoint = item.gpa ?? 0;
      grade.credit = item.credit ?? 0;
      grade.termCode = item.courseSelectionSchoolYearTermCode ?? '';
      grade.natureText = item.courseNature === '01' ? '必修' : '选修';
      grade.passed = item.passed ?? true;
      list.push(grade);
    }
    return list;
  }

  /**
   * 培养方案分类成绩（专业基础课/专业课/公共课/实习等）：
   * 仅保留已有成绩的科目，未出分（空）与成绩为 0 的科目自动隐藏。
   */
  private static parseGradeCategories(fan?: FanTreeRaw): GradeCategory[] {
    const list: GradeCategory[] = [];
    const children: FanCategoryRaw[] | undefined = fan?.children ?? undefined;
    if (children === undefined) {
      return list;
    }
    for (const child of children) {
      const name: string = child.courseCategoryName ?? '';
      if (name.length === 0) {
        continue;
      }
      const category: GradeCategory = new GradeCategory();
      category.name = name;
      category.grades = JwxtRepository.parseGrades(child.checkCourseVOS);
      if (category.grades.length > 0) {
        list.push(category);
      }
    }
    return list;
  }

  private static parseStudent(basic?: StudentBasicRaw): StudentProfile {
    const p: StudentProfile = new StudentProfile();
    if (basic !== undefined) {
      p.name = basic.XM ?? '';
      p.studentId = basic.XH ?? '';
      p.className = basic.BJDM_DISPLAY ?? '';
      p.majorName = basic.ZYDM_DISPLAY ?? '';
      p.collegeName = basic.YXDM_DISPLAY ?? '';
      p.grade = basic.XZNJ_DISPLAY ?? '';
    }
    return p;
  }

  /**
   * 节次列表：优先取接口 getMySectionList；接口缺失时按课表节次范围推导。
   * 时间文本取该节次第一节课的开始时间（来自课表接口）。
   */
  private static parseSections(cells: ScheduleCellInfo[], items?: SectionItemRaw[]): SectionTimeInfo[] {
    const list: SectionTimeInfo[] = [];
    if (items !== undefined && items.length > 0) {
      for (const item of items) {
        const s: SectionTimeInfo = new SectionTimeInfo();
        s.section = item.code ?? 0;
        s.name = item.name ?? '';
        s.timeText = JwxtRepository.sectionStartTime(cells, s.section);
        list.push(s);
      }
      return list;
    }
    let maxSection: number = 0;
    for (const cell of cells) {
      if (cell.endSection > maxSection) {
        maxSection = cell.endSection;
      }
    }
    for (let i: number = 1; i <= maxSection; i++) {
      const s: SectionTimeInfo = new SectionTimeInfo();
      s.section = i;
      s.name = '第' + i + '节';
      s.timeText = JwxtRepository.sectionStartTime(cells, i);
      list.push(s);
    }
    return list;
  }

  private static sectionStartTime(cells: ScheduleCellInfo[], section: number): string {
    for (const cell of cells) {
      if (cell.startSection === section && cell.startTime.length > 0) {
        return cell.startTime;
      }
    }
    return '';
  }

  private static firstSegment(text: string, separator: string): string {
    const idx: number = text.indexOf(separator);
    if (idx < 0) {
      return text;
    }
    return text.substring(0, idx).trim();
  }

  private static weeksPart(weeksAndTeachers: string): string {
    const idx: number = weeksAndTeachers.indexOf('[讲授]');
    const head: string = idx >= 0 ? weeksAndTeachers.substring(0, idx) : weeksAndTeachers;
    return head;
  }

  private static teacherPart(weeksAndTeachers: string): string {
    const slash: number = weeksAndTeachers.indexOf('/');
    if (slash < 0) {
      return '';
    }
    let rest: string = weeksAndTeachers.substring(slash + 1);
    const semicolon: number = rest.indexOf(';');
    if (semicolon >= 0) {
      rest = rest.substring(0, semicolon);
    }
    const bracket: number = rest.indexOf('[主讲]');
    if (bracket >= 0) {
      rest = rest.substring(0, bracket);
    }
    return rest.trim();
  }
}
