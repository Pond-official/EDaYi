import { COURSE_CELL_DEFAULT_BG, TEXT_DARK, TEXT_MEDIUM, WIDGET_SELECTED_COLOR } from '../../theme/AppColors';
import { TermWeekUtils } from '../../utils/TermWeekUtils';

let largeStorage = new LocalStorage();

const CARD_DAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const CARD_CELL_GAP: number = 4;
const CARD_PERIOD_COUNT: number = 6;
const CARD_PERIOD_LABELS: string[] = ['1-2节', '3-4节', '5-6节', '7-8节', '9-10节', '11-12节'];
const CARD_PERIOD_TIMES: string[] =
  ['8:30-10:00', '10:20-11:50', '13:20-14:50', '15:00-16:30', '17:30-19:00', '19:10-20:40'];
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
 * 行高不固定：大节槽位按 layoutWeight 权重均分卡片高度（课程槽权重=跨节数），
 * 底部不被裁剪；大节行动态渲染——仅所显周内存在该大节起步课程时显示该行
 * （含 label 与时间），无课大节（如晚间 11-12 节）不渲染空占位行。
 * 数据由 ScheduleFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(largeStorage) 接收；数据来自最近一次成功同步的离线存储。
 * 点击卡片其他区域通过 postCardAction router 拉起 PondAbility 进入应用；
 * 切换胶囊自身绑定 onClick，点击时优先于整卡 router（父子手势竞争，内层胜出）；
 * 胶囊外围包一层 padding 安全区并绑定空 onClick 吞掉点击，顶部切换行同样划为安全区，
 * 安全区内点击不拉起应用。
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
        if (day < 1 || day > 7 || start < 1 || start > 12) {
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

  /** 渲染的大节序号列表：仅保留所显周内存在起步课程的大节（无课大节不渲染占位行） */
  private visiblePeriods(): number[] {
    const periods: number[] = [];
    const actives: WeekCourseCell[] = this.activeCells();
    for (let period: number = 1; period <= CARD_PERIOD_COUNT; period++) {
      for (const cell of actives) {
        if (this.periodOfSection(cell.s) === period) {
          periods.push(period);
          break;
        }
      }
    }
    return periods;
  }

  /** 表头日期取时实例：headerDateLabel 内 setTime 复用，避免重复 new Date */
  private readonly dateScratch: Date = new Date();

  /** 表头日期文本：所显周（本周/下周）第 day 天对应的 'M/d'（如 11/24） */
  private headerDateLabel(day: number): string {
    this.dateScratch.setTime(Date.now());
    const monday: Date = TermWeekUtils.mondayOf(this.dateScratch);
    const target: Date = new Date(monday.getFullYear(), monday.getMonth(),
      monday.getDate() + (this.showNextWeek ? 7 : 0) + day - 1);
    return (target.getMonth() + 1) + '/' + target.getDate();
  }

  @Builder
  dayHeader(day: number) {
    Column({ space: 1 }) {
      Text(CARD_DAY_NAMES[day - 1])
        .fontSize(11)
        .fontWeight(this.isToday(day) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.isToday(day) ?
          $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_text_primary'))
      Text(this.isToday(day) ? '今天' : this.headerDateLabel(day))
        .fontSize(7)
        .fontColor(this.isToday(day) ?
          $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  // 高亮状态在 Builder 体内直读 this.showNextWeek：按值传参不随状态刷新，经参数传递会导致指示器不更新
  /** 本周/下周切换胶囊：单容器包裹两个选项，选中指示器随状态左右滑动（属性动画）；
   * 外层 padding 安全区绑定空 onClick，安全区内点击不触发整卡 router 拉起应用 */
  @Builder
  weekToggle() {
    Column() {
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('50%')
          .height('100%')
          .borderRadius(12)
          .backgroundColor(WIDGET_SELECTED_COLOR)
          .translate({ x: this.showNextWeek ? '100%' : '0%' })
          .animation({ duration: 200, curve: Curve.EaseOut })
        Row() {
          Text('本周')
            .fontSize(10)
            .fontWeight(this.showNextWeek ? FontWeight.Normal : FontWeight.Bold)
            .fontColor(this.showNextWeek ?
              $r('sys.color.ohos_id_color_text_secondary') : Color.White)
            .height('100%')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showNextWeek = false;
            })
          Text('下周')
            .fontSize(10)
            .fontWeight(this.showNextWeek ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.showNextWeek ? Color.White : $r('sys.color.ohos_id_color_text_secondary'))
            .height('100%')
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showNextWeek = true;
            })
        }
        .width('100%')
        .height('100%')
      }
      .width(68)
      .height(24)
      .borderRadius(12)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .onClick(() => {
    })
  }

  @Builder
  courseBlock(startingCells: WeekCourseCell[]) {
    Column({ space: 2 }) {
      ForEach(startingCells, (cell: WeekCourseCell) => {
        Text(cell.n)
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(TEXT_DARK)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }, (cell: WeekCourseCell, index: number) => 'stack' + index + cell.s + cell.n)
      Text(startingCells[0].p)
        .fontSize(8)
        .fontColor(TEXT_MEDIUM)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(startingCells[0].r)
        .fontSize(8)
        .fontColor(TEXT_MEDIUM)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .layoutWeight(1)
    .padding(3)
    .backgroundColor(startingCells[0].c.length > 0 ? startingCells[0].c : COURSE_CELL_DEFAULT_BG)
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  dayColumn(day: number) {
    Column({ space: CARD_CELL_GAP }) {
      ForEach(this.visiblePeriods(), (period: number) => {
        if (!this.coveredByEarlier(day, period)) {
          Column() {
            if (this.cellsStartingAt(day, period).length > 0) {
              this.courseBlock(this.cellsStartingAt(day, period))
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
          .layoutWeight(this.slotWeight(day, period))
        }
      }, (period: number) => 'day' + day + '-period' + period)
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
        Row() {
          this.weekToggle()
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ bottom: 4 })
        .onClick(() => {
        })
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
                ForEach(this.visiblePeriods(), (period: number) => {
                  Column({ space: 1 }) {
                    Text(CARD_PERIOD_LABELS[period - 1])
                      .fontSize(9)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    Text(CARD_PERIOD_TIMES[period - 1])
                      .fontSize(7)
                      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  }
                  .width(CARD_LABEL_WIDTH)
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)
                }, (period: number) => 'label' + period)
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
