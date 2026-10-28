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
 * 课表服务卡片（2*4）：展示今日课程（最多 3 门）与当前周次。
 * 数据由 ScheduleFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(storage) 接收，否则卡片拿不到数据。
 * coursesJson 等属性变化时通过 @Watch 重新解析（updateForm 刷新路径）。
 */
@Entry(storage)
@Component
struct ScheduleCard {
  @LocalStorageProp('weekText') weekText: string = '';
  @LocalStorageProp('coursesJson') @Watch('onDataChanged') coursesJson: string = '[]';
  @LocalStorageProp('moreText') moreText: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';
  /** 严格隐私模式下非空：卡片不可用提示 */
  @LocalStorageProp('privacyDisabledText') privacyDisabledText: string = '';
  @State courses: CardCourse[] = [];

  aboutToAppear(): void {
    this.parseCourses();
  }

  onDataChanged(): void {
    this.parseCourses();
  }

  private parseCourses(): void {
    let parsed: CardCourse[] = [];
    try {
      const raw: CardCourseRaw[] = JSON.parse(this.coursesJson) as CardCourseRaw[];
      for (const item of raw) {
        const course: CardCourse = new CardCourse();
        course.time = item.time ?? '';
        course.name = item.name ?? '';
        course.place = item.place ?? '';
        parsed.push(course);
      }
    } catch (error) {
      parsed = [];
    }
    this.courses = parsed;
  }

  build() {
    Column() {
      Row() {
        Text('今日课程')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
        if (this.weekText.length > 0) {
          Text(this.weekText)
            .fontSize(10)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
      }
      .width('100%')
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
      } else if (this.courses.length === 0) {
        Column() {
          Text(this.emptyText.length > 0 ? this.emptyText : '登录教务系统后同步课表')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 6 }) {
          ForEach(this.courses, (course: CardCourse) => {
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
          }, (course: CardCourse, index: number) => 'course' + index + course.name)
          if (this.moreText.length > 0) {
            Text(this.moreText)
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
  }
}
