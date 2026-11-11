import { SelectionBatch, SelectedCourse, SelectionCourse } from '../model/SelectionModels';

/** 轮次未开始状态色 */
const PENDING_COLOR: string = '#E88A00';

/** 去掉 Error 字符串的 'Error: ' 前缀，便于直接展示（自 SelectionView 拆出） */
export function plainError(text: string): string {
  return text.startsWith('Error: ') ? text.substring(7) : text;
}

/** 顶栏登录摘要（自 SelectionView 拆出） */
export function loginSummaryText(studentName: string, selectedCount: number): string {
  return studentName + ' · 已选 ' + `${selectedCount}` + ' 门';
}

/** 课程总数文案（自 SelectionView 拆出） */
export function totalCourseText(totalCourses: number): string {
  return '共 ' + `${totalCourses}` + ' 门课程';
}

/** 当前选中轮次的时间窗文本（自 SelectionView 拆出） */
function batchTimeText(batches: SelectionBatch[], currentIndex: number): string {
  const batch: SelectionBatch | undefined = batches[currentIndex];
  if (batch === undefined) {
    return '';
  }
  return batch.beginTime + ' ~ ' + batch.endTime;
}

/** 轮次选课时间状态：未开放/未开始/进行中/已结束/可选（自 SelectionView 拆出） */
export function batchStatus(batch: SelectionBatch): string {
  if (batch.canSelect !== '1') {
    return '未开放';
  }
  const begin: number = parseTime(batch.beginTime);
  const end: number = parseTime(batch.endTime);
  const now: number = Date.now();
  if (begin > 0 && now < begin) {
    return '未开始';
  }
  if (end > 0 && now > end) {
    return '已结束';
  }
  if (begin > 0 && end > 0) {
    return '进行中';
  }
  return '可选';
}

/** 宽容解析 'YYYY-MM-DD HH:mm:ss' 等数字时间文本，失败返回 0（自 SelectionView 拆出） */
function parseTime(text: string): number {
  if (text.length < 8) {
    return 0;
  }
  const parts: string[] = text.split(/[^0-9]+/);
  const nums: number[] = [];
  for (const part of parts) {
    if (part.length > 0) {
      nums.push(Number.parseInt(part));
    }
  }
  if (nums.length < 3) {
    return 0;
  }
  const hour: number = nums.length > 3 ? nums[3] : 0;
  const minute: number = nums.length > 4 ? nums[4] : 0;
  const date: Date = new Date(nums[0], nums[1] - 1, nums[2], hour, minute);
  const time: number = date.getTime();
  return Number.isNaN(time) ? 0 : time;
}

/** 轮次状态色（自 SelectionView 拆出） */
function statusColor(status: string): ResourceColor {
  if (status === '进行中' || status === '可选') {
    return $r('sys.color.ohos_id_color_text_primary_activated');
  }
  if (status === '未开始') {
    return PENDING_COLOR;
  }
  return $r('sys.color.ohos_id_color_text_secondary');
}

/** 课程副文本（教师 · 时间，自 SelectionView 拆出） */
function courseSubText(course: SelectionCourse): string {
  const teacher: string = course.teacher.length > 0 ? course.teacher : '教师待定';
  if (course.timeText.length > 0) {
    return teacher + ' · ' + course.timeText;
  }
  return teacher;
}

/** 课程已选人数文案（自 SelectionView 拆出） */
function courseCountText(course: SelectionCourse): string {
  return '已选 ' + `${course.selectedCount}` + '/' + `${course.capacity}`;
}

/** 已选课程状态文案（自 SelectionView 拆出） */
function selectedStatusText(item: SelectedCourse): string {
  return item.selectStatus === 99 ? '正常' : '状态 ' + `${item.selectStatus}`;
}

/** 已选课程副文本（教师 · 学分，自 SelectionView 拆出） */
function selectedSubText(item: SelectedCourse): string {
  const credit: string = item.credit.length > 0 ? ' · ' + item.credit + '学分' : '';
  return item.teacher + credit;
}

/** 提示条（自 SelectionView 拆出） */
@Builder
export function SelectionTipCard(tipText: string) {
  Row({ space: 8 }) {
    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
      .fontSize(18)
      .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
    Text(tipText)
      .fontSize(12)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .layoutWeight(1)
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding(12)
  .borderRadius(12)
  .backgroundColor($r('app.color.card_background'))
}

/** 顶栏卡（自 SelectionView 拆出；onRefresh 刷新数据，onLogout 退出登录） */
@Builder
export function SelectionHeaderCard(summaryText: string, onRefresh: () => void, onLogout: () => void) {
  Row({ space: 8 }) {
    Column({ space: 2 }) {
      Text('选课系统')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text(summaryText)
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    Button('刷新')
      .fontSize(13)
      .height(34)
      .onClick(() => {
        onRefresh();
      })
    Button('退出')
      .fontSize(13)
      .height(34)
      .onClick(() => {
        onLogout();
      })
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding(12)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 轮次切换片（自 SelectionView 拆出；onSelect 切换当前轮次） */
@Builder
function SelectionBatchChip(batch: SelectionBatch, selected: boolean, onSelect: () => void) {
  Text(batch.name.length > 0 ? batch.name : '轮次')
    .fontSize(13)
    .fontColor(selected ? Color.White : $r('sys.color.ohos_id_color_text_primary'))
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .constraintSize({ maxWidth: 220 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(selected
      ? $r('sys.color.ohos_id_color_text_primary_activated')
      : $r('app.color.card_background'))
    .onClick(() => {
      onSelect();
    })
}

/** 轮次区（自 SelectionView 拆出；onSelect 切换当前轮次） */
@Builder
export function SelectionBatchSection(batches: SelectionBatch[], currentIndex: number,
  onSelect: (index: number) => void) {
  Column({ space: 10 }) {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(batches, (batch: SelectionBatch, index: number) => {
          SelectionBatchChip(batch, index === currentIndex, (): void => {
            onSelect(index);
          })
        }, (batch: SelectionBatch) => batch.code)
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    if (batches.length > 0) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(batches[currentIndex].name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(batchStatus(batches[currentIndex]))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(statusColor(batchStatus(batches[currentIndex])))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        Text('选课时间：' + batchTimeText(batches, currentIndex))
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        if (batches[currentIndex].typeName.length > 0
          || batches[currentIndex].tacticName.length > 0) {
          Text(batches[currentIndex].typeName
            + (batches[currentIndex].tacticName.length > 0
              ? ' · ' + batches[currentIndex].tacticName
              : ''))
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        if (batches[currentIndex].weekRange.length > 0) {
          Text('上课周次：' + batches[currentIndex].weekRange)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
}

/** 已选课程卡（自 SelectionView 拆出） */
@Builder
export function SelectionSelectedCard(selectedCourses: SelectedCourse[]) {
  Column({ space: 8 }) {
    Row({ space: 8 }) {
      Text('已选课程')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
      Text(`${selectedCourses.length}` + ' 门')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    if (selectedCourses.length === 0) {
      Text('暂无已选课程，选课提交后在此显示，可下拉刷新查看最新结果。')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    } else {
      ForEach(selectedCourses, (item: SelectedCourse) => {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(item.courseName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(selectedSubText(item))
              .fontSize(11)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(selectedStatusText(item))
            .fontSize(11)
            .fontColor(item.selectStatus === 99
              ? $r('sys.color.ohos_id_color_text_primary_activated')
              : $r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (item: SelectedCourse) => item.jxbId)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(12)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 搜索行（自 SelectionView 拆出；onKeywordChange 同步关键词，onSearch 触发搜索） */
@Builder
export function SelectionSearchRow(keyword: string, searchEnabled: boolean,
  onKeywordChange: (value: string) => void, onSearch: () => void) {
  Row({ space: 8 }) {
    TextInput({ placeholder: '搜索课程名或教师', text: keyword })
      .fontSize(13)
      .height(40)
      .layoutWeight(1)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .borderRadius(20)
      .onChange((value: string) => {
        onKeywordChange(value);
      })
    Button('搜索')
      .fontSize(13)
      .height(40)
      .enabled(searchEnabled)
      .onClick(() => {
        onSearch();
      })
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
}

/** 课程卡（自 SelectionView 拆出；onConfirm 提交选课） */
@Builder
export function SelectionCourseCard(course: SelectionCourse, actionLabel: string,
  actionEnabled: boolean, onConfirm: () => void) {
  Column({ space: 8 }) {
    Row() {
      Text(course.courseName)
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
    Text(courseSubText(course))
      .fontSize(12)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
    Row() {
      Text(courseCountText(course))
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .layoutWeight(1)
      Button(actionLabel)
        .fontSize(13)
        .height(32)
        .padding({ left: 16, right: 16 })
        .enabled(actionEnabled)
        .onClick(() => {
          onConfirm();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(14)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 课程加载中卡（自 SelectionView 拆出） */
@Builder
export function SelectionCoursesLoadingCard() {
  Column({ space: 10 }) {
    LoadingProgress()
      .width(28)
      .height(28)
    Text('正在加载课程…')
      .fontSize(12)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .width('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ top: 28, bottom: 28 })
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 课程空态卡（自 SelectionView 拆出；hasKeyword 区分「未找到」与「暂无」） */
@Builder
export function SelectionCoursesEmptyCard(hasKeyword: boolean) {
  Column({ space: 8 }) {
    SymbolGlyph($r('sys.symbol.list_bullet'))
      .fontSize(36)
      .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
    Text(hasKeyword ? '未找到相关课程' : '暂无可选课程')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
    Text('换个关键词试试，或点击右上角刷新。')
      .fontSize(12)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .width('100%')
  .justifyContent(FlexAlign.Center)
  .alignItems(HorizontalAlign.Center)
  .padding({ top: 28, bottom: 28, left: 24, right: 24 })
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 加载更多行（自 SelectionView 拆出；onLoadMore 加载下一页） */
@Builder
export function SelectionLoadMoreRow(moreLoading: boolean, hasMore: boolean, onLoadMore: () => void) {
  Column() {
    if (moreLoading) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(20)
          .height(20)
        Text('正在加载…')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .alignItems(VerticalAlign.Center)
    } else if (hasMore) {
      Button('加载更多')
        .fontSize(13)
        .height(36)
        .onClick(() => {
          onLoadMore();
        })
    } else {
      Text('没有更多了')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Center)
  .margin({ top: 4 })
}
