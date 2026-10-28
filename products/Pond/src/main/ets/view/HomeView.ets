import { router } from '@kit.ArkUI';
import { FinalExamEntry, ScheduleCellInfo, StudentProfile, TermStatus } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { ScheduleBoard } from './ScheduleBoard';

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
  /** 各课程期末考试日期设置（按课程名） */
  @StorageProp('jwFinalExams') finalExams: FinalExamEntry[] = [];
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  /** 应用回前台时刻戳（PondAbility onForeground），跨天时刷新"今日课程" */
  @StorageProp('jwForegroundTick') @Watch('onForegroundTick') foregroundTick: number = 0;
  private todayDay: number = 1;
  @State todayCells: ScheduleCellInfo[] = [];
  /** 课表周切换：0=本周，1=下周 */
  @State scheduleWeekOffset: number = 0;

  aboutToAppear(): void {
    JwxtRepository.ensureLoaded();
    this.refreshToday();
    this.rebuildTodayCells();
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
    return this.currentBreakpoint === 'lg' || this.currentBreakpoint === 'xl';
  }

  private bottomInset(): number {
    return 88;
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

  private modeLabel(): string {
    if (this.dataMode === 'online') {
      return '已连接教务系统';
    }
    if (this.dataMode === 'offlineCache') {
      return '离线数据 · 请重新登录';
    }
    return '未登录教务系统';
  }

  private goLogin(): void {
    router.pushUrl({ url: 'pages/LoginIndex' });
  }

  private refreshData(): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: '正在刷新…', duration: 1000 });
    } catch (error) {
    }
    JwxtRepository.reload().then((ok: boolean) => {
      if (!ok) {
        try {
          this.getUIContext().getPromptAction()
            .showToast({ message: '刷新失败，请稍后重试', duration: 1500 });
        } catch (error) {
        }
      }
    });
  }

  private confirmLogout(): void {
    AlertDialog.show({
      title: '退出登录',
      message: '退出后将清除教务登录状态，课表与成绩不再显示，确定退出吗？',
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
  dataModeBanner() {
    Row() {
      Text(this.modeLabel())
        .fontSize(this.dataMode === 'offlineCache' ? 12 : 11)
        .fontWeight(this.dataMode === 'offlineCache' ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.dataMode === 'offlineCache' ?
          $r('sys.color.ohos_id_color_warning') :
          $r('sys.color.ohos_id_color_text_secondary'))
        .layoutWeight(1)
      if (this.dataMode !== 'online') {
        Button('登录教务')
          .fontSize(12)
          .height(28)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.goLogin();
          })
      }
      if (this.dataMode === 'online') {
        Text('退出登录')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ left: 8 })
          .onClick(() => {
            this.confirmLogout();
          })
      }
      Text('刷新')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .padding({ left: 8 })
        .onClick(() => {
          this.refreshData();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  studentCard() {
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
  }

  @Builder
  infoColumn() {
    Column() {
      this.studentCard()
      this.sectionTitle('今日安排')
      this.todayCard()
    }
    .width('100%')
  }

  /** 期末倒计时条目：日期合法的科目按考试日期升序 */
  private sortedFinalExams(): FinalExamEntry[] {
    return this.finalExams
      .filter((e: FinalExamEntry): boolean => ExamDateUtils.parseYmd(e.examDate) !== null)
      .slice()
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

      this.countdownBadge(ExamDateUtils.daysFromDate(ExamDateUtils.parseYmd(entry.examDate) ?? new Date()))
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

  build() {
    Column() {
      this.dataModeBanner()
      Scroll() {
        Column() {
          if (this.isWide()) {
            this.wideContent()
          } else {
            this.narrowContent()
          }
        }
        .padding({ left: 16, right: 16, bottom: this.bottomInset() })
        .constraintSize({ minWidth: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
