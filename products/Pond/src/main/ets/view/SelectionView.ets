import { ElectiveCourseInfo } from '../model/JwModels';

/**
 * 选课页：选课批次说明 + 课程搜索 + 可选课程列表（原生 Row/Column 布局）。
 * 选课系统（jwxk.dmu.edu.cn）为独立账号体系，课程数据需登录选课系统后在线获取，
 * 未获取到数据时展示引导空态，不内置任何演示数据。
 */
@Component
export struct SelectionView {
  @StorageProp('jwElectives') electives: ElectiveCourseInfo[] = [];
  @StorageProp('jwDataMode') dataMode: string = 'preview';
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  @State keyword: string = '';
  @State chosenIds: string[] = [];

  private filteredCourses(): ElectiveCourseInfo[] {
    if (this.keyword.length === 0) {
      return this.electives;
    }
    return this.electives.filter((c: ElectiveCourseInfo): boolean => c.name.indexOf(this.keyword) >= 0
      || c.teacher.indexOf(this.keyword) >= 0);
  }

  private isChosen(course: ElectiveCourseInfo): boolean {
    return this.chosenIds.indexOf(course.courseId) >= 0;
  }

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 600;
    }
    return 1000;
  }

  private bottomInset(): number {
    return 88;
  }

  @Builder
  noticeCard() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(22)
        .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
      Column({ space: 2 }) {
        Text('公告')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('暂未支持，敬请期待')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  batchCard() {
    Column({ space: 6 }) {
      Text('通识选修课')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('选课功能暂未支持，敬请期待。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
  }

  @Builder
  emptyCard() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(40)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      Text('暂未支持，敬请期待')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('选课功能正在开发中，开放后将在这里提供在线选课。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 32, bottom: 32, left: 24, right: 24 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
  }

  @Builder
  courseCard(course: ElectiveCourseInfo) {
    Column({ space: 8 }) {
      Row() {
        Text(course.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(course.credit + '学分')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      Text(course.teacher + ' · ' + course.timeText + ' · ' + course.place)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ bottom: 12 })
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.noticeCard()
          this.batchCard()
          if (this.electives.length === 0) {
            this.emptyCard()
          } else {
            TextInput({ placeholder: '搜索课程名或教师', text: this.keyword })
              .fontSize(13)
              .height(40)
              .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
              .borderRadius(20)
              .margin({ top: 12, bottom: 12 })
              .onChange((value: string) => {
                this.keyword = value;
              })
            ForEach(this.filteredCourses(), (course: ElectiveCourseInfo) => {
              this.courseCard(course)
            }, (course: ElectiveCourseInfo) => course.courseId)
          }
        }
        .padding({ left: 16, right: 16, top: 8, bottom: this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
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
