import { GradeEntry } from '../model/JwModels';

/** 分组内容指纹：课程名+性质+考核+成绩拼接，内容变化时 ForEach key 变化以重建分组 */
export function gradeSectionFingerprint(items: GradeEntry[]): string {
  let fp: string = String(items.length);
  for (const grade of items) {
    fp += '|' + grade.courseName + grade.natureText + grade.examTypeText + grade.scoreView;
  }
  return fp;
}

/** 成绩数字色（优秀绿/良好蓝/中等橙/其他灰） */
export function gradeScoreColor(score: string): string {
  if (score === '优秀') {
    return '#2E7D32';
  }
  if (score === '良好') {
    return '#1565C0';
  }
  if (score === '中等') {
    return '#B26A00';
  }
  return '#616161';
}

export function gradeScoreBackground(score: string): string {
  if (score === '优秀') {
    return '#E8F5E9';
  }
  if (score === '良好') {
    return '#E3F2FD';
  }
  if (score === '中等') {
    return '#FFF3E0';
  }
  return '#EEEEEE';
}

/** 课程性质标签色（必修蓝/限选橙/选修及其他灰，兼容“必修课”等带后缀文案） */
export function gradeNatureTagColor(nature: string): string {
  if (nature.startsWith('必修')) {
    return '#1565C0';
  }
  if (nature.startsWith('限选')) {
    return '#B26A00';
  }
  return '#616161';
}

export function gradeNatureTagBackground(nature: string): string {
  if (nature.startsWith('必修')) {
    return '#E3F2FD';
  }
  if (nature.startsWith('限选')) {
    return '#FFF3E0';
  }
  return '#F5F5F5';
}

/** 考核方式标签色（考试绿/考查紫/其他灰） */
export function gradeExamTagColor(examType: string): string {
  if (examType === '考试') {
    return '#2E7D32';
  }
  if (examType === '考查') {
    return '#6A1B9A';
  }
  return '#616161';
}

export function gradeExamTagBackground(examType: string): string {
  if (examType === '考试') {
    return '#E8F5E9';
  }
  if (examType === '考查') {
    return '#F3E5F5';
  }
  return '#F5F5F5';
}

/** 汇总卡单元格（自 GradeView 拆出） */
@Builder
export function GradeSummaryCell(label: string, value: string) {
  Column({ space: 4 }) {
    Text(value)
      .fontSize(22)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
    Text(label)
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .layoutWeight(1)
  .alignItems(HorizontalAlign.Center)
}

/** 学分绩点汇总卡（自 GradeView 拆出） */
@Builder
export function GradeSummaryCard(gpaText: string, creditText: string, countText: string) {
  Row() {
    GradeSummaryCell('平均绩点', gpaText)
    Column()
      .width(1)
      .height(32)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    GradeSummaryCell('通过学分', creditText)
    Column()
      .width(1)
      .height(32)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    GradeSummaryCell('课程门数', countText)
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceEvenly)
  .alignItems(VerticalAlign.Center)
  .padding({ top: 16, bottom: 16 })
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .geometryTransition('grade-summary')
  .transition(TransitionEffect.OPACITY)
}

/** 培养计划入口（位于成绩汇总卡下方，自 GradeView 拆出） */
@Builder
export function GradeTrainingPlanEntry(onOpen: () => void) {
  Row({ space: 12 }) {
    Column({ space: 2 }) {
      Text('培养计划')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('方案内课程、学分与开课学期')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
  }
  .width('100%')
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .margin({ top: 12 })
  .geometryTransition('grade-plan')
  .transition(TransitionEffect.OPACITY)
  .onClick(() => {
    onOpen();
  })
}

/** 单条成绩行（自 GradeView 拆出） */
@Builder
export function GradeRow(grade: GradeEntry) {
  Row() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(grade.courseName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        if (grade.natureText.length > 0) {
          Text(grade.natureText)
            .fontSize(10)
            .fontColor(gradeNatureTagColor(grade.natureText))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(gradeNatureTagBackground(grade.natureText))
        }
        if (grade.examTypeText.length > 0) {
          Text(grade.examTypeText)
            .fontSize(10)
            .fontColor(gradeExamTagColor(grade.examTypeText))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(gradeExamTagBackground(grade.examTypeText))
        }
      }
      .width('100%')
      Text(grade.credit + '学分 · 绩点' + grade.gpaPoint)
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    Text(grade.scoreView)
      .fontSize(13)
      .fontWeight(FontWeight.Bold)
      .fontColor(gradeScoreColor(grade.scoreView))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(12)
      .backgroundColor(gradeScoreBackground(grade.scoreView))
      .margin({ left: 12 })
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceBetween)
  .alignItems(VerticalAlign.Center)
  .padding({ top: 10, bottom: 10 })
}

/** 分类成绩分组卡片（自 GradeView 拆出） */
@Builder
export function GradeSection(title: string, items: GradeEntry[]) {
  if (items.length > 0) {
    Column() {
      Row() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text(items.length + '门')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      .padding({ bottom: 4 })
      ForEach(items, (grade: GradeEntry) => {
        GradeRow(grade)
      }, (grade: GradeEntry) => grade.termCode + grade.courseName + grade.natureText + grade.examTypeText + grade.scoreView)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .geometryTransition('grade-sec-' + title)
    .transition(TransitionEffect.OPACITY)
  }
}

/** 离线数据提示条（自 GradeView 拆出；onHeight 回传实测组件高，onLogin 跳登录） */
@Builder
export function GradeOfflineBanner(onHeight: (vp: number) => void, onLogin: () => void) {
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
  .geometryTransition('grade-banner')
  .transition(TransitionEffect.OPACITY)
  .onAreaChange((oldArea: Area, newArea: Area) => {
    onHeight(typeof newArea.height === 'number' ? newArea.height : 0);
  })
  .onClick(() => {
    onLogin();
  })
}

/** 学期筛选行（自 GradeView 拆出；onSelect 回传选中的学期索引） */
@Builder
export function GradeTermFilterRow(options: SelectOption[], selectedIndex: number,
  selectedLabel: string, onSelect: (index: number) => void) {
  Row({ space: 10 }) {
    Text('学期')
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    Select(options)
      .selected(selectedIndex)
      .value(selectedLabel)
      .font({ size: 13 })
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .optionFont({ size: 13 })
      .optionFontColor($r('sys.color.ohos_id_color_text_primary'))
      .selectedOptionFontColor($r('sys.color.ohos_id_color_text_primary_activated'))
      .selectedOptionBgColor($r('sys.color.ohos_id_color_button_normal'))
      .optionWidth(232)
      .onSelect((index: number) => {
        onSelect(index);
      })
  }
  .width('100%')
  .margin({ top: 16, bottom: 4 })
  .alignItems(VerticalAlign.Center)
  .geometryTransition('grade-term')
  .transition(TransitionEffect.OPACITY)
}

/** 无成绩空态提示（自 GradeView 拆出） */
@Builder
export function GradeEmptyText(mode: string) {
  Text(mode === 'online' ? '暂无成绩数据' :
    (mode === 'offlineCache' ? '暂无缓存成绩' : '登录教务系统后可查看成绩'))
    .fontSize(12)
    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    .padding({ top: 24, bottom: 24 })
    .geometryTransition('grade-empty')
    .transition(TransitionEffect.OPACITY)
}
