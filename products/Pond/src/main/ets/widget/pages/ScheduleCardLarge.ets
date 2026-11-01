let largeStorage = new LocalStorage();

const CARD_DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const CARD_CELL_GAP: number = 4;
const CARD_PERIOD_COUNT: number = 5;
const CARD_PERIOD_LABELS: string[] = ['1-2节', '3-4节', '5-6节', '7-8节', '9-10节'];
const CARD_PERIOD_TIMES: string[] = ['8:30-10:00', '10:20-11:50', '13:20-14:50', '15:00-16:30', '17:30-19:00'];
const CARD_LABEL_WIDTH: number = 44;
const CARD_ROW_HEIGHT: number = 78;

class WeekCourseCell {
  d: number = 1;
  s: number = 1;
  e: number = 1;
  n: string = '';
  p: string = '';
  r: string = '';
  c: string = '';
}

interface WeekCourseRaw {
  d?: number;
  s?: number;
  e?: number;
  n?: string;
  p?: string;
  r?: string;
  c?: string;
}

/**
 * 课表服务卡片（4*4）：套用应用内 ScheduleBoard 的排布——
 * 表头（第N周 + 周一~周日，今日高亮）、左侧大节时间标签、
 * 每天按大节占位（被跨节课程覆盖的大节不渲染，包裹层高=内容高+尾随间距），
 * 课程块显示课名/地点/教师，空槽为浅灰占位。
 * 数据由 ScheduleFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(largeStorage) 接收；数据来自最近一次成功同步的离线存储。
 */
@Entry(largeStorage)
@Component
struct ScheduleCardLarge {
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('weekCellsJson') @Watch('onDataChanged') weekCellsJson: string = '[]';
  @LocalStorageProp('todayD') todayD: string = '0';
  /** 严格隐私模式下非空：卡片不可用提示 */
  @LocalStorageProp('privacyDisabledText') privacyDisabledText: string = '';
  @State cells: WeekCourseCell[] = [];

  aboutToAppear(): void {
    this.parseCells();
  }

  onDataChanged(): void {
    this.parseCells();
  }

  private parseCells(): void {
    const parsed: WeekCourseCell[] = [];
    try {
      const raw: WeekCourseRaw[] = JSON.parse(this.weekCellsJson) as WeekCourseRaw[];
      for (const item of raw) {
        const day: number = typeof item.d === 'number' ? item.d : 0;
        const start: number = typeof item.s === 'number' ? item.s : 0;
        if (day < 1 || day > 7 || start < 1 || start > 10) {
          continue;
        }
        const cell: WeekCourseCell = new WeekCourseCell();
        cell.d = day;
        cell.s = start;
        cell.e = typeof item.e === 'number' && item.e >= start ? item.e : start;
        cell.n = typeof item.n === 'string' ? item.n : '';
        cell.p = typeof item.p === 'string' ? item.p : '';
        cell.r = typeof item.r === 'string' ? item.r : '';
        cell.c = typeof item.c === 'string' ? item.c : '';
        parsed.push(cell);
      }
    } catch (error) {
      parsed.length = 0;
    }
    this.cells = parsed;
  }

  private isToday(day: number): boolean {
    const today: number = Number(this.todayD);
    return today === day;
  }

  private periodOfSection(section: number): number {
    const period: number = Math.ceil(section / 2);
    if (period < 1) {
      return 1;
    }
    if (period > CARD_PERIOD_COUNT) {
      return CARD_PERIOD_COUNT;
    }
    return period;
  }

  private cellsStartingAt(day: number, period: number): WeekCourseCell[] {
    return this.cells.filter((c: WeekCourseCell): boolean =>
      c.d === day && this.periodOfSection(c.s) === period);
  }

  private coveredByEarlier(day: number, period: number): boolean {
    const found: WeekCourseCell | undefined = this.cells.find((c: WeekCourseCell): boolean =>
      c.d === day && this.periodOfSection(c.s) < period
      && this.periodOfSection(c.e) >= period);
    return found !== undefined;
  }

  private blockHeight(cell: WeekCourseCell): number {
    const span: number =
      this.periodOfSection(cell.e) - this.periodOfSection(cell.s) + 1;
    return span * CARD_ROW_HEIGHT + (span - 1) * CARD_CELL_GAP;
  }

  private stackHeight(startingCells: WeekCourseCell[]): number {
    let height: number = CARD_ROW_HEIGHT;
    for (const cell of startingCells) {
      const blockHeight: number = this.blockHeight(cell);
      if (blockHeight > height) {
        height = blockHeight;
      }
    }
    return height;
  }

  private slotHeight(day: number, period: number): number {
    let content: number = CARD_ROW_HEIGHT;
    const startingCells: WeekCourseCell[] = this.cellsStartingAt(day, period);
    if (startingCells.length > 0) {
      content = this.stackHeight(startingCells);
    }
    if (period < CARD_PERIOD_COUNT) {
      return content + CARD_CELL_GAP;
    }
    return content;
  }

  @Builder
  dayHeader(day: number) {
    Column({ space: 1 }) {
      Text(CARD_DAY_NAMES[day - 1])
        .fontSize(11)
        .fontWeight(this.isToday(day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.isToday(day) ?
          $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_text_primary'))
      Text(this.isToday(day) ? '今天' : ' ')
        .fontSize(7)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .visibility(this.isToday(day) ? Visibility.Visible : Visibility.Hidden)
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  courseBlock(startingCells: WeekCourseCell[]) {
    Column({ space: 2 }) {
      ForEach(startingCells, (cell: WeekCourseCell) => {
        Text(cell.n)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (cell: WeekCourseCell, index: number) => 'stack' + index + cell.s + cell.n)
      Text(startingCells[0].p)
        .fontSize(8)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(startingCells[0].r)
        .fontSize(8)
        .fontColor('#555555')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(this.stackHeight(startingCells))
    .padding(3)
    .backgroundColor(startingCells[0].c.length > 0 ? startingCells[0].c : '#E8F3DB')
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  dayColumn(day: number) {
    Column() {
      ForEach(CARD_PERIOD_LABELS, (label: string, index: number) => {
        if (!this.coveredByEarlier(day, index + 1)) {
          Column() {
            if (this.cellsStartingAt(day, index + 1).length > 0) {
              this.courseBlock(this.cellsStartingAt(day, index + 1))
            } else {
              Column()
                .width('100%')
                .height(CARD_ROW_HEIGHT)
                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                .borderRadius(4)
                .opacity(0.35)
            }
          }
          .width('100%')
          .height(this.slotHeight(day, index + 1))
        }
      }, (label: string, index: number) => 'day' + day + '-period' + index)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      if (this.privacyDisabledText.length > 0) {
        Text(this.privacyDisabledText)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .textAlign(TextAlign.Center)
      } else if (this.cells.length === 0 && this.weekText.length === 0) {
        Text('登录教务系统后同步课表')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else if (this.cells.length === 0) {
        Text('本周暂无课程安排')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        Column() {
          Row({ space: CARD_CELL_GAP }) {
            Text(this.weekText.length > 0 ? this.weekText : '本周')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .width(CARD_LABEL_WIDTH)
              .textAlign(TextAlign.Center)
            ForEach(CARD_DAY_NAMES, (name: string, index: number) => {
              this.dayHeader(index + 1)
            }, (name: string, index: number) => 'header' + index)
          }
          .width('100%')
          .margin({ bottom: 4 })
          .alignItems(VerticalAlign.Center)
          Row({ space: CARD_CELL_GAP }) {
            Column({ space: CARD_CELL_GAP }) {
              ForEach(CARD_PERIOD_LABELS, (label: string, index: number) => {
                Column({ space: 1 }) {
                  Text(label)
                    .fontSize(9)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  Text(CARD_PERIOD_TIMES[index])
                    .fontSize(7)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                }
                .width(CARD_LABEL_WIDTH)
                .height(CARD_ROW_HEIGHT)
                .justifyContent(FlexAlign.Center)
              }, (label: string, index: number) => 'label' + index)
            }
            .width(CARD_LABEL_WIDTH)
            ForEach(CARD_DAY_NAMES, (name: string, index: number) => {
              this.dayColumn(index + 1)
            }, (name: string, index: number) => 'column' + index)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }
}
