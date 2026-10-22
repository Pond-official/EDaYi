import { ScheduleCellInfo, TermStatus } from '../model/JwModels';

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
  @Prop dayCellWidth: number = 52;
  @Prop sectionRowHeight: number = 62;
  @Prop showHeader: boolean = true;
  /** 0=本周，1=下周，由父组件控制 */
  @Prop weekOffset: number = 0;
  private todayDay: number = 1;
  @State showDetail: boolean = false;
  @State selectedCell: ScheduleCellInfo = new ScheduleCellInfo();

  aboutToAppear(): void {
    const day: number = new Date().getDay();
    this.todayDay = day === 0 ? 7 : day;
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
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width(76)
      Text(value.length > 0 ? value : '—')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  courseDetailSheet() {
    Column({ space: 12 }) {
      Text(this.selectedCell.courseName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      this.detailRow('时间', DAY_NAMES[this.selectedCell.dayOfWeek - 1] + ' 第' + this.selectedCell.startSection
        + '-' + this.selectedCell.endSection + '节'
        + ' ' + this.periodTimeOf(this.selectedCell))
      this.detailRow('周次', this.selectedCell.weeksText)
      this.detailRow('地点', this.selectedCell.location)
      this.detailRow('教师', this.selectedCell.teacher)
      if (this.selectedCell.courseSerialNo.length > 0) {
        this.detailRow('课程序号', this.selectedCell.courseSerialNo)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: 8, bottom: 32 })
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
    .width('100%')
    .bindSheet($$this.showDetail, this.courseDetailSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true
    })
  }
}
