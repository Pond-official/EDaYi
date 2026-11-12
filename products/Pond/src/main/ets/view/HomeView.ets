import { FinalExamEntry, ScheduleCellInfo, StudentProfile, TermStatus } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { ScheduleBoard } from './ScheduleBoard';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { display, window } from '@kit.ArkUI';
import { HomeOfflineBanner, HomeStudentCard, HomeSectionTitle, HomeTodayCard, HomeWeekChip, HomeFinalExamCard } from './HomeCards';

/**
 * 首页：学生信息卡 + 今日课程 + 我的课表（原生 Row/Column 布局，三端自适应）。
 * 手机单列纵向排布；平板/电脑双列（左信息流、右课表）。
 */
@Component
export struct HomeView {
  @StorageProp('jwStudent') student: StudentProfile = new StudentProfile();
  @StorageProp('jwSchedule') @Watch('onScheduleChanged') scheduleCells: ScheduleCellInfo[] = [];
  @StorageProp('jwTerm') @Watch('onScheduleChanged') termStatus: TermStatus = new TermStatus();
  @StorageProp('jwDataMode') dataMode: string = 'preview';
  /** 隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  @StorageProp('jwPrivacyMode') privacyMode: string = 'standard';
  /** 各课程期末考试时间设置（按课程名） */
  @StorageProp('jwFinalExams') @Watch('onFinalExamsChanged') finalExams: FinalExamEntry[] = [];
  /** 首页页签是否激活（pages/Index 页签切换时写入）：切回首页时检查已结束考试 */
  @StorageProp('jwHomeTabActive') @Watch('onHomeTabActive') homeTabActive: boolean = true;
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  /** 应用回前台时刻戳（PondAbility onForeground），跨天时刷新"今日课程" */
  @StorageProp('jwForegroundTick') @Watch('onForegroundTick') foregroundTick: number = 0;
  private todayDay: number = 1;
  @State todayCells: ScheduleCellInfo[] = [];
  /** 课表周切换：0=本周，1=下周 */
  @State scheduleWeekOffset: number = 0;
  /** 下拉刷新进行中（仅登录后实际刷新，未登录提示后立即收起） */
  @State isRefreshing: boolean = false;
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** Refresh 布局高度：初始取屏幕高度，旋转后由窗口尺寸事件刷新（display 快照在旋转瞬间滞后） */
  @State refreshHeight: Length = '100%';
  /** 窗口宽高（px）：横竖屏方向判定；启动时取 display 快照，旋转后由窗口尺寸事件刷新 */
  @State winWidthPx: number = 0;
  @State winHeightPx: number = 0;
  /** 窗口尺寸变化回调：持有引用便于精准解绑，避免 off 误伤其他视图的监听 */
  private readonly onWinSizeChanged = (size: window.Size): void => {
    // 旋转：状态更新包进 animateTo，驱动单列/双列分支 geometryTransition 飞行与高度渐变
    this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction }, () => {
      this.applyWindowSize(size.width, size.height);
    });
  };

  aboutToAppear(): void {
    this.initWindowDims();
    this.refreshHeight = this.refreshHeightVp();
    this.bindWindowHeight();
    JwxtRepository.ensureLoaded();
    this.refreshToday();
    this.rebuildTodayCells();
  }

  aboutToDisappear(): void {
    this.unbindWindowHeight();
  }

  onScheduleChanged(): void {
    this.rebuildTodayCells();
  }

  /** 应用回前台：跨天挂起后重算"今天"，刷新今日课程，检查已结束考试 */
  onForegroundTick(): void {
    this.refreshToday();
    this.rebuildTodayCells();
    this.checkFinishedExams();
  }

  /** 首页页签切回：刷新今日课程并检查已结束考试 */
  onHomeTabActive(): void {
    if (this.homeTabActive) {
      this.rebuildTodayCells();
      this.checkFinishedExams();
    }
  }

  /** 期末数据变化（首次异步加载完成/设置页修改）：检查已结束考试 */
  onFinalExamsChanged(): void {
    this.checkFinishedExams();
  }

  private refreshToday(): void {
    const day: number = new Date().getDay();
    this.todayDay = day === 0 ? 7 : day;
  }

  private rebuildTodayCells(): void {
    const week: number = this.termStatus.currentWeek;
    this.todayCells = this.scheduleCells
      .filter((c: ScheduleCellInfo): boolean =>
        c.dayOfWeek === this.todayDay && c.activeInWeek(week))
      .sort((a: ScheduleCellInfo, b: ScheduleCellInfo): number => a.startSection - b.startSection);
  }

  private isWide(): boolean {
    if (this.currentBreakpoint !== 'lg' && this.currentBreakpoint !== 'xl') {
      return false;
    }
    // 大屏平板竖屏宽度也可能达到 lg（如 13 寸平板竖屏 960vp）：处于竖屏（宽 ≤ 高）时仍用单列纵向排版
    if (this.winWidthPx > 0 && this.winHeightPx > 0 && this.winWidthPx <= this.winHeightPx) {
      return false;
    }
    return true;
  }

  private bottomInset(): number {
    return 88;
  }

  /**
   * Refresh 组件会接管子组件几何并吞掉其 expandSafeArea，导致内部 Scroll 的
   * 滚动视口无法扩展进安全避让区（内容永远裁剪在避让区上方）。
   * 因此不给 Refresh 走 expandSafeArea，而是显式把它的布局高度设为整屏高度
   * （窗口沉浸式全屏，布局从屏幕顶部开始），使 Refresh 与内部 Scroll
   * 的布局本身覆盖状态栏与底部手势区，滚动视口随布局自然延伸。
   */
  private refreshHeightVp(): Length {
    let screenHeightPx: number = 0;
    try {
      screenHeightPx = display.getDefaultDisplaySync().height;
    } catch (err) {
      screenHeightPx = 0;
    }
    if (screenHeightPx <= 0) {
      return '100%';
    }
    return this.getUIContext().px2vp(screenHeightPx);
  }

  /** 启动时同步读取 display 宽高：用于初始横竖屏方向判定（启动时 display 快照是准确的） */
  private initWindowDims(): void {
    try {
      const disp: display.Display = display.getDefaultDisplaySync();
      this.winWidthPx = disp.width;
      this.winHeightPx = disp.height;
    } catch (err) {
      // 读取失败保持 0，留给窗口尺寸事件回填
    }
  }

  /** 按窗口尺寸（px）刷新 Refresh 布局高度与横竖屏方向判定数据 */
  private applyWindowSize(widthPx: number, heightPx: number): void {
    if (widthPx > 0 && heightPx > 0) {
      this.winWidthPx = widthPx;
      this.winHeightPx = heightPx;
      this.refreshHeight = this.getUIContext().px2vp(heightPx);
    }
  }

  /** 绑定主窗口尺寸变化：旋转后以窗口事件数据刷新 Refresh 高度与方向判定（display 快照可能滞后） */
  private bindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      this.applyWindowSize(rect.width, rect.height);
      win.on('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  /** 解绑窗口尺寸变化监听 */
  private unbindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.off('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  private dayWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 56;
    }
    if (this.currentBreakpoint === 'md') {
      return 76;
    }
    return 96;
  }

  private rowHeight(): number {
    if (this.currentBreakpoint === 'sm') {
      return 66;
    }
    if (this.currentBreakpoint === 'md') {
      return 70;
    }
    return 74;
  }

  private goLogin(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginIndex' });
  }

  /** 下拉刷新：已连接教务系统时在线刷新；未登录时提示先登录并立即收起刷新动画 */
  private doRefresh(): void {
    if (this.dataMode !== 'online') {
      this.isRefreshing = false;
      try {
        this.getUIContext().getPromptAction()
          .showToast({ message: '请先登录教务系统后再刷新', duration: 1500 });
      } catch (error) {
      }
      return;
    }
    JwxtRepository.reload().then((ok: boolean) => {
      this.isRefreshing = false;
      if (!ok) {
        try {
          this.getUIContext().getPromptAction()
            .showToast({ message: '刷新失败，请稍后重试', duration: 1500 });
        } catch (error) {
        }
      }
    });
  }

  /** 退出登录确认弹窗文案：按隐私模式说明退出后数据去留 */
  private logoutMessage(): string {
    if (this.privacyMode === 'standard') {
      return '退出后将清除教务登录状态，课表、成绩与综评等离线数据将继续显示，确定退出吗？';
    }
    if (this.privacyMode === 'strict') {
      return '退出后将清除教务登录状态与全部缓存数据（含桌面课表卡片），课表与成绩等不再显示，确定退出吗？';
    }
    return '退出后将清除教务登录状态与课表以外的缓存数据，课表与成绩等不再显示；桌面课表卡片不受影响。确定退出吗？';
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: this.logoutMessage(),
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('sys.color.ohos_id_color_warning'),
        action: () => {
          JwxtRepository.logout();
        }
      }
    });
  }

  @Builder
  scheduleCard() {
    Column() {
      Row() {
        Text('我的课表')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        HomeWeekChip({ label: '本周', selected: this.scheduleWeekOffset === 0, onSelect: (): void => {
          this.scheduleWeekOffset = 0;
        } })
        HomeWeekChip({ label: '下周', selected: this.scheduleWeekOffset === 1, onSelect: (): void => {
          this.scheduleWeekOffset = 1;
        } })
      }
      .width('100%')
      .padding({ bottom: 12 })
      if (this.scheduleCells.length === 0) {
        Text('登录教务系统后在线同步课表')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 8, bottom: 8 })
      }
      ScheduleBoard({
        dayCellWidth: this.dayWidth(),
        sectionRowHeight: this.rowHeight(),
        showHeader: true,
        weekOffset: this.scheduleWeekOffset
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .geometryTransition('home-schedule')
    .transition(TransitionEffect.OPACITY)
  }

  @Builder
  infoColumn() {
    Column() {
      HomeStudentCard({ student: this.student })
      if (this.dataMode !== 'online') {
        this.loginFooter()
      } else {
        this.logoutFooter()
      }
      HomeSectionTitle('今日安排')
      HomeTodayCard({ cells: this.todayCells })
    }
    .width('100%')
    .geometryTransition('home-info')
    .transition(TransitionEffect.OPACITY)
  }

  /** 该科目考试时刻（时间非法返回 null） */
  private examDateOf(entry: FinalExamEntry): Date | null {
    return ExamDateUtils.parseExamDate(entry.examDate);
  }

  /** 该科目距考日历天数（今天为 0；时间非法返回 -1） */
  private examDaysOf(entry: FinalExamEntry): number {
    const parsed: Date | null = this.examDateOf(entry);
    return parsed !== null ? ExamDateUtils.calendarDaysFrom(parsed) : -1;
  }

  /** 该科目倒计时文本（超过一天显示整天，不足一天显示小时；时间非法按"已结束"展示） */
  private examTextOf(entry: FinalExamEntry): string {
    const parsed: Date | null = this.examDateOf(entry);
    return parsed !== null ? ExamDateUtils.countdownTextOf(parsed) : '已结束';
  }

  /** 期末倒计时条目：仅保留时间合法且未到点的科目，按考试时间升序 */
  private sortedFinalExams(): FinalExamEntry[] {
    return this.finalExams
      .filter((e: FinalExamEntry): boolean => {
        const parsed: Date | null = this.examDateOf(e);
        return parsed !== null && ExamDateUtils.remainingMs(parsed) > 0;
      })
      .sort((a: FinalExamEntry, b: FinalExamEntry): number =>
        a.examDate < b.examDate ? -1 : (a.examDate > b.examDate ? 1 : 0));
  }

  /**
   * 首页可见时检查期末倒计时：已到点（含时间非法）的科目弹窗提示已完成数，
   * 并从设置中删除。触发点：Index.onPageShow（页面就绪，含冷启动/路由返回）、
   * 应用回前台、页签切回首页、期末数据变化（首次加载/设置页修改）。
   * 注意：不在此处 aboutToAppear 调用——页面尚未挂载完成时弹窗无法显示。
   */
  private checkFinishedExams(): void {
    const finishedNames: string[] = [];
    for (const entry of this.finalExams) {
      const parsed: Date | null = this.examDateOf(entry);
      if (parsed === null || ExamDateUtils.remainingMs(parsed) <= 0) {
        finishedNames.push(entry.courseName);
      }
    }
    if (finishedNames.length === 0) {
      return;
    }
    for (const name of finishedNames) {
      JwxtRepository.updateFinalExam(name, '');
    }
    this.getUIContext().showAlertDialog({
      title: '期末倒计时',
      message: '已完成 ' + finishedNames.length + ' 科目的考试，相关倒计时已移除',
      confirm: {
        value: '知道啦',
        action: () => {
        }
      }
    });
  }

  /** 该课程在课表中的颜色（找不到返回空串，不显示色点） */
  private courseColorOf(courseName: string): string {
    const found: ScheduleCellInfo | undefined = this.scheduleCells
      .find((c: ScheduleCellInfo): boolean => c.courseName === courseName);
    return found !== undefined ? found.colorHex : '';
  }

  @Builder
  wideContent() {
    Row() {
      Column() {
        this.infoColumn()
      }
      .width(360)
      Column() {
        this.scheduleCard()
        if (this.sortedFinalExams().length > 0) {
          HomeFinalExamCard({
            exams: this.sortedFinalExams(),
            colorOf: (courseName: string): string => this.courseColorOf(courseName),
            daysOf: (entry: FinalExamEntry): number => this.examDaysOf(entry),
            textOf: (entry: FinalExamEntry): string => this.examTextOf(entry)
          })
        }
      }
      .layoutWeight(1)
      .padding({ left: 16 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .constraintSize({ maxWidth: 1200 })
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  narrowContent() {
    Column() {
      this.infoColumn()
      HomeSectionTitle('我的课表')
      this.scheduleCard()
      if (this.sortedFinalExams().length > 0) {
        HomeFinalExamCard({
          exams: this.sortedFinalExams(),
          colorOf: (courseName: string): string => this.courseColorOf(courseName),
          daysOf: (entry: FinalExamEntry): number => this.examDaysOf(entry),
          textOf: (entry: FinalExamEntry): string => this.examTextOf(entry)
        })
      }
    }
    .width('100%')
  }

  /** 登录教务按钮：紧随个人信息卡下方，仅在未连接教务系统时显示 */
  @Builder
  loginFooter() {
    Button('登录教务')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .height(44)
      .margin({ top: 16 })
      .onClick(() => {
        this.goLogin();
      })
  }

  /** 退出登录按钮：紧随个人信息卡下方，仅在已连接教务系统时显示 */
  @Builder
  logoutFooter() {
    Button('退出登录')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .height(44)
      .margin({ top: 16 })
      .buttonStyle(ButtonStyleMode.NORMAL)
      .fontColor($r('sys.color.ohos_id_color_warning'))
      .onClick(() => {
        this.confirmLogout();
      })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll() {
          Column() {
            if (this.dataMode === 'offlineCache') {
              HomeOfflineBanner((): void => {
                this.goLogin();
              })
            }
            if (this.isWide()) {
              this.wideContent()
            } else {
              this.narrowContent()
            }
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: this.bottomInset() })
          .constraintSize({ minWidth: '100%' })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        }
      .onRefreshing(() => {
        this.doRefresh();
      })
      .width('100%')
      .height(this.refreshHeight)

      FrostBand() {
        Row({ space: 8 }) {
          Text('首页')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
