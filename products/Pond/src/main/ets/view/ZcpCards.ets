import { ZcpResult } from '../model/ZcpModels';
import { ZcpRadarChart, RadarEntry } from './ZcpRadarChart';
import { NEUTRAL_BG, PASS_BG, PASS_TEXT, REJECT_BG, REJECT_TEXT, REVIEW_BG, REVIEW_TEXT } from '../theme/AppColors';

/** 去掉 Error 字符串的 'Error: ' 前缀，便于直接展示（自 ZcpView 拆出） */
export function plainError(text: string): string {
  return text.startsWith('Error: ') ? text.substring(7) : text;
}

/** 测评状态文本颜色（自 ZcpView 拆出） */
function statusTextColor(result: ZcpResult): ResourceColor {
  const state: number = result.process.state;
  const text: string = result.process.statusText;
  if (state === 4 || text.indexOf('通过') >= 0) {
    return PASS_TEXT;
  }
  if (state === 3 || text.indexOf('退回') >= 0) {
    return REJECT_TEXT;
  }
  if (state === 2 || text.indexOf('审核') >= 0) {
    return REVIEW_TEXT;
  }
  return $r('sys.color.ohos_id_color_text_secondary');
}

/** 测评状态背景色（自 ZcpView 拆出） */
function statusBgColor(result: ZcpResult): string {
  const state: number = result.process.state;
  const text: string = result.process.statusText;
  if (state === 4 || text.indexOf('通过') >= 0) {
    return PASS_BG;
  }
  if (state === 3 || text.indexOf('退回') >= 0) {
    return REJECT_BG;
  }
  if (state === 2 || text.indexOf('审核') >= 0) {
    return REVIEW_BG;
  }
  return NEUTRAL_BG;
}

/** 多维图数据：二级素质维度中得分与满分均可解析的条目（附加项 999 兜底上限排除）。
 * 一级「综合素质」为计算项无得分，雷达轴取其下二级指标（get23zbScore 回填源，实测 8 项）。（自 ZcpView 拆出） */
function radarEntries(result: ZcpResult): RadarEntry[] {
  const list: RadarEntry[] = [];
  for (const root of result.indicators) {
    for (const item of root.children) {
      if (item.category === '附加项') {
        continue;
      }
      const scoreSource: string = item.scoreText.length > 0 ? item.scoreText : item.fixedScore;
      if (scoreSource.length === 0) {
        continue;
      }
      const score: number = Number.parseFloat(scoreSource);
      const cap: number = Number.parseFloat(item.capText);
      if (Number.isNaN(score) || Number.isNaN(cap) || cap <= 0 || cap === 999) {
        continue;
      }
      const entry: RadarEntry = new RadarEntry();
      entry.name = item.name;
      entry.scoreText = `${score}`;
      entry.capText = `${cap}`;
      const ratio: number = score / cap;
      entry.value = ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
      list.push(entry);
    }
  }
  return list;
}

/** 加载中卡片（自 ZcpView 拆出） */
@Builder
export function ZcpLoadingCard(text: string) {
  Column({ space: 12 }) {
    LoadingProgress()
      .width(36)
      .height(36)
      .color($r('sys.color.ohos_id_color_text_primary_activated'))
    Text(text)
      .fontSize(14)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
  }
  .width('100%')
  .padding({ top: 48, bottom: 48 })
  .alignItems(HorizontalAlign.Center)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 失败卡片（自 ZcpView 拆出；onRetry 重新获取） */
@Builder
export function ZcpErrorCard(errorText: string, onRetry: () => void) {
  Column({ space: 12 }) {
    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
      .fontSize(36)
      .fontColor([$r('sys.color.ohos_id_color_warning')])
    Text(errorText)
      .fontSize(14)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .textAlign(TextAlign.Center)
    Text('重新获取')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .borderRadius(20)
      .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
      .onClick(() => {
        onRetry();
      })
  }
  .width('100%')
  .padding({ left: 16, right: 16, top: 36, bottom: 36 })
  .alignItems(HorizontalAlign.Center)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 未加载卡片（自 ZcpView 拆出；onRetry 获取综评成绩） */
@Builder
export function ZcpIdleCard(onRetry: () => void) {
  Column({ space: 12 }) {
    Text('综评数据未加载')
      .fontSize(15)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    Text('获取综评成绩')
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(Color.White)
      .padding({ left: 24, right: 24, top: 10, bottom: 10 })
      .borderRadius(20)
      .backgroundColor($r('sys.color.ohos_id_color_text_primary_activated'))
      .onClick(() => {
        onRetry();
      })
  }
  .width('100%')
  .padding({ top: 36, bottom: 36 })
  .alignItems(HorizontalAlign.Center)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 上下文信息行（label 值为空时不渲染在调用处保证）（自 ZcpView 拆出） */
@Builder
function ZcpCtxRow(label: string, value: string) {
  Row() {
    Text(label)
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    Blank()
    Text(value)
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: '68%' })
  }
  .width('100%')
  .padding({ top: 6, bottom: 6 })
}

/** 批次上下文卡（自 ZcpView 拆出） */
@Builder
export function ZcpCtxCard(result: ZcpResult) {
  Column() {
    Row({ space: 8 }) {
      Text(result.context.batchName.length > 0 ? result.context.batchName : '当前批次')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(result.process.statusDisplay())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(statusTextColor(result))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(statusBgColor(result))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    if (result.context.termDisplay.length > 0) {
      ZcpCtxRow('学年学期', result.context.termDisplay)
    }
    if (result.context.targetName.length > 0) {
      ZcpCtxRow('参评对象', result.context.targetName)
    }
    if (result.context.fillWindow.length > 0) {
      ZcpCtxRow('填写时间', result.context.fillWindow)
    }
    if (result.context.auditWindow.length > 0) {
      ZcpCtxRow('审核时间', result.context.auditWindow)
    }
    if (result.process.state === 3 && result.process.rejectReason.length > 0) {
      Text('退回原因：' + result.process.rejectReason)
        .fontSize(13)
        .fontColor(REJECT_TEXT)
        .width('100%')
        .padding({ top: 6, bottom: 6 })
    }
    if (!result.context.windowOpen) {
      Text('测评填写时间已关闭，以下为当前批次归档数据，仅供参考')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
        .padding({ top: 4 })
    }
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
  .geometryTransition('zcp-ctx')
  .transition(TransitionEffect.OPACITY)
}

/** 素质得分多维图卡片：有效维度 ≥3 时展示雷达图（自 ZcpView 拆出） */
@Builder
export function ZcpRadarCard(result: ZcpResult) {
  if (radarEntries(result).length >= 3) {
    Column() {
      Text('素质得分多维图')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
        .padding({ bottom: 4 })
      ZcpRadarChart({ entries: radarEntries(result) })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .geometryTransition('zcp-radar')
    .transition(TransitionEffect.OPACITY)
  }
}

/** 离线数据提示条：当前展示本地缓存数据时置顶提示，点击重试在线刷新（自 ZcpView 拆出；
 *  onGoLogin 去登录，onRetry 重试，onBannerHeight 实测横幅高度回写） */
@Builder
export function ZcpOfflineBanner(dataMode: string, onGoLogin: () => void, onRetry: () => void,
  onBannerHeight: (heightVp: number) => void) {
  Row({ space: 10 }) {
    SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
      .fontSize(20)
      .fontColor([$r('sys.color.ohos_id_color_warning')])
    Column({ space: 2 }) {
      Text('正在使用离线数据')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text(dataMode === 'offlineCache' ?
        '当前展示本地缓存，重新登录后自动更新' :
        '当前展示本地缓存，联网刷新成功后自动更新')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    Text(dataMode === 'offlineCache' ? '去登录' : '重试')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  .borderRadius(12)
  .backgroundColor($r('sys.color.comp_background_tertiary'))
  .margin({ bottom: 10 })
  .geometryTransition('zcp-banner')
  .transition(TransitionEffect.OPACITY)
  .onAreaChange((oldArea: Area, newArea: Area) => {
    onBannerHeight(typeof newArea.height === 'number' ? newArea.height : 0);
  })
  .onClick(() => {
    if (dataMode === 'offlineCache') {
      onGoLogin();
    } else {
      onRetry();
    }
  })
}
