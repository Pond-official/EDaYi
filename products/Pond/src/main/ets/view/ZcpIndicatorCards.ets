import { ZcpDetailItem, ZcpIndicator } from '../model/ZcpModels';
import { ZcpRepository } from '../data/ZcpRepository';
import { PASS_TEXT } from '../theme/AppColors';
import { cardEnterEffect } from './CardEnter';

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
    return PASS_TEXT;
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

/** 已展开的附加分明细条目（卡片内部状态；数组条目按 zbdm 增删实现多明细同时展开互不挤占） */
class ZcpOpenDetail {
  /** 展开明细的指标代码 */
  zbdm: string = '';
  /** 明细条目（加载完成前为空） */
  items: ZcpDetailItem[] = [];
  /** 明细加载中 */
  loading: boolean = false;
}

/**
 * 一级指标卡片：指标名 + 占比 + 二级明细（自 ZcpView 拆出，原全局 @Builder 组件化）。
 * 附加项明细展开状态与获取（getZbFjfDetail，仅读接口）收敛在卡片内部：
 * @State openDetails 数组按 zbdm 记录展开项，多个附加项明细可同时展开互不挤占；
 * 收起仅由附加项行头再次点击触发（明细区内点击不冒泡收起），
 * 明细区内单条加分项可点按展开其说明/计分说明（默认收起）；
 * 调用方 ForEach key 只含指标数据（不并入明细状态），避免卡片重挂载导致渐入动画重复播放。
 */
@Component
export struct ZcpIndicatorCard {
  /** 一级指标根节点（调用方 ForEach 数据源元素，key 变化时整体重建） */
  root: ZcpIndicator = new ZcpIndicator();
  /** 已展开的明细条目（zbdm 唯一，点击展开/收起增删） */
  @State openDetails: ZcpOpenDetail[] = [];
  /** 已展开说明的单条加分项（key = 父 zbdm + ':' + 条目下标，点按条目增删） */
  @State expandedEntries: string[] = [];

  /** 明细条目在 openDetails 中的下标（-1 = 未展开） */
  private indexOfDetail(zbdm: string): number {
    for (let i: number = 0; i < this.openDetails.length; i++) {
      if (this.openDetails[i].zbdm === zbdm) {
        return i;
      }
    }
    return -1;
  }

  /** 该指标的明细是否已展开 */
  private isDetailOpen(zbdm: string): boolean {
    return this.indexOfDetail(zbdm) >= 0;
  }

  /** 该指标的明细是否加载中 */
  private isDetailLoading(zbdm: string): boolean {
    const index: number = this.indexOfDetail(zbdm);
    return index >= 0 && this.openDetails[index].loading;
  }

  /** 该指标的明细条目（未展开或加载中为空数组） */
  private detailItemsOf(zbdm: string): ZcpDetailItem[] {
    const index: number = this.indexOfDetail(zbdm);
    return index >= 0 ? this.openDetails[index].items : [];
  }

  /** 附加项指标点击行头展开/收起明细：展开项记入 openDetails 并异步获取，再次点击行头移除收起 */
  private async toggleDetail(item: ZcpIndicator): Promise<void> {
    if (item.category !== '附加项') { return; }
    const index: number = this.indexOfDetail(item.zbdm);
    if (index >= 0) {
      this.openDetails.splice(index, 1);
      this.collapseEntriesOf(item.zbdm);
      return;
    }
    const open: ZcpOpenDetail = new ZcpOpenDetail();
    open.zbdm = item.zbdm;
    open.loading = true;
    this.openDetails.push(open);
    try {
      const items: ZcpDetailItem[] = await ZcpRepository.fetchDetail(item.zbdm);
      this.finishDetail(item.zbdm, items);
    } catch (error) {
      // 明细加载失败按空明细展示，不中断页面
      this.finishDetail(item.zbdm, []);
    }
  }

  /** 明细获取完成：替换展开条目；加载期间已收起（或卡片重建）则丢弃 */
  private finishDetail(zbdm: string, items: ZcpDetailItem[]): void {
    const index: number = this.indexOfDetail(zbdm);
    if (index < 0) { return; }
    const done: ZcpOpenDetail = new ZcpOpenDetail();
    done.zbdm = zbdm;
    done.items = items;
    this.openDetails.splice(index, 1, done);
  }

  /** 单条加分项是否带说明/计分说明（有点按展开价值） */
  private hasEntryDetail(detail: ZcpDetailItem): boolean {
    return detail.note.length > 0 || detail.rule.length > 0;
  }

  /** 单条加分项展开状态 key（父明细 zbdm + 条目下标） */
  private entryKey(zbdm: string, index: number): string {
    return zbdm + ':' + index;
  }

  /** 单条加分项的说明是否已展开 */
  private isEntryExpanded(zbdm: string, index: number): boolean {
    return this.expandedEntries.indexOf(this.entryKey(zbdm, index)) >= 0;
  }

  /** 点按单条加分项：展开/收起该条目的说明与计分说明 */
  private toggleEntry(zbdm: string, index: number): void {
    const key: string = this.entryKey(zbdm, index);
    const pos: number = this.expandedEntries.indexOf(key);
    if (pos >= 0) {
      this.expandedEntries.splice(pos, 1);
    } else {
      this.expandedEntries.push(key);
    }
  }

  /** 父明细收起时清掉其下条目的展开状态（避免下次展开残留错位） */
  private collapseEntriesOf(zbdm: string): void {
    const prefix: string = zbdm + ':';
    for (let i: number = this.expandedEntries.length - 1; i >= 0; i--) {
      if (this.expandedEntries[i].startsWith(prefix)) {
        this.expandedEntries.splice(i, 1);
      }
    }
  }

  /** 行左侧展开箭头（展开时旋转 180°） */
  @Builder
  expandChevron(item: ZcpIndicator, size: number) {
    SymbolGlyph($r('sys.symbol.chevron_down'))
      .fontSize(size)
      .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      .rotate({ angle: this.isDetailOpen(item.zbdm) ? 180 : 0 })
      .margin({ right: 4 })
  }

  /** 单条加分项行左侧展开箭头（展开时旋转 180°；仅有说明/计分说明的条目显示） */
  @Builder
  entryChevron(zbdm: string, index: number) {
    SymbolGlyph($r('sys.symbol.chevron_down'))
      .fontSize(12)
      .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      .rotate({ angle: this.isEntryExpanded(zbdm, index) ? 180 : 0 })
      .margin({ right: 4 })
  }

  /** 附加分明细展开区（挂在被点击的附加项行下方） */
  @Builder
  detailArea(zbdm: string) {
    Column({ space: 8 }) {
      if (this.isDetailLoading(zbdm)) {
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
      } else if (this.detailItemsOf(zbdm).length === 0) {
        Text('暂无附加分明细')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.detailItemsOf(zbdm), (detail: ZcpDetailItem, index: number) => {
          Column({ space: 3 }) {
            Row() {
              if (this.hasEntryDetail(detail)) {
                this.entryChevron(zbdm, index)
              }
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
                .fontColor(PASS_TEXT)
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
            if (this.isEntryExpanded(zbdm, index)) {
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
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(10)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .onClick(() => {
            if (this.hasEntryDetail(detail)) {
              this.toggleEntry(zbdm, index);
            }
          })
        }, (detail: ZcpDetailItem, index: number) => detail.name + detail.score + detail.status + index)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 26, right: 4, top: 4, bottom: 8 })
  }

  /** 三级指标行（挂在二级行下，缩进展示；点击行头展开/收起明细，明细区内点击不触发） */
  @Builder
  level3Row(item: ZcpIndicator) {
    Column() {
      Row() {
        if (isExpandable(item)) {
          this.expandChevron(item, 14)
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
      .onClick(() => {
        this.toggleDetail(item);
      })
      if (hasScoreBar(item)) {
        Progress({ value: scoreBarValue(item), total: scoreBarTotal(item), type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color($r('sys.color.ohos_id_color_text_primary_activated'))
          .borderRadius(2)
          .padding({ bottom: 4 })
      }
      if (this.isDetailOpen(item.zbdm)) {
        this.detailArea(item.zbdm)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 26 })
  }

  /** 二级指标行（附加项行头可点击展开明细） */
  @Builder
  level2Row(item: ZcpIndicator) {
    Column() {
      Row() {
        if (isExpandable(item)) {
          this.expandChevron(item, 16)
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
      .onClick(() => {
        this.toggleDetail(item);
      })
      if (hasScoreBar(item)) {
        Progress({ value: scoreBarValue(item), total: scoreBarTotal(item), type: ProgressType.Linear })
          .width('100%')
          .height(5)
          .color($r('sys.color.ohos_id_color_text_primary_activated'))
          .borderRadius(2.5)
      }
      ForEach(item.children, (child: ZcpIndicator) => {
        this.level3Row(child)
      }, (child: ZcpIndicator) => child.zbdm + child.name + child.scoreText)
      if (this.isDetailOpen(item.zbdm)) {
        this.detailArea(item.zbdm)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8 })
  }

  build() {
    Column() {
      Row() {
        Text(this.root.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(indicatorLabel(this.root))
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
      ForEach(this.root.children, (child: ZcpIndicator) => {
        this.level2Row(child)
      }, (child: ZcpIndicator) => child.zbdm + child.name + child.scoreText)
      if (this.root.children.length === 0) {
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
    .geometryTransition('zcp-ind-' + this.root.zbdm)
    .transition(cardEnterEffect(180))
  }
}
