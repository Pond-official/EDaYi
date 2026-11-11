import { FinalExamEntry, ScheduleCellInfo, StudentProfile, TermStatus } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { ScheduleBoard } from './ScheduleBoard';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { display, window } from '@kit.ArkUI';

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
  /** 各课程期末考试日期设置（按课程名） */
  @StorageProp('jwFinalExams') finalExams: FinalExamEntry[] = [];
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

  /** 应用回前台：跨天挂起后重算"今天"，刷新今日课程 */
  onForegroundTick(): void {
    this.refreshToday();
    this.rebuildTodayCells();
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

  /** 离线数据提示条：使用本地缓存数据时置顶提示，点击“去登录”重新在线同步 */
  @Builder
  offlineBanner() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(20)
        .fontColor([$r('sys.color.ohos_id_color_warning')])
      Column({ space: 2 }) {
        Text('正在使用离线数据')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('当前展示本地缓存，重新登录后自动更新')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('去登录')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ bottom: 12 })
    .onClick(() => {
      this.goLogin();
    })
  }

  @Builder
  studentCard() {
    Column() {
      Row() {
        Stack() {
          Text(this.student.name.length > 0 ? this.student.name.substring(0, 1) : '生')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
        Column({ space: 4 }) {
          Text(this.student.name)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text(this.student.studentId)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12 })
        Column({ space: 4 }) {
          Text(this.student.className)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.End)
          Text(this.student.collegeName)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.End)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.End)
        .constraintSize({ maxWidth: '45%' })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .padding({ top: 16, bottom: 8 })
  }

  @Builder
  todayCourseRow(cell: ScheduleCellInfo) {
    Row() {
      Text(cell.startTime)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width(44)
      Column()
        .width(3)
        .height(32)
        .borderRadius(2)
        .backgroundColor(cell.colorHex)
        .margin({ left: 4, right: 12 })
      Column({ space: 2 }) {
        Text(cell.courseName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('第' + cell.startSection + '-' + cell.endSection + '节 · ' + cell.location + ' · ' + cell.teacher)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  todayCard() {
    Column() {
      Row() {
        Text('今日课程')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text('共' + this.todayCells.length + '门')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      if (this.todayCells.length === 0) {
        Text('今天没有课程安排')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 16, bottom: 16 })
      } else {
        ForEach(this.todayCells, (cell: ScheduleCellInfo) => {
          this.todayCourseRow(cell)
        }, (cell: ScheduleCellInfo) => 'today' + cell.courseSerialNo + cell.dayOfWeek + cell.startSection)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  weekChip(label: string, offset: number) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.scheduleWeekOffset === offset ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.scheduleWeekOffset === offset ?
        Color.White : $r('sys.color.ohos_id_color_text_secondary'))
      .backgroundColor(this.scheduleWeekOffset === offset ?
        $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(10)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .margin({ left: 6 })
      .onClick(() => {
        this.scheduleWeekOffset = offset;
      })
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
        this.weekChip('本周', 0)
        this.weekChip('下周', 1)
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
      this.studentCard()
      if (this.dataMode !== 'online') {
        this.loginFooter()
      } else {
        this.logoutFooter()
      }
      this.sectionTitle('今日安排')
      this.todayCard()
    }
    .width('100%')
    .geometryTransition('home-info')
    .transition(TransitionEffect.OPACITY)
  }

  /** 该科目距考天数（日期非法返回 -1，按"已结束"展示） */
  private examDaysOf(entry: FinalExamEntry): number {
    const parsed: Date | null = ExamDateUtils.parseYmd(entry.examDate);
    return parsed !== null ? ExamDateUtils.daysFromDate(parsed) : -1;
  }

  /** 期末倒计时条目：仅保留日期合法且未考完（含当天）的科目，按考试日期升序 */
  private sortedFinalExams(): FinalExamEntry[] {
    return this.finalExams
      .filter((e: FinalExamEntry): boolean => this.examDaysOf(e) >= 0)
      .sort((a: FinalExamEntry, b: FinalExamEntry): number =>
        a.examDate < b.examDate ? -1 : (a.examDate > b.examDate ? 1 : 0));
  }

  /** 该课程在课表中的颜色（找不到返回空串，不显示色点） */
  private courseColorOf(courseName: string): string {
    const found: ScheduleCellInfo | undefined = this.scheduleCells
      .find((c: ScheduleCellInfo): boolean => c.courseName === courseName);
    return found !== undefined ? found.colorHex : '';
  }

  /** 倒计时徽标：未来为激活色底白字，当天为警示色，已结束为次要文字 */
  @Builder
  countdownBadge(days: number) {
    if (days > 0) {
      Text(ExamDateUtils.countdownText(days))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
    } else if (days === 0) {
      Text(ExamDateUtils.countdownText(days))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_warning'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    } else {
      Text(ExamDateUtils.countdownText(days))
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    }
  }

  @Builder
  finalExamRow(entry: FinalExamEntry) {
    Row() {
      if (this.courseColorOf(entry.courseName).length > 0) {
        Column()
          .width(10)
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.courseColorOf(entry.courseName))
          .margin({ right: 8 })
      }
      Column({ space: 2 }) {
        Text(entry.courseName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(ExamDateUtils.formatDisplay(entry.examDate))
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      this.countdownBadge(this.examDaysOf(entry))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 7, bottom: 7 })
  }

  /** 期末倒计时卡：显示已设定期末日期的科目及倒计时，未设定任何日期时不显示 */
  @Builder
  finalExamCard() {
    Column() {
      Row() {
        Text('期末倒计时')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text('在课表课程详情中设置')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      .padding({ bottom: 4 })

      ForEach(this.sortedFinalExams(), (entry: FinalExamEntry) => {
        this.finalExamRow(entry)
      }, (entry: FinalExamEntry) => 'exam' + entry.courseName + entry.examDate)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 16 })
    .geometryTransition('home-final')
    .transition(TransitionEffect.OPACITY)
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
          this.finalExamCard()
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
      this.sectionTitle('我的课表')
      this.scheduleCard()
      if (this.sortedFinalExams().length > 0) {
        this.finalExamCard()
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
              this.offlineBanner()
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
