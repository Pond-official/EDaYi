import { FinalExamEntry, ScheduleCellInfo, TermStatus } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { mediaquery } from '@kit.ArkUI';

const DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const CELL_GAP: number = 4;
const PERIOD_COUNT: number = 5;
const PERIOD_LABELS: string[] = ['1-2节', '3-4节', '5-6节', '7-8节', '9-10节'];
const PERIOD_TIMES: string[] = ['8:30-10:00', '10:20-11:50', '13:20-14:50', '15:00-16:30', '17:30-19:00'];
const LABEL_COLUMN_WIDTH: number = 58;

/**
 * 周课表网格（原生 Row/Column 布局实现）：
 * 每天 10 节课，两节一大节，固定作息：1-2节 8:30-10:00、3-4节 10:20-11:50、
 * 5-6节 13:20-14:50、7-8节 15:00-16:30、9-10节 17:30-19:00。
 * 数据仅包含本周与下周课程，"本周/下周"切换由父组件通过 weekOffset 控制；
 * 课程块按大节占位（小节映射：period = ceil(section / 2)），
 * 手机端横向滚动，平板/电脑端列宽自适应放大。
 */
@Component
export struct ScheduleBoard {
  @StorageProp('jwSchedule') cells: ScheduleCellInfo[] = [];
  @StorageProp('jwTerm') termStatus: TermStatus = new TermStatus();
  /** 被单独关闭上课提醒的课程名单（按课程名） */
  @StorageProp('jwReminderDisabledCourses') disabledCourses: string[] = [];
  /** 各课程期末考试日期设置（按课程名） */
  @StorageProp('jwFinalExams') finalExams: FinalExamEntry[] = [];
  @Prop dayCellWidth: number = 52;
  @Prop sectionRowHeight: number = 62;
  @Prop showHeader: boolean = true;
  /** 0=本周，1=下周，由父组件控制 */
  @Prop weekOffset: number = 0;
  /** 今天是周几（1=周一…7=周日），回前台跨天时重算以刷新"今天"高亮 */
  @State todayDay: number = 1;
  /** 应用回前台时刻戳（PondAbility onForeground），跨天时重算"今天" */
  @StorageProp('jwForegroundTick') @Watch('onForegroundTick') foregroundTick: number = 0;
  @State showDetail: boolean = false;
  @State selectedCell: ScheduleCellInfo = new ScheduleCellInfo();
  /** 窗口宽度是否达到宽屏（>=600vp）：平板/折叠屏展开时半模态默认为居中样式，需显式指定宽度 */
  @State isWideScreen: boolean = false;
  private wideQueryListener: mediaquery.MediaQueryListener | null = null;
  private wideQueryCallback: Callback<mediaquery.MediaQueryResult> | null = null;

  aboutToAppear(): void {
    this.refreshToday();
    const listener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(min-width: 600vp)');
    this.isWideScreen = listener.matches;
    this.wideQueryCallback = (result: mediaquery.MediaQueryResult): void => {
      this.isWideScreen = result.matches;
    };
    listener.on('change', this.wideQueryCallback);
    this.wideQueryListener = listener;
  }

  /** 应用回前台：跨天挂起后重算"今天"高亮 */
  onForegroundTick(): void {
    this.refreshToday();
  }

  private refreshToday(): void {
    const day: number = new Date().getDay();
    this.todayDay = day === 0 ? 7 : day;
  }

  aboutToDisappear(): void {
    if (this.wideQueryListener !== null && this.wideQueryCallback !== null) {
      this.wideQueryListener.off('change', this.wideQueryCallback);
    }
    this.wideQueryListener = null;
    this.wideQueryCallback = null;
  }

  private displayedWeek(): number {
    return this.termStatus.currentWeek + this.weekOffset;
  }

  /**
   * 当前所选周的课程：按周位图过滤。
   */
  private activeCells(): ScheduleCellInfo[] {
    const week: number = this.displayedWeek();
    return this.cells.filter((c: ScheduleCellInfo): boolean => c.activeInWeek(week));
  }

  private periodOfSection(section: number): number {
    const period: number = Math.ceil(section / 2);
    if (period < 1) {
      return 1;
    }
    if (period > PERIOD_COUNT) {
      return PERIOD_COUNT;
    }
    return period;
  }

  private cellsStartingAt(day: number, period: number): ScheduleCellInfo[] {
    return this.activeCells().filter((c: ScheduleCellInfo): boolean =>
      c.dayOfWeek === day && this.periodOfSection(c.startSection) === period);
  }

  private coveredByEarlier(day: number, period: number): boolean {
    const found: ScheduleCellInfo | undefined = this.activeCells().find((c: ScheduleCellInfo): boolean =>
      c.dayOfWeek === day && this.periodOfSection(c.startSection) < period
      && this.periodOfSection(c.endSection) >= period);
    return found !== undefined;
  }

  private blockHeight(cell: ScheduleCellInfo): number {
    const span: number =
      this.periodOfSection(cell.endSection) - this.periodOfSection(cell.startSection) + 1;
    return span * this.sectionRowHeight + (span - 1) * CELL_GAP;
  }

  private stackHeight(startingCells: ScheduleCellInfo[]): number {
    let height: number = this.sectionRowHeight;
    for (const cell of startingCells) {
      const blockHeight: number = this.blockHeight(cell);
      if (blockHeight > height) {
        height = blockHeight;
      }
    }
    return height;
  }

  private slotHeight(day: number, period: number): number {
    let content: number = this.sectionRowHeight;
    const startingCells: ScheduleCellInfo[] = this.cellsStartingAt(day, period);
    if (startingCells.length > 0) {
      content = this.stackHeight(startingCells);
    }
    if (period < PERIOD_COUNT) {
      return content + CELL_GAP;
    }
    return content;
  }

  @Builder
  dayHeader(day: number) {
    Column({ space: 2 }) {
      Text(DAY_NAMES[day - 1])
        .fontSize(12)
        .fontWeight(this.todayDay === day && this.weekOffset === 0 ?
          FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.todayDay === day && this.weekOffset === 0 ?
          $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_text_primary'))
      Text(this.todayDay === day ? '今天' : ' ')
        .fontSize(9)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .visibility(this.todayDay === day && this.weekOffset === 0 ?
          Visibility.Visible : Visibility.Hidden)
    }
    .width(this.dayCellWidth)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  detailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width(84)
      Text(value.length > 0 ? value : '—')
        .fontSize(16)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 该课程的单课提醒是否开启（未在关闭名单中即开启） */
  private courseReminderOn(courseName: string): boolean {
    return this.disabledCourses.indexOf(courseName) < 0;
  }

  /** 该课程的期末考试日期（未设置返回空串） */
  private examDateOf(courseName: string): string {
    const found: FinalExamEntry | undefined = this.finalExams
      .find((e: FinalExamEntry): boolean => e.courseName === courseName);
    return found !== undefined ? found.examDate : '';
  }

  /** 期末时间行右侧按钮文本：已设置显示日期，未设置显示"设置" */
  private examDateText(): string {
    const date: string = this.examDateOf(this.selectedCell.courseName);
    return date.length > 0 ? ExamDateUtils.formatDisplay(date) : '设置';
  }

  /** 期末时间行副标题：未设置时引导设置，已设置时显示倒计时 */
  private examSubtitle(): string {
    const date: string = this.examDateOf(this.selectedCell.courseName);
    if (date.length === 0) {
      return '设定该课程期末考试日期';
    }
    const parsed: Date | null = ExamDateUtils.parseYmd(date);
    if (parsed === null) {
      return '日期无效，点击重新设置';
    }
    return '距期末 ' + ExamDateUtils.countdownText(ExamDateUtils.daysFromDate(parsed));
  }

  /** 打开日期选择器设定期末时间 */
  private openExamDatePicker(): void {
    const current: string = this.examDateOf(this.selectedCell.courseName);
    const parsedCurrent: Date | null = current.length > 0 ? ExamDateUtils.parseYmd(current) : null;
    this.getUIContext().showDatePickerDialog({
      selected: parsedCurrent ?? new Date(),
      onDateAccept: (value: Date) => {
        JwxtRepository.updateFinalExam(this.selectedCell.courseName, ExamDateUtils.toYmd(value));
      }
    });
  }

  @Builder
  courseDetailSheet() {
    Column({ space: 12 }) {
      Text(this.selectedCell.courseName)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .padding({ right: 48 })
      this.detailRow('时间', DAY_NAMES[this.selectedCell.dayOfWeek - 1] + ' 第' + this.selectedCell.startSection
        + '-' + this.selectedCell.endSection + '节'
        + ' ' + this.periodTimeOf(this.selectedCell))
      this.detailRow('周次', this.selectedCell.weeksText)
      this.detailRow('地点', this.selectedCell.location)
      this.detailRow('教师', this.selectedCell.teacher)
      if (this.selectedCell.courseSerialNo.length > 0) {
        this.detailRow('课程序号', this.selectedCell.courseSerialNo)
      }
      Divider()
        .color($r('sys.color.ohos_id_color_list_separator'))
      Row() {
        Column({ space: 2 }) {
          Text('上课提醒')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text('提醒时间在"设置"中调整')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.courseReminderOn(this.selectedCell.courseName) })
          .onChange((isOn: boolean) => {
            JwxtRepository.updateCourseReminder(this.selectedCell.courseName, isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color($r('sys.color.ohos_id_color_list_separator'))

      Row() {
        Column({ space: 2 }) {
          Text('期末时间')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text(this.examSubtitle())
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.examDateText())
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.openExamDatePicker();
          })
        if (this.examDateOf(this.selectedCell.courseName).length > 0) {
          Text('清除')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .padding({ left: 10 })
            .onClick(() => {
              JwxtRepository.updateFinalExam(this.selectedCell.courseName, '');
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 28, right: 28, top: 12, bottom: 36 })
  }

  private periodTimeOf(cell: ScheduleCellInfo): string {
    const startPeriod: number = this.periodOfSection(cell.startSection);
    const endPeriod: number = this.periodOfSection(cell.endSection);
    const times: string[] = [];
    for (let i: number = startPeriod; i <= endPeriod; i++) {
      times.push(PERIOD_TIMES[i - 1]);
    }
    return times.join(' / ');
  }

  @Builder
  courseBlock(startingCells: ScheduleCellInfo[]) {
    Column({ space: 2 }) {
      ForEach(startingCells, (cell: ScheduleCellInfo) => {
        Text(cell.courseName)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (cell: ScheduleCellInfo) => 'stack' + cell.courseSerialNo + cell.startSection)
      Text(startingCells[0].location)
        .fontSize(9)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(startingCells[0].teacher)
        .fontSize(9)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.stackHeight(startingCells))
    .padding(4)
    .backgroundColor(startingCells[0].colorHex)
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.selectedCell = startingCells[0];
      this.showDetail = true;
    })
  }

  @Builder
  dayColumn(day: number) {
    Column() {
      ForEach(PERIOD_LABELS, (label: string, index: number) => {
        if (!this.coveredByEarlier(day, index + 1)) {
          Column() {
            if (this.cellsStartingAt(day, index + 1).length > 0) {
              this.courseBlock(this.cellsStartingAt(day, index + 1))
            } else {
              Column()
                .width('100%')
                .height(this.sectionRowHeight)
                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                .borderRadius(4)
                .opacity(0.35)
            }
          }
          .width(this.dayCellWidth)
          .height(this.slotHeight(day, index + 1))
        }
      }, (label: string, index: number) => 'day' + day + '-period' + index)
    }
    .width(this.dayCellWidth)
  }

  build() {
    Scroll() {
      Column() {
        if (this.showHeader) {
          Row({ space: CELL_GAP }) {
            Column() {
              Text('第' + this.displayedWeek() + '周')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
            }
            .width(LABEL_COLUMN_WIDTH)
            .justifyContent(FlexAlign.Center)
            ForEach(DAY_NAMES, (name: string, index: number) => {
              this.dayHeader(index + 1)
            }, (name: string, index: number) => 'header' + index)
          }
          .margin({ bottom: 6 })
          .alignItems(VerticalAlign.Center)
        }
        Row({ space: CELL_GAP }) {
          Column({ space: CELL_GAP }) {
            ForEach(PERIOD_LABELS, (label: string, index: number) => {
              Column({ space: 1 }) {
                Text(label)
                  .fontSize(10)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                Text(PERIOD_TIMES[index])
                  .fontSize(8)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              }
              .width(LABEL_COLUMN_WIDTH)
              .height(this.sectionRowHeight)
              .justifyContent(FlexAlign.Center)
            }, (label: string, index: number) => 'label' + index)
          }
          .width(LABEL_COLUMN_WIDTH)
          ForEach(DAY_NAMES, (name: string, index: number) => {
            this.dayColumn(index + 1)
          }, (name: string, index: number) => 'column' + index)
        }
        .alignItems(VerticalAlign.Top)
      }
      .constraintSize({ minWidth: '100%' })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
    .bindSheet($$this.showDetail, this.courseDetailSheet(), {
      height: this.isWideScreen ? SheetSize.FIT_CONTENT : SheetSize.MEDIUM,
      width: this.isWideScreen ? 560 : '100%',
      dragBar: true,
      showClose: true
    })
  }
}
