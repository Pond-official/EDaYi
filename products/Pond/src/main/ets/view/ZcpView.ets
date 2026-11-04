import { webview } from '@kit.ArkWeb';
import { ZcpDetailItem, ZcpIndicator, ZcpResult } from '../model/ZcpModels';
import { ZcpRepository, ZCP_SESSION_INVALID_ERROR } from '../data/ZcpRepository';
import { FrostBand, FROST_BAND_HEIGHT } from './FrostBand';
import { ZcpRadarChart, RadarEntry } from './ZcpRadarChart';

/** 状态色（测评状态机：已通过/已退回/审核中/其他） */
const STATUS_PASS_COLOR: string = '#0FA958';
const STATUS_REJECT_COLOR: string = '#E84026';
const STATUS_REVIEW_COLOR: string = '#E88A00';
const STATUS_PASS_BG: string = '#E8F5E9';
const STATUS_REJECT_BG: string = '#FDECEA';
const STATUS_REVIEW_BG: string = '#FFF3E0';
/** 隐藏 Web 单点引导超时（毫秒） */
const BOOTSTRAP_TIMEOUT: number = 20000;

/**
 * 综评页：综合测评成绩查询（学生综合服务系统 xgfw.dmu.edu.cn）。
 * 会话建立（Web 单点引导）：综评不在教务（jwxt）域而在 xgfw 域，
 * 教务登录仅持有 CAS 的 CASTGC，xgfw 会话从未建立，
 * 首次进入时以 1×1 隐藏 Web 组件加载综评页面入口，
 * 由 WebView 完成 CAS→xgfw 的单点重定向链并把 _WEU/JSESSIONID 落入 Cookie 存储，
 * 落在 CAS 登录页说明教务会话已过期，引导用户先去「首页」登录；
 * 会话建立后由原生 HTTP（ZcpRepository）完成两步角色切换与只读业务查询。
 * 数据保留内存态，标准隐私模式下另做 filesDir 本地缓存（登录失效时回放，成功后自动替换），
 * 限制/严格隐私模式收紧与退出登录时连同临时缓存立即清除；标准模式退出登录仅失效会话，离线数据继续显示。
 */
@Component
export struct ZcpView {
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  /** 综评页签是否处于激活（可见）状态：首次激活自动开始加载 */
  @StorageProp('jwZcpTabActive') @Watch('onTabActive') zcpTabActive: boolean = false;
  /** 综评查询结果（仅内存态，隐私清理/退出登录时置空） */
  @StorageProp('jwZcpResult') @Watch('onResultChanged') result: ZcpResult | null = null;
  /** idle=未加载 bootstrap=Web 单点引导中 loading=业务拉取中 error=失败 */
  @State phase: string = 'idle';
  @State errorText: string = '';
  /** 隐藏 Web 单点引导是否进行中（条件渲染隐藏 Web 的开关） */
  @State bootstrapRunning: boolean = false;
  /** 展开附加分明细的指标代码（空串 = 无展开） */
  @State detailZbdm: string = '';
  @State detailItems: ZcpDetailItem[] = [];
  @State detailLoading: boolean = false;
  private webController: webview.WebviewController = new webview.WebviewController();
  private bootstrapTimer: number = -1;

  aboutToAppear(): void {
    this.loadIfNeeded();
  }

  aboutToDisappear(): void {
    this.clearBootstrapTimer();
  }

  /** 综评页签激活：首次可见且无数据时自动加载，避免应用启动即发起网络请求 */
  onTabActive(): void {
    this.loadIfNeeded();
  }

  /** 内存结果被隐私清理/退出登录清除：回到未加载态，等下次页签激活或手动获取 */
  onResultChanged(): void {
    if (this.result === null && this.phase === 'loaded') {
      this.phase = 'idle';
    }
  }

  /** 加载入口：页签可见且无在途任务时启动；优先回放本地临时缓存，再在线刷新 */
  private loadIfNeeded(): void {
    if (!this.zcpTabActive) {
      return;
    }
    if (this.bootstrapRunning || this.phase === 'bootstrap' || this.phase === 'loading') {
      return;
    }
    if (this.result === null) {
      const cached: ZcpResult | null = ZcpRepository.loadCache();
      if (cached !== null) {
        AppStorage.setOrCreate<ZcpResult>('jwZcpResult', cached);
        this.phase = 'loaded';
      }
    }
    if (this.result !== null && !this.result.fromCache) {
      return;
    }
    this.start();
  }

  /** 手动重试（错误卡片/未加载卡片的按钮）：清空错误后重新启动 */
  private retry(): void {
    if (this.phase === 'bootstrap' || this.phase === 'loading' || this.bootstrapRunning) {
      return;
    }
    this.errorText = '';
    this.start();
  }

  /** 启动加载：会话已就绪直接拉业务数据，否则先走 Web 单点引导 */
  private start(): void {
    if (ZcpRepository.isSessionReady()) {
      this.doLoad();
      return;
    }
    this.startBootstrap();
  }

  /** 开始 Web 单点引导：条件渲染隐藏 Web 加载页面入口，超时兜底 */
  private startBootstrap(): void {
    this.phase = 'bootstrap';
    this.bootstrapRunning = true;
    this.bootstrapTimer = setTimeout(() => {
      this.onBootstrapTimeout();
    }, BOOTSTRAP_TIMEOUT);
  }

  /** 单点引导超时：终止引导并提示重试 */
  private onBootstrapTimeout(): void {
    if (!this.bootstrapRunning) {
      return;
    }
    this.finishBootstrap();
    this.phase = 'error';
    this.errorText = '网络连接超时，请检查网络后重试';
  }

  /** 结束单点引导：关闭隐藏 Web 并清理超时定时器 */
  private finishBootstrap(): void {
    this.bootstrapRunning = false;
    this.clearBootstrapTimer();
  }

  private clearBootstrapTimer(): void {
    if (this.bootstrapTimer >= 0) {
      clearTimeout(this.bootstrapTimer);
      this.bootstrapTimer = -1;
    }
  }

  /** Web 页面加载结束：落在 CAS 登录页 = 教务会话过期；落在 xgfw = 单点成功，进入业务拉取 */
  private onBootstrapPageEnd(): void {
    if (!this.bootstrapRunning) {
      return;
    }
    let endedUrl: string = '';
    try {
      endedUrl = this.webController.getUrl();
    } catch (error) {
      endedUrl = '';
    }
    if (endedUrl.indexOf('authserver') >= 0) {
      this.finishBootstrap();
      this.phase = 'error';
      this.errorText = '请先在「首页」登录教务系统，再查看综评';
      return;
    }
    if (endedUrl.indexOf('xgfw.dmu.edu.cn') >= 0) {
      this.finishBootstrap();
      ZcpRepository.markSessionReady();
      this.doLoad();
    }
  }

  /** 主文档加载失败（子资源失败不触发）：终止引导并提示重试 */
  private onBootstrapError(event: OnErrorReceiveEvent): void {
    if (!this.bootstrapRunning) {
      return;
    }
    if (!event.request.isMainFrame()) {
      return;
    }
    this.finishBootstrap();
    this.phase = 'error';
    this.errorText = '网络连接失败，请检查网络后重试';
  }

  /** 业务拉取：角色切换 + 批次上下文 + 状态 + 指标树 + 得分回填；成功写临时缓存，失败回放缓存 */
  private async doLoad(): Promise<void> {
    this.phase = 'loading';
    try {
      const loaded: ZcpResult = await ZcpRepository.loadAll();
      ZcpRepository.saveCache(loaded);
      AppStorage.setOrCreate<ZcpResult>('jwZcpResult', loaded);
      this.phase = 'loaded';
    } catch (error) {
      const err: Error = error as Error;
      const message: string = err.message ?? `${err}`;
      if (message.indexOf(ZCP_SESSION_INVALID_ERROR) >= 0) {
        // CAS 会话已过期：清除会话标记，下次获取重新走 Web 单点引导
        ZcpRepository.clearSession();
      }
      if (this.result !== null) {
        // 已在展示数据（缓存回放）时刷新失败保持现状
        this.phase = 'loaded';
        return;
      }
      const cached: ZcpResult | null = ZcpRepository.loadCache();
      if (cached !== null) {
        AppStorage.setOrCreate<ZcpResult>('jwZcpResult', cached);
        this.phase = 'loaded';
        return;
      }
      if (message.indexOf(ZCP_SESSION_INVALID_ERROR) >= 0) {
        this.errorText = '登录状态已失效，请重新获取';
      } else {
        this.errorText = this.plainError(message);
      }
      this.phase = 'error';
    }
  }

  /** 附加项指标点击展开/收起明细（getZbFjfDetail，仅读接口） */
  private async toggleDetail(item: ZcpIndicator): Promise<void> {
    if (item.category !== '附加项') {
      return;
    }
    if (this.detailZbdm === item.zbdm) {
      this.detailZbdm = '';
      this.detailItems = [];
      return;
    }
    this.detailZbdm = item.zbdm;
    this.detailItems = [];
    this.detailLoading = true;
    try {
      this.detailItems = await ZcpRepository.fetchDetail(item.zbdm);
    } catch (error) {
      // 明细加载失败按空明细展示，不中断页面
      this.detailItems = [];
    }
    this.detailLoading = false;
  }

  /** 去掉 Error 字符串的 'Error: ' 前缀，便于直接展示 */
  private plainError(text: string): string {
    return text.startsWith('Error: ') ? text.substring(7) : text;
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

  /** 测评状态文本颜色 */
  private statusTextColor(result: ZcpResult): ResourceColor {
    const state: number = result.process.state;
    const text: string = result.process.statusText;
    if (state === 4 || text.indexOf('通过') >= 0) {
      return STATUS_PASS_COLOR;
    }
    if (state === 3 || text.indexOf('退回') >= 0) {
      return STATUS_REJECT_COLOR;
    }
    if (state === 2 || text.indexOf('审核') >= 0) {
      return STATUS_REVIEW_COLOR;
    }
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  /** 测评状态背景色 */
  private statusBgColor(result: ZcpResult): string {
    const state: number = result.process.state;
    const text: string = result.process.statusText;
    if (state === 4 || text.indexOf('通过') >= 0) {
      return STATUS_PASS_BG;
    }
    if (state === 3 || text.indexOf('退回') >= 0) {
      return STATUS_REJECT_BG;
    }
    if (state === 2 || text.indexOf('审核') >= 0) {
      return STATUS_REVIEW_BG;
    }
    return '#F1F1F1';
  }

  /** 指标右侧数值标签（附加项显示已获得，评分/成绩分显示 得分/上限，一级显示占比） */
  private indicatorLabel(item: ZcpIndicator): string {
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

  /** 指标数值文本颜色：有得分为激活色，附加项已获得为绿色 */
  private indicatorValueColor(item: ZcpIndicator): ResourceColor {
    if (item.category === '附加项' && item.extraGained.length > 0) {
      return STATUS_PASS_COLOR;
    }
    if (item.scoreText.length > 0 || item.fixedScore.length > 0) {
      return $r('sys.color.ohos_id_color_text_primary');
    }
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  /** 是否可画得分进度条：有数值得分且上限有效（附加项 999 为兜底值不作分母） */
  private hasScoreBar(item: ZcpIndicator): boolean {
    if (item.category === '附加项' || item.scoreText.length === 0) {
      return false;
    }
    const cap: number = Number.parseFloat(item.capText);
    if (Number.isNaN(cap) || cap <= 0 || cap === 999) {
      return false;
    }
    return true;
  }

  private scoreBarValue(item: ZcpIndicator): number {
    const value: number = Number.parseFloat(item.scoreText);
    return Number.isNaN(value) ? 0 : value;
  }

  private scoreBarTotal(item: ZcpIndicator): number {
    const total: number = Number.parseFloat(item.capText);
    return Number.isNaN(total) || total <= 0 ? 100 : total;
  }

  /** 顶带副标题：状态/无批次/获取中/失败 */
  private bandSubtitle(): string {
    if (this.phase === 'error') {
      return '获取失败，点击页面内按钮重试';
    }
    if (this.phase === 'bootstrap') {
      return '正在建立综评会话…';
    }
    if (this.phase === 'loading') {
      return '正在获取综评数据…';
    }
    const loaded: ZcpResult | null = this.result;
    if (loaded === null) {
      return '综评成绩查询';
    }
    if (!loaded.hasContext) {
      return '当前无参评批次';
    }
    return loaded.process.statusDisplay();
  }

  @Builder
  loadingCard(text: string) {
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

  @Builder
  errorCard() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(36)
        .fontColor([$r('sys.color.ohos_id_color_warning')])
      Text(this.errorText)
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
          this.retry();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 36, bottom: 36 })
    .alignItems(HorizontalAlign.Center)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  idleCard() {
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
          this.retry();
        })
    }
    .width('100%')
    .padding({ top: 36, bottom: 36 })
    .alignItems(HorizontalAlign.Center)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  /** 上下文信息行（label 值为空时不渲染在调用处保证） */
  @Builder
  ctxRow(label: string, value: string) {
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

  @Builder
  ctxCard(result: ZcpResult) {
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
          .fontColor(this.statusTextColor(result))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.statusBgColor(result))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      if (result.context.termDisplay.length > 0) {
        this.ctxRow('学年学期', result.context.termDisplay)
      }
      if (result.context.targetName.length > 0) {
        this.ctxRow('参评对象', result.context.targetName)
      }
      if (result.context.fillWindow.length > 0) {
        this.ctxRow('填写时间', result.context.fillWindow)
      }
      if (result.context.auditWindow.length > 0) {
        this.ctxRow('审核时间', result.context.auditWindow)
      }
      if (result.process.state === 3 && result.process.rejectReason.length > 0) {
        Text('退回原因：' + result.process.rejectReason)
          .fontSize(13)
          .fontColor(STATUS_REJECT_COLOR)
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
  }

  /** 附加项行是否可展开明细（展示展开图标） */
  private isExpandable(item: ZcpIndicator): boolean {
    return item.category === '附加项';
  }

  /** 行左侧展开箭头（展开时旋转 180°） */
  @Builder
  expandChevron(item: ZcpIndicator, size: number) {
    SymbolGlyph($r('sys.symbol.chevron_down'))
      .fontSize(size)
      .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      .rotate({ angle: this.detailZbdm === item.zbdm ? 180 : 0 })
      .margin({ right: 4 })
  }

  /** 附加分明细展开区（挂在被点击的附加项行下方） */
  @Builder
  detailArea(item: ZcpIndicator) {
    Column({ space: 8 }) {
      if (this.detailLoading) {
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
      } else if (this.detailItems.length === 0) {
        Text('暂无附加分明细')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      } else {
        ForEach(this.detailItems, (detail: ZcpDetailItem) => {
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

  /** 三级指标行（挂在二级行下，缩进展示） */
  @Builder
  level3Row(item: ZcpIndicator) {
    Column() {
      Row() {
        if (this.isExpandable(item)) {
          this.expandChevron(item, 14)
        }
        Text(item.name)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.indicatorLabel(item))
          .fontSize(13)
          .fontColor(this.indicatorValueColor(item))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 6, bottom: 6 })
      if (this.hasScoreBar(item)) {
        Progress({ value: this.scoreBarValue(item), total: this.scoreBarTotal(item), type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color($r('sys.color.ohos_id_color_text_primary_activated'))
          .borderRadius(2)
          .padding({ bottom: 4 })
      }
      if (this.detailZbdm === item.zbdm) {
        this.detailArea(item)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 26 })
    .onClick(() => {
      this.toggleDetail(item);
    })
  }

  /** 二级指标行（附加项可点击展开明细） */
  @Builder
  level2Row(item: ZcpIndicator) {
    Column() {
      Row() {
        if (this.isExpandable(item)) {
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
        Text(this.indicatorLabel(item))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.indicatorValueColor(item))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 8, bottom: 4 })
      if (this.hasScoreBar(item)) {
        Progress({ value: this.scoreBarValue(item), total: this.scoreBarTotal(item), type: ProgressType.Linear })
          .width('100%')
          .height(5)
          .color($r('sys.color.ohos_id_color_text_primary_activated'))
          .borderRadius(2.5)
      }
      ForEach(item.children, (child: ZcpIndicator) => {
        this.level3Row(child)
      }, (child: ZcpIndicator) => child.zbdm + child.name + child.scoreText)
      if (this.detailZbdm === item.zbdm) {
        this.detailArea(item)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8 })
    .onClick(() => {
      this.toggleDetail(item);
    })
  }

  /** 多维图数据：二级素质维度中得分与满分均可解析的条目（附加项 999 兜底上限排除）。
   * 一级「综合素质」为计算项无得分，雷达轴取其下二级指标（get23zbScore 回填源，实测 8 项）。 */
  private radarEntries(result: ZcpResult): RadarEntry[] {
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

  /** 素质得分多维图卡片：有效维度 ≥3 时展示雷达图 */
  @Builder
  radarCard(result: ZcpResult) {
    if (this.radarEntries(result).length >= 3) {
      Column() {
        Text('素质得分多维图')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
          .padding({ bottom: 4 })
        ZcpRadarChart({ entries: this.radarEntries(result) })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 12 })
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
    }
  }

  /** 一级指标卡片：指标名 + 占比 + 二级明细 */
  @Builder
  indicatorCard(root: ZcpIndicator) {
    Column() {
      Row() {
        Text(root.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.indicatorLabel(root))
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
        this.level2Row(child)
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
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          if (this.result !== null) {
            this.ctxCard(this.result)
            if (this.result.fromCache) {
              Text('正在展示本地缓存数据，联网刷新成功后自动更新（点击重试）')
                .fontSize(11)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width('100%')
                .padding({ top: 6 })
                .onClick(() => {
                  this.retry();
                })
            }
            if (!this.result.hasContext) {
              Text('当前学期暂无综评批次（未开放或无参评资格）')
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .padding({ top: 16, bottom: 16 })
            } else {
              this.radarCard(this.result)
              ForEach(this.result.indicators, (root: ZcpIndicator) => {
                this.indicatorCard(root)
              }, (root: ZcpIndicator) => root.zbdm + root.name + root.scoreText)
              if (this.result.indicators.length === 0) {
                Text('暂无测评指标数据')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .padding({ top: 16, bottom: 16 })
              }
              Text('以上为当前批次数据，最终成绩以学校系统为准')
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .padding({ top: 12, bottom: 12 })
            }
          } else if (this.phase === 'bootstrap' || this.phase === 'loading') {
            this.loadingCard(this.phase === 'bootstrap' ? '正在建立综评会话…' : '正在获取综评数据…')
          } else if (this.phase === 'error') {
            this.errorCard()
          } else {
            this.idleCard()
          }
        }
        .padding({ left: 16, right: 16, top: FROST_BAND_HEIGHT, bottom: this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      FrostBand() {
        Row({ space: 8 }) {
          Text('综评')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text(this.bandSubtitle())
            .fontSize(12)
            .fontColor(this.phase === 'error' ?
              $r('sys.color.ohos_id_color_warning') :
              $r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }

      if (this.bootstrapRunning) {
        Web({ src: ZcpRepository.indexUrl(), controller: this.webController })
          .width(1)
          .height(1)
          .opacity(0)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onPageEnd(() => {
            this.onBootstrapPageEnd();
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            this.onBootstrapError(event);
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
