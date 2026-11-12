import { ExamDateUtils } from '../utils/ExamDateUtils';

/** 期末倒计时设置行：本学期培养计划考试课（或已设置但计划外的课程）与其已设考试时间 */
export class ExamCourseItem {
  courseName: string = '';
  /** 课程副标题（培养计划课程为"学分 · 性质"，计划外课程为来源说明） */
  subtitle: string = '';
  /** 已设考试时间（'YYYY-MM-DD HH:mm'，未设置为空） */
  examDate: string = '';
}

/** 考试行倒计时副文本：不足一天显示小时，已到点显示"已结束"，时间非法显示"时间无效" */
function examCountdownOf(item: ExamCourseItem): string {
  const parsed: Date | null = ExamDateUtils.parseExamDate(item.examDate);
  if (parsed === null) {
    return '时间无效';
  }
  return ExamDateUtils.countdownTextOf(parsed);
}

/** 期末倒计时入口（onEnter 进入期末倒计时二级页） */
@Builder
export function SettingsExamEntry(onEnter: () => void) {
  Row({ space: 12 }) {
    Column({ space: 2 }) {
      Text('期末倒计时')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text('设置各科目考试时间，精确到分钟')
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
  .margin({ top: 16 })
  .onClick(() => {
    onEnter();
  })
}

/** 添加科目入口（onAdd 打开候选列表弹层，科目来自培养计划非考试课） */
@Builder
export function SettingsExamAddEntry(onAdd: () => void) {
  Row({ space: 8 }) {
    SymbolGlyph($r('sys.symbol.plus'))
      .fontSize(16)
      .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
    Text('添加科目')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
    Blank()
    Text('考查课等非考试科目')
      .fontSize(11)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .width('100%')
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .margin({ top: 12 })
  .onClick(() => {
    onAdd();
  })
}

/** 添加科目候选项（本学期培养计划中考核方式非"考试"的课程） */
export class ExamAddCandidate {
  courseName: string = '';
  /** 课程副标题（"学分 · 性质 · 考核方式"） */
  subtitle: string = '';
}

/** 添加科目候选列表入参（单参对象字面量按引用传递） */
export interface SettingsExamAddListParams {
  candidates: ExamAddCandidate[];
  /** 空态文案（由 SettingsView 按数据来源区分） */
  emptyText: string;
  onPick: (candidate: ExamAddCandidate) => void;
}

/** 添加科目候选列表：点击科目后进入日期+时间选择器 */
@Builder
export function SettingsExamAddList(params: SettingsExamAddListParams) {
  Column() {
    if (params.candidates.length === 0) {
      Text(params.emptyText)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .padding({ top: 12, bottom: 12 })
    } else {
      ForEach(params.candidates, (candidate: ExamAddCandidate, index: number) => {
        if (index > 0) {
          Divider()
            .color($r('sys.color.ohos_id_color_list_separator'))
        }
        Row() {
          Column({ space: 2 }) {
            Text(candidate.courseName)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (candidate.subtitle.length > 0) {
              Text(candidate.subtitle)
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 10, bottom: 10 })
        .onClick(() => {
          params.onPick(candidate);
        })
      }, (candidate: ExamAddCandidate) => 'examAdd' + candidate.courseName)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
}

/** 考试课列表卡入参（单参对象字面量按引用传递，设置时间后随状态刷新） */
export interface SettingsExamListParams {
  items: ExamCourseItem[];
  /** 空态文案（由 SettingsView 按数据来源区分：未同步培养计划/无法确定学期/无考试课） */
  emptyText: string;
  onPick: (item: ExamCourseItem) => void;
  onClear: (item: ExamCourseItem) => void;
}

/** 期末倒计时单行：课程名 + 副标题，右侧已设时间与倒计时（含"清除"）或"设置"入口 */
@Builder
function examCourseRow(params: SettingsExamListParams, item: ExamCourseItem) {
  Row() {
    Column({ space: 2 }) {
      Text(item.courseName)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (item.subtitle.length > 0) {
        Text(item.subtitle)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)

    if (item.examDate.length > 0) {
      Column({ space: 2 }) {
        Text(ExamDateUtils.formatDisplay(item.examDate))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text(examCountdownOf(item))
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
      }
      .alignItems(HorizontalAlign.End)
      Text('清除')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ left: 10 })
        .onClick(() => {
          params.onClear(item);
        })
    } else {
      Text('设置')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(14)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
    }
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding({ top: 10, bottom: 10 })
  .onClick(() => {
    params.onPick(item);
  })
}

/** 考试课列表卡：本学期培养计划考试课 + 计划外已设课程，点击设置考试日期与时间 */
@Builder
export function SettingsExamListCard(params: SettingsExamListParams) {
  Column() {
    if (params.items.length === 0) {
      Text(params.emptyText)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .padding({ top: 12, bottom: 12 })
    } else {
      ForEach(params.items, (item: ExamCourseItem, index: number) => {
        if (index > 0) {
          Divider()
            .color($r('sys.color.ohos_id_color_list_separator'))
        }
        examCourseRow(params, item)
      }, (item: ExamCourseItem) => 'examCourse' + item.courseName + ':' + item.examDate)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}
