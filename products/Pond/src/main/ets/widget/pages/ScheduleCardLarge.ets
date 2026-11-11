let largeStorage = new LocalStorage();

const CARD_DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const CARD_CELL_GAP: number = 4;
const CARD_PERIOD_COUNT: number = 5;
const CARD_PERIOD_LABELS: string[] = ['1-2节', '3-4节', '5-6节', '7-8节', '9-10节'];
const CARD_PERIOD_TIMES: string[] = ['8:30-10:00', '10:20-11:50', '13:20-14:50', '15:00-16:30', '17:30-19:00'];
const CARD_LABEL_WIDTH: number = 44;

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
 * 支持点击"下周"切换查看下周课表（再点"本周"切回），下周模式不渲染"今天"高亮。
 * 行高不固定：五大节槽位按 layoutWeight 权重均分卡片高度（课程槽权重=跨节数），
 * 卡片多高都完整显示 1-2 到 9-10 全部五大节，底部不再被裁剪。
 * 数据由 ScheduleFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(largeStorage) 接收；数据来自最近一次成功同步的离线存储。
 * 点击卡片其他区域通过 postCardAction router 拉起 PondAbility 进入应用；
 * 切换胶囊自身绑定 onClick，点击时优先于整卡 router（父子手势竞争，内层胜出）。
 */
@Entry(largeStorage)
@Component
struct ScheduleCardLarge {
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('weekCellsJson') @Watch('onDataChanged') weekCellsJson: string = '[]';
  @LocalStorageProp('nextWeekCellsJson') @Watch('onDataChanged') nextWeekCellsJson: string = '[]';
  @LocalStorageProp('nextWeekText') nextWeekText: string = '';
  @LocalStorageProp('todayD') todayD: string = '0';
  /** 严格隐私模式下非空：卡片不可用提示 */
  @LocalStorageProp('privacyDisabledText') privacyDisabledText: string = '';
  /** 查看下周课表模式（点击"下周"开启、"本周"关闭） */
  @State showNextWeek: boolean = false;
  @State cells: WeekCourseCell[] = [];
  @State nextCells: WeekCourseCell[] = [];

  aboutToAppear(): void {
    this.parseCells();
  }

  onDataChanged(): void {
    this.parseCells();
  }

  private parseCells(): void {
    this.cells = this.parseWeekCells(this.weekCellsJson);
    this.nextCells = this.parseWeekCells(this.nextWeekCellsJson);
  }

  private parseWeekCells(json: string): WeekCourseCell[] {
    const parsed: WeekCourseCell[] = [];
    try {
      const raw: WeekCourseRaw[] = JSON.parse(json) as WeekCourseRaw[];
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
      return [];
    }
    return parsed;
  }

  /** 是否已同步过课表（同步后 weekText 非空，切换入口才有数据可看） */
  private synced(): boolean {
    return this.weekText.length > 0;
  }

  /** 当前展示模式的课程格（本周/下周） */
  private activeCells(): WeekCourseCell[] {
    return this.showNextWeek ? this.nextCells : this.cells;
  }

  /** 当前展示模式的周次文本（表头左上角标签） */
  private activeWeekText(): string {
    if (this.showNextWeek) {
      return this.nextWeekText.length > 0 ? this.nextWeekText : '下周';
    }
    return this.weekText.length > 0 ? this.weekText : '本周';
  }

  private isToday(day: number): boolean {
    if (this.showNextWeek) {
      return false;
    }
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
    return this.activeCells().filter((c: WeekCourseCell): boolean =>
      c.d === day && this.periodOfSection(c.s) === period);
  }

  private coveredByEarlier(day: number, period: number): boolean {
    const found: WeekCourseCell | undefined = this.activeCells().find((c: WeekCourseCell): boolean =>
      c.d === day && this.periodOfSection(c.s) < period
      && this.periodOfSection(c.e) >= period);
    return found !== undefined;
  }

  /**
   * 起始大节槽位内课程的最大跨节数（权重 = 跨度，占多行）。
   */
  private startingSpan(startingCells: WeekCourseCell[]): number {
    let span: number = 1;
    for (const cell of startingCells) {
      const cellSpan: number =
        this.periodOfSection(cell.e) - this.periodOfSection(cell.s) + 1;
      if (cellSpan > span) {
        span = cellSpan;
      }
    }
    return span;
  }

  /** 大节槽位垂直权重：空槽=1，课程槽=最大跨节数（被覆盖的槽位不渲染） */
  private slotWeight(day: number, period: number): number {
    const startingCells: WeekCourseCell[] = this.cellsStartingAt(day, period);
    if (startingCells.length === 0) {
      return 1;
    }
    return this.startingSpan(startingCells);
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
  weekChip(label: string, selected: boolean, isNext: boolean) {
    Text(label)
      .fontSize(10)
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(selected ? Color.White : $r('sys.color.ohos_id_color_text_secondary'))
      .backgroundColor(selected ? '#007DFF' : $r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(9)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .onClick(() => {
        this.showNextWeek = isNext;
      })
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
    .layoutWeight(1)
    .padding(3)
    .backgroundColor(startingCells[0].c.length > 0 ? startingCells[0].c : '#E8F3DB')
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  dayColumn(day: number) {
    Column({ space: CARD_CELL_GAP }) {
      ForEach(CARD_PERIOD_LABELS, (label: string, index: number) => {
        if (!this.coveredByEarlier(day, index + 1)) {
          Column() {
            if (this.cellsStartingAt(day, index + 1).length > 0) {
              this.courseBlock(this.cellsStartingAt(day, index + 1))
            } else {
              Column()
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
                .borderRadius(4)
                .opacity(0.35)
            }
          }
          .width('100%')
          .layoutWeight(this.slotWeight(day, index + 1))
        }
      }, (label: string, index: number) => 'day' + day + '-period' + index)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      if (this.privacyDisabledText.length > 0) {
        Text(this.privacyDisabledText)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .textAlign(TextAlign.Center)
      } else if (!this.synced()) {
        Text('登录教务系统后同步课表')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        Row({ space: 4 }) {
          this.weekChip('本周', !this.showNextWeek, false)
          this.weekChip('下周', this.showNextWeek, true)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 4 })
        if (this.activeCells().length === 0) {
          Text(this.showNextWeek ? '下周暂无课程安排' : '本周暂无课程安排')
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        } else {
          Column() {
            Row({ space: CARD_CELL_GAP }) {
              Text(this.activeWeekText())
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
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                }, (label: string, index: number) => 'label' + index)
              }
              .width(CARD_LABEL_WIDTH)
              .height('100%')
              ForEach(CARD_DAY_NAMES, (name: string, index: number) => {
                this.dayColumn(index + 1)
              }, (name: string, index: number) => 'column' + index)
            }
            .width('100%')
            .layoutWeight(1)
            .alignItems(VerticalAlign.Top)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'PondAbility',
        'params': {}
      });
    })
  }
}
