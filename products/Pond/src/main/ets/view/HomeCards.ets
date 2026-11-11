import { FinalExamEntry, ScheduleCellInfo } from '../model/JwModels';
import { ExamDateUtils } from '../utils/ExamDateUtils';

/** 离线数据提示条（自 HomeView 拆出；onLogin 跳登录） */
@Builder
export function HomeOfflineBanner(onLogin: () => void) {
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
    onLogin();
  })
}

/** 学生信息卡（自 HomeView 拆出） */
@Builder
export function HomeStudentCard(name: string, studentId: string, className: string, collegeName: string) {
  Column() {
    Row() {
      Stack() {
        Text(name.length > 0 ? name.substring(0, 1) : '生')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
      Column({ space: 4 }) {
        Text(name)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text(studentId)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12 })
      Column({ space: 4 }) {
        Text(className)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .textAlign(TextAlign.End)
        Text(collegeName)
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

/** 区块标题（自 HomeView 拆出） */
@Builder
export function HomeSectionTitle(title: string) {
  Text(title)
    .fontSize(16)
    .fontWeight(FontWeight.Bold)
    .fontColor($r('sys.color.ohos_id_color_text_primary'))
    .padding({ top: 16, bottom: 8 })
}

/** 今日课程单行（自 HomeView 拆出） */
@Builder
export function HomeTodayCourseRow(cell: ScheduleCellInfo) {
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

/** 今日课程卡（自 HomeView 拆出） */
@Builder
export function HomeTodayCard(todayCells: ScheduleCellInfo[]) {
  Column() {
    Row() {
      Text('今日课程')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Blank()
      Text('共' + todayCells.length + '门')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    if (todayCells.length === 0) {
      Text('今天没有课程安排')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ top: 16, bottom: 16 })
    } else {
      ForEach(todayCells, (cell: ScheduleCellInfo) => {
        HomeTodayCourseRow(cell)
      }, (cell: ScheduleCellInfo) => 'today' + cell.courseSerialNo + cell.dayOfWeek + cell.startSection)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 课表周切换片（自 HomeView 拆出；onSelect 切换周偏移） */
@Builder
export function HomeWeekChip(label: string, offset: number, selected: boolean, onSelect: () => void) {
  Text(label)
    .fontSize(11)
    .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
    .fontColor(selected ?
      Color.White : $r('sys.color.ohos_id_color_text_secondary'))
    .backgroundColor(selected ?
      $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_button_normal'))
    .borderRadius(10)
    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
    .margin({ left: 6 })
    .onClick(() => {
      onSelect();
    })
}

/** 倒计时徽标：未来为激活色底白字，当天为警示色，已结束为次要文字（自 HomeView 拆出） */
@Builder
export function HomeCountdownBadge(days: number) {
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

/** 期末倒计时单行（自 HomeView 拆出；colorHex 为课表课程色，days 为距考天数） */
@Builder
export function HomeFinalExamRow(entry: FinalExamEntry, colorHex: string, days: number) {
  Row() {
    if (colorHex.length > 0) {
      Column()
        .width(10)
        .height(10)
        .borderRadius(5)
        .backgroundColor(colorHex)
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

    HomeCountdownBadge(days)
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding({ top: 7, bottom: 7 })
}

/** 期末倒计时卡：显示已设定期末日期的科目及倒计时，未设定任何日期时不显示（自 HomeView 拆出） */
@Builder
export function HomeFinalExamCard(exams: FinalExamEntry[],
  colorOf: (courseName: string) => string, daysOf: (entry: FinalExamEntry) => number) {
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

    ForEach(exams, (entry: FinalExamEntry) => {
      HomeFinalExamRow(entry, colorOf(entry.courseName), daysOf(entry))
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
