import { WIDGET_SELECTED_COLOR } from '../../theme/AppColors';

let storage = new LocalStorage();

class CardCourse {
  time: string = '';
  name: string = '';
  place: string = '';
}

interface CardCourseRaw {
  time?: string;
  name?: string;
  place?: string;
}

/**
 * 课表服务卡片（2*4）：展示今日课程（最多 3 门）与当前周次，
 * 支持点击"明天"切换查看明日课程（再点"今天"切回）。
 * 数据由 ScheduleFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(storage) 接收，否则卡片拿不到数据。
 * coursesJson/tomorrowJson 等属性变化时通过 @Watch 重新解析（updateForm 刷新路径）。
 * 点击卡片其他区域通过 postCardAction router 拉起 PondAbility 进入应用；
 * 切换胶囊自身绑定 onClick，点击时优先于整卡 router（父子手势竞争，内层胜出）。
 */
@Entry(storage)
@Component
struct ScheduleCard {
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('coursesJson') @Watch('onDataChanged') coursesJson: string = '[]';
  @LocalStorageProp('moreText') moreText: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';
  @LocalStorageProp('tomorrowJson') @Watch('onDataChanged') tomorrowJson: string = '[]';
  @LocalStorageProp('tomorrowMoreText') tomorrowMoreText: string = '';
  @LocalStorageProp('tomorrowEmptyText') tomorrowEmptyText: string = '';
  @LocalStorageProp('tomorrowWeekText') tomorrowWeekText: string = '';
  /** 严格隐私模式下非空：卡片不可用提示 */
  @LocalStorageProp('privacyDisabledText') privacyDisabledText: string = '';
  /** 查看明日课程模式（点击"明天"开启、"今天"关闭） */
  @State showTomorrow: boolean = false;
  @State courses: CardCourse[] = [];
  @State tomorrowCourses: CardCourse[] = [];

  aboutToAppear(): void {
    this.parseCourses();
  }

  onDataChanged(): void {
    this.parseCourses();
  }

  private parseCourses(): void {
    this.courses = this.parseCourseList(this.coursesJson);
    this.tomorrowCourses = this.parseCourseList(this.tomorrowJson);
  }

  private parseCourseList(json: string): CardCourse[] {
    const parsed: CardCourse[] = [];
    try {
      const raw: CardCourseRaw[] = JSON.parse(json) as CardCourseRaw[];
      for (const item of raw) {
        const course: CardCourse = new CardCourse();
        course.time = item.time ?? '';
        course.name = item.name ?? '';
        course.place = item.place ?? '';
        parsed.push(course);
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

  private titleText(): string {
    return this.showTomorrow ? '明日课程' : '今日课程';
  }

  private activeWeekText(): string {
    if (!this.synced()) {
      return '';
    }
    const weekText: string = this.showTomorrow ? this.tomorrowWeekText : this.weekText;
    return weekText.length > 0 ? ' ' + weekText : '';
  }

  private activeCourses(): CardCourse[] {
    return this.showTomorrow ? this.tomorrowCourses : this.courses;
  }

  private activeEmptyText(): string {
    if (this.showTomorrow) {
      return this.tomorrowEmptyText.length > 0 ? this.tomorrowEmptyText : '明天没有课程安排';
    }
    return this.emptyText.length > 0 ? this.emptyText : '登录教务系统后同步课表';
  }

  private activeMoreText(): string {
    return this.showTomorrow ? this.tomorrowMoreText : this.moreText;
  }

  // 高亮状态在 Builder 体内直读 this.showTomorrow：按值传参不随状态刷新，经参数传递会导致指示器不更新
  /** 今天/明天切换胶囊：单容器包裹两个选项，选中指示器随状态左右滑动（属性动画） */
  @Builder
  dayToggle() {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width('50%')
        .height('100%')
        .borderRadius(11)
        .backgroundColor(WIDGET_SELECTED_COLOR)
        .translate({ x: this.showTomorrow ? '100%' : '0%' })
        .animation({ duration: 200, curve: Curve.EaseOut })
      Row() {
        Text('今天')
          .fontSize(10)
          .fontWeight(this.showTomorrow ? FontWeight.Normal : FontWeight.Bold)
          .fontColor(this.showTomorrow ?
            $r('sys.color.ohos_id_color_text_secondary') : Color.White)
          .height('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showTomorrow = false;
          })
        Text('明天')
          .fontSize(10)
          .fontWeight(this.showTomorrow ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.showTomorrow ? Color.White : $r('sys.color.ohos_id_color_text_secondary'))
          .height('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.showTomorrow = true;
          })
      }
      .width('100%')
      .height('100%')
    }
    .width(64)
    .height(22)
    .borderRadius(11)
    .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    .margin({ left: 6 })
  }

  build() {
    Column() {
      Row() {
        Text() {
          Span(this.titleText())
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Span(this.activeWeekText())
            .fontSize(10)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.privacyDisabledText.length === 0 && this.synced()) {
          this.dayToggle()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (this.privacyDisabledText.length > 0) {
        Column() {
          Text(this.privacyDisabledText)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.activeCourses().length === 0) {
        Column() {
          Text(this.activeEmptyText())
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 6 }) {
          ForEach(this.activeCourses(), (course: CardCourse) => {
            Row() {
              Text(course.time)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .width(40)
              Column() {
                Text(course.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(course.place)
                  .fontSize(9)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (course: CardCourse, index: number) =>
            (this.showTomorrow ? 'tomorrow' : 'today') + index + course.name)
          if (this.activeMoreText().length > 0) {
            Text(this.activeMoreText())
              .fontSize(9)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
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
