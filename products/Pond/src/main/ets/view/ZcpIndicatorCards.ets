import { ZcpDetailItem, ZcpIndicator, ZcpResult } from '../model/ZcpModels';
import { STATUS_PASS_COLOR, ZcpCtxCard, ZcpRadarCard } from './ZcpCards';

/** 附加项行是否可展开明细（展示展开图标）（自 ZcpView 拆出） */
function isExpandable(item: ZcpIndicator): boolean {
  return item.category === '附加项';
}

/** 指标右侧数值标签（附加项显示已获得，评分/成绩分显示 得分/上限，一级显示占比）（自 ZcpView 拆出） */
function indicatorLabel(item: ZcpIndicator): string {
  if (item.category === '附加项') {
    return '已获得 ' + (item.extraGained.length > 0 ? item.extraGained : '0');
  }
  if (item.scoreText.length > 0) {
    const cap: string = item.capText.length > 0 ? item.capText : '-';
    return item.scoreText + ' / ' + cap;
  }
  if (item.fixedScore.length > 0) {
    return item.fixedScore + (item.capText.length > 0 ? ' / ' + item.capText : '');
  }
  if (item.level === 1 && item.ratioPercent.length > 0) {
    return '占比 ' + item.ratioPercent + '%';
  }
  if (item.capText.length > 0) {
    return '上限 ' + item.capText;
  }
  return '';
}

/** 指标数值文本颜色：有得分为激活色，附加项已获得为绿色（自 ZcpView 拆出） */
function indicatorValueColor(item: ZcpIndicator): ResourceColor {
  if (item.category === '附加项' && item.extraGained.length > 0) {
    return STATUS_PASS_COLOR;
  }
  if (item.scoreText.length > 0 || item.fixedScore.length > 0) {
    return $r('sys.color.ohos_id_color_text_primary');
  }
  return $r('sys.color.ohos_id_color_text_secondary');
}

/** 是否可画得分进度条：有数值得分且上限有效（附加项 999 为兜底值不作分母）（自 ZcpView 拆出） */
function hasScoreBar(item: ZcpIndicator): boolean {
  if (item.category === '附加项' || item.scoreText.length === 0) {
    return false;
  }
  const cap: number = Number.parseFloat(item.capText);
  if (Number.isNaN(cap) || cap <= 0 || cap === 999) {
    return false;
  }
  return true;
}

function scoreBarValue(item: ZcpIndicator): number {
  const value: number = Number.parseFloat(item.scoreText);
  return Number.isNaN(value) ? 0 : value;
}

function scoreBarTotal(item: ZcpIndicator): number {
  const total: number = Number.parseFloat(item.capText);
  return Number.isNaN(total) || total <= 0 ? 100 : total;
}

/** 行左侧展开箭头（展开时旋转 180°）（自 ZcpView 拆出） */
@Builder
function ZcpExpandChevron(detailZbdm: string, item: ZcpIndicator, size: number) {
  SymbolGlyph($r('sys.symbol.chevron_down'))
    .fontSize(size)
    .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
    .rotate({ angle: detailZbdm === item.zbdm ? 180 : 0 })
    .margin({ right: 4 })
}

/** 附加分明细展开区（挂在被点击的附加项行下方）（自 ZcpView 拆出） */
@Builder
function ZcpDetailArea(detailItems: ZcpDetailItem[], detailLoading: boolean) {
  Column({ space: 8 }) {
    if (detailLoading) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color($r('sys.color.ohos_id_color_text_secondary'))
        Text('正在加载附加分明细…')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .alignItems(VerticalAlign.Center)
    } else if (detailItems.length === 0) {
      Text('暂无附加分明细')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    } else {
      ForEach(detailItems, (detail: ZcpDetailItem) => {
        Column({ space: 3 }) {
          Row() {
            Text(detail.name)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(detail.score)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor(STATUS_PASS_COLOR)
              .margin({ left: 8 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Row({ space: 8 }) {
            if (detail.category.length > 0) {
              Text(detail.category)
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            }
            if (detail.status.length > 0) {
              Text(detail.status)
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            }
          }
          .width('100%')
          if (detail.note.length > 0) {
            Text(detail.note)
              .fontSize(11)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
          }
          if (detail.rule.length > 0) {
            Text(detail.rule)
              .fontSize(11)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(10)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
      }, (detail: ZcpDetailItem) => detail.name + detail.score + detail.status)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 26, right: 4, top: 4, bottom: 8 })
}

/** 三级指标行（挂在二级行下，缩进展示）（自 ZcpView 拆出；onToggle 点击展开/收起明细） */
@Builder
function ZcpLevel3Row(item: ZcpIndicator, detailZbdm: string, detailItems: ZcpDetailItem[],
  detailLoading: boolean, onToggle: (item: ZcpIndicator) => void) {
  Column() {
    Row() {
      if (isExpandable(item)) {
        ZcpExpandChevron(detailZbdm, item, 14)
      }
      Text(item.name)
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(indicatorLabel(item))
        .fontSize(13)
        .fontColor(indicatorValueColor(item))
        .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 6, bottom: 6 })
    if (hasScoreBar(item)) {
      Progress({ value: scoreBarValue(item), total: scoreBarTotal(item), type: ProgressType.Linear })
        .width('100%')
        .height(4)
        .color($r('sys.color.ohos_id_color_text_primary_activated'))
        .borderRadius(2)
        .padding({ bottom: 4 })
    }
    if (detailZbdm === item.zbdm) {
      ZcpDetailArea(detailItems, detailLoading)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 26 })
  .onClick(() => {
    onToggle(item);
  })
}

/** 二级指标行（附加项可点击展开明细）（自 ZcpView 拆出；onToggle 点击展开/收起明细） */
@Builder
function ZcpLevel2Row(item: ZcpIndicator, detailZbdm: string, detailItems: ZcpDetailItem[],
  detailLoading: boolean, onToggle: (item: ZcpIndicator) => void) {
  Column() {
    Row() {
      if (isExpandable(item)) {
        ZcpExpandChevron(detailZbdm, item, 16)
      }
      Column({ space: 2 }) {
        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.note.length > 0) {
          Text(item.note)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(indicatorLabel(item))
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(indicatorValueColor(item))
        .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 4 })
    if (hasScoreBar(item)) {
      Progress({ value: scoreBarValue(item), total: scoreBarTotal(item), type: ProgressType.Linear })
        .width('100%')
        .height(5)
        .color($r('sys.color.ohos_id_color_text_primary_activated'))
        .borderRadius(2.5)
    }
    ForEach(item.children, (child: ZcpIndicator) => {
      ZcpLevel3Row(child, detailZbdm, detailItems, detailLoading, onToggle)
    }, (child: ZcpIndicator) => child.zbdm + child.name + child.scoreText)
    if (detailZbdm === item.zbdm) {
      ZcpDetailArea(detailItems, detailLoading)
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 8 })
  .onClick(() => {
    onToggle(item);
  })
}

/** 一级指标卡片：指标名 + 占比 + 二级明细（自 ZcpView 拆出；onToggle 点击展开/收起明细） */
@Builder
export function ZcpIndicatorCard(root: ZcpIndicator, detailZbdm: string, detailItems: ZcpDetailItem[],
  detailLoading: boolean, onToggle: (item: ZcpIndicator) => void) {
  Column() {
    Row() {
      Text(root.name)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(indicatorLabel(root))
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ bottom: 4 })
    Divider()
      .color($r('sys.color.ohos_id_color_button_normal'))
      .strokeWidth(1)
      .margin({ bottom: 2 })
    ForEach(root.children, (child: ZcpIndicator) => {
      ZcpLevel2Row(child, detailZbdm, detailItems, detailLoading, onToggle)
    }, (child: ZcpIndicator) => child.zbdm + child.name + child.scoreText)
    if (root.children.length === 0) {
      Text('暂无子指标')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .padding({ top: 6, bottom: 6 })
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .margin({ top: 12 })
  .padding({ left: 16, right: 16, top: 12, bottom: 10 })
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .geometryTransition('zcp-ind-' + root.zbdm)
  .transition(TransitionEffect.OPACITY)
}

/**
 * 平板横屏双列布局：左列（批次上下文卡 + 雷达图）固定不随滚动，
 * 右列（一级指标明细卡）独立滚动；左右宽度比与首页横屏一致。
 * 离线横幅不在此处渲染，由外层内容顶部横跨双列全宽展示。
 * 双列行高按外层滚动视口与横幅块高精确计算，使外层 Scroll 恰好不滚（左列保持不动），
 * 内层滚动经 SELF_FIRST 延伸到外层，下拉刷新仍然可用。（自 ZcpView 拆出）
 */
@Builder
export function ZcpWideContent(result: ZcpResult, wideRowHeight: Length, bottomInset: number,
  detailZbdm: string, detailItems: ZcpDetailItem[], detailLoading: boolean,
  onToggle: (item: ZcpIndicator) => void) {
  Row() {
    Scroll() {
      Column() {
        ZcpCtxCard(result)
        ZcpRadarCard(result)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 16 })
    }
    .width(360)
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })

    Scroll() {
      Column() {
        ForEach(result.indicators, (root: ZcpIndicator) => {
          ZcpIndicatorCard(root, detailZbdm, detailItems, detailLoading, onToggle)
        }, (root: ZcpIndicator) => root.zbdm + root.name + root.scoreText)
        if (result.indicators.length === 0) {
          Text('暂无测评指标数据')
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .padding({ top: 16, bottom: 16 })
            .geometryTransition('zcp-empty')
            .transition(TransitionEffect.OPACITY)
        }
        Text('以上为当前批次数据，最终成绩以学校系统为准')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 12, bottom: 12 })
          .geometryTransition('zcp-footer')
          .transition(TransitionEffect.OPACITY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: bottomInset })
    }
    .layoutWeight(1)
    .height('100%')
    .align(Alignment.Top)
    .padding({ left: 16 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
  }
  .width('100%')
  .height(wideRowHeight)
  .alignItems(VerticalAlign.Top)
  .constraintSize({ maxWidth: 1200 })
  .alignSelf(ItemAlign.Center)
}
