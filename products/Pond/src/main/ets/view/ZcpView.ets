import { display, window } from '@kit.ArkUI';
import { ZcpIndicator, ZcpResult } from '../model/ZcpModels';
import { ZcpRepository, ZCP_SESSION_INVALID_ERROR } from '../data/ZcpRepository';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { plainError, ZcpCtxCard, ZcpErrorCard, ZcpIdleCard, ZcpLoadingCard, ZcpOfflineBanner, ZcpRadarCard } from './ZcpCards';
import { ZcpIndicatorCard } from './ZcpIndicatorCards';
import { CrossDomainSession } from '../net/CrossDomainSession';
import { DOMAIN_XGFW } from '../net/DomainSpec';

/**
 * 综评页：综合测评成绩查询（学生综合服务系统 xgfw.dmu.edu.cn）。
 * 会话建立（跨域换票）：综评不在教务（jwxt）域而在 xgfw 域，
 * 教务登录仅持有 CAS 的 CASTGC，xgfw 会话从未建立，
 * 首次进入时经全 App 唯一的跨域会话服务（net/CrossDomainSession，
 * 由根页面 pages/Index 常驻的 1×1 隐藏 Web 承载）加载综评页面入口，
 * 由 WebView 完成 CAS→xgfw 的单点重定向链并把 _WEU/JSESSIONID 落入 Cookie 存储，
 * 落在 CAS 登录页说明教务会话已过期，引导用户先去「首页」登录；
 * 会话建立后由原生 HTTP（ZcpRepository）完成两步角色切换与只读业务查询。
 * 数据保留内存态，标准隐私模式下另做 filesDir 本地缓存（登录失效时回放，成功后自动替换），
 * 限制/严格隐私模式收紧与退出登录时连同临时缓存立即清除；标准模式退出登录清除 filesDir 临时缓存，内存数据保留至进程结束。
 */
@Component
export struct ZcpView {
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  /** 教务数据模式：offlineCache（标准模式退出登录）时综评页同样置顶离线提示；变为 online（登录成功）时自动补拉 */
  @StorageProp('jwDataMode') @Watch('onDataModeChanged') dataMode: string = 'preview';
  /** 综评页签是否处于激活（可见）状态：首次激活自动开始加载 */
  @StorageProp('jwZcpTabActive') @Watch('onTabActive') zcpTabActive: boolean = false;
  /** 综评查询结果（仅内存态，隐私清理/退出登录时置空） */
  @StorageProp('jwZcpResult') @Watch('onResultChanged') result: ZcpResult | null = null;
  /** idle=未加载 bootstrap=跨域换票中 loading=业务拉取中 error=失败 */
  @State phase: string = 'idle';
  @State errorText: string = '';
  @State isRefreshing: boolean = false;
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** Refresh 布局高度：初始取屏幕高度，旋转后由窗口尺寸事件刷新（display 快照在旋转瞬间滞后） */
  @State refreshHeight: Length = '100%';
  /** 窗口宽高（px）：横竖屏方向判定；启动时取 display 快照，旋转后由窗口尺寸事件刷新 */
  @State winWidthPx: number = 0;
  @State winHeightPx: number = 0;
  /** 离线横幅实测高度（vp）：宽屏双列时横幅横跨双列上方，双列行高按其动态扣减 */
  @State bannerHeightVp: number = 0;
  /** 窗口尺寸变化回调：持有引用便于精准解绑，避免 off 误伤其他视图的监听 */
  private readonly onWinSizeChanged = (size: window.Size): void => {
    // 旋转：状态更新包进 animateTo，驱动单列/双列分支 geometryTransition 飞行与高度渐变
    this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction }, () => {
      this.applyWindowSize(size.width, size.height);
    });
  };

  aboutToAppear(): void {
    this.initWindowDims();
    this.refreshHeight = this.refreshHeightVp();
    this.bindWindowHeight();
    this.loadIfNeeded();
  }

  aboutToDisappear(): void {
    this.unbindWindowHeight();
  }

  /** 综评页签激活：首次可见且无数据时自动加载，避免应用启动即发起网络请求 */
  onTabActive(): void {
    this.loadIfNeeded();
  }

  /** 登录成功（dataMode 变为 online）：页签可见且数据待更新时自动补拉综评 */
  onDataModeChanged(): void {
    this.loadIfNeeded();
  }

  /** 内存结果被隐私清理/退出登录清除：回到未加载态，等下次页签激活或手动获取 */
  onResultChanged(): void {
    if (this.result === null && this.phase === 'loaded') { this.phase = 'idle'; }
  }

  /** 加载入口：页签可见且无在途任务时启动；优先回放本地临时缓存，再在线刷新 */
  private loadIfNeeded(): void {
    if (!this.zcpTabActive || this.phase === 'bootstrap' || this.phase === 'loading') {
      return;
    }
    if (this.result === null) {
      const cached: ZcpResult | null = ZcpRepository.loadCache();
      if (cached !== null) {
        AppStorage.setOrCreate<ZcpResult>('jwZcpResult', cached);
        this.phase = 'loaded';
      }
    }
    if (this.result !== null && !this.result.fromCache) { return; }
    // 未登录（preview/offline/offlineCache）不自动发起跨域换票与业务请求，登录成功后经 dataMode 监听自动补拉；
    // 手动获取/重试与下拉刷新不受此限（失败由页面内错误卡片/提示反馈）
    if (this.dataMode !== 'online') { return; }
    this.start();
  }

  /** 手动重试（错误卡片/未加载卡片的按钮）：清空错误后重新启动 */
  private retry(): void {
    if (this.phase === 'bootstrap' || this.phase === 'loading') { return; }
    this.errorText = '';
    this.start();
  }

  /** 去登录：标准模式退出登录后离线数据仍在，引导重新登录以在线刷新 */
  private goLogin(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginIndex' });
  }

  /** 下拉刷新：已连接教务系统时重新获取综评数据；未登录时提示先登录并立即收起刷新动画 */
  private doRefresh(): void {
    this.isRefreshing = false;
    if (this.dataMode !== 'online') {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录教务系统后再刷新', duration: 1500 });
      } catch (error) {
      }
      return;
    }
    if (this.phase === 'bootstrap' || this.phase === 'loading') { return; }
    this.errorText = '';
    this.start();
  }

  /** 启动加载：会话已就绪直接拉业务数据，否则先走跨域换票（隐藏 Web 由根页面常驻承载） */
  private start(): void {
    if (ZcpRepository.isSessionReady()) { this.doLoad(); return; }
    this.beginLoad();
  }

  /** 跨域换票后拉业务数据：换票失败（落在 CAS 登录页/超时/加载失败）提示先登录 */
  private async beginLoad(): Promise<void> {
    this.phase = 'bootstrap';
    const ok: boolean = await CrossDomainSession.ensure(DOMAIN_XGFW);
    if (!ok) {
      this.phase = 'error';
      this.errorText = '请先在「首页」登录教务系统，再查看综评';
      return;
    }
    ZcpRepository.markSessionReady();
    this.doLoad();
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
        // CAS 会话已过期：清除会话标记与跨域就绪集，下次获取重新走隐藏 Web 换票
        ZcpRepository.clearSession();
        CrossDomainSession.reset();
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
      this.errorText = message.indexOf(ZCP_SESSION_INVALID_ERROR) >= 0 ?
        '登录状态已失效，请重新获取' : plainError(message);
      this.phase = 'error';
    }
  }

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') { return 600; }
    return this.isWide() ? 1200 : 1000;
  }

  /** 平板/电脑横屏（lg/xl 且窗口为横屏方向）双列布局，切换逻辑与首页保持一致 */
  private isWide(): boolean {
    if (this.currentBreakpoint !== 'lg' && this.currentBreakpoint !== 'xl') { return false; }
    // 大屏平板竖屏宽度也可能达到 lg（如 13 寸平板竖屏 960vp）：处于竖屏（宽 ≤ 高）时仍用单列纵向排版
    if (this.winWidthPx > 0 && this.winHeightPx > 0 && this.winWidthPx <= this.winHeightPx) { return false; }
    return true;
  }

  private bottomInset(): number {
    return 88;
  }

  /**
   * 横屏双列行高：外层滚动视口高 − 顶带让位高，使外层 Scroll 恰好不滚
   * （左列固定不动、右列独立滚动）；窗口高度未知时回退 100%。
   */
  /** 离线横幅块高（实测组件高 + 底边距）：宽屏双列时横幅横跨双列上方，行高按其扣减使外层恰好不滚 */
  private bannerBlockVp(): number {
    if (this.result === null) { return 0; }
    if (!this.result.fromCache && this.dataMode !== 'offlineCache') { return 0; }
    return this.bannerHeightVp > 0 ? this.bannerHeightVp + 10 : 0;
  }

  private wideRowHeight(): Length {
    if (this.winHeightPx <= 0) { return '100%'; }
    const viewportVp: number = this.getUIContext().px2vp(this.winHeightPx);
    const insetVp: number = frostTopInsetVp(this.safeTopPx, this.getUIContext());
    return Math.max(viewportVp - insetVp - this.bannerBlockVp(), 0);
  }

  /**
   * Refresh 组件会接管子组件几何并吞掉其 expandSafeArea，导致内部 Scroll 的
   * 滚动视口无法扩展进安全避让区（内容永远裁剪在避让区上方）。
   * 因此不给 Refresh 走 expandSafeArea，而是显式把它的布局高度设为整屏高度
   * （窗口沉浸式全屏，布局从屏幕顶部开始），使 Refresh 与内部 Scroll
   * 的布局本身覆盖状态栏与底部手势区，滚动视口随布局自然延伸。
   */
  private refreshHeightVp(): Length {
    let screenHeightPx: number = 0;
    try {
      screenHeightPx = display.getDefaultDisplaySync().height;
    } catch (err) {
      screenHeightPx = 0;
    }
    if (screenHeightPx <= 0) {
      return '100%';
    }
    return this.getUIContext().px2vp(screenHeightPx);
  }

  /** 启动时同步读取 display 宽高：用于初始横竖屏方向判定（启动时 display 快照是准确的） */
  private initWindowDims(): void {
    try {
      const disp: display.Display = display.getDefaultDisplaySync();
      this.winWidthPx = disp.width;
      this.winHeightPx = disp.height;
    } catch (err) {
      // 读取失败保持 0，留给窗口尺寸事件回填
    }
  }

  /** 按窗口尺寸（px）刷新 Refresh 布局高度与横竖屏方向判定数据 */
  private applyWindowSize(widthPx: number, heightPx: number): void {
    if (widthPx > 0 && heightPx > 0) {
      this.winWidthPx = widthPx;
      this.winHeightPx = heightPx;
      this.refreshHeight = this.getUIContext().px2vp(heightPx);
    }
  }

  /** 绑定主窗口尺寸变化：旋转后以窗口事件数据刷新 Refresh 高度与方向判定（display 快照可能滞后） */
  private bindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      this.applyWindowSize(rect.width, rect.height);
      win.on('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  /** 解绑窗口尺寸变化监听 */
  private unbindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.off('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  /** 顶带副标题：状态/无批次/获取中（获取失败时由页面内错误卡片与离线提示条反馈，顶带不显示红字） */
  private bandSubtitle(): string {
    if (this.phase === 'bootstrap') { return '正在建立综评会话…'; }
    if (this.phase === 'loading') { return '正在获取综评数据…'; }
    const loaded: ZcpResult | null = this.result;
    if (loaded === null) { return '综评成绩查询'; }
    return loaded.hasContext ? loaded.process.statusDisplay() : '当前无参评批次';
  }

  /**
   * 平板横屏双列布局（自 ZcpIndicatorCards 并回）：左列（批次上下文卡 + 雷达图）固定不随滚动，
   * 右列（一级指标明细卡）独立滚动；左右宽度比与首页横屏一致。
   * 离线横幅不在此处渲染，由外层内容顶部横跨双列全宽展示。
   * 双列行高按外层滚动视口与横幅块高精确计算，使外层 Scroll 恰好不滚（左列保持不动），
   * 内层滚动经 SELF_FIRST 延伸到外层，下拉刷新仍然可用。
   */
  @Builder
  wideContent() {
    if (this.result !== null) {
      Row() {
        Scroll() {
          Column() {
            ZcpCtxCard({ result: this.result })
            ZcpRadarCard({ result: this.result })
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
            ForEach(this.result.indicators, (root: ZcpIndicator) => {
              ZcpIndicatorCard({ root: root })
            }, (root: ZcpIndicator) => root.zbdm + root.name + root.scoreText)
            if (this.result.indicators.length === 0) {
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
          .padding({ bottom: this.bottomInset() })
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
      .height(this.wideRowHeight())
      .alignItems(VerticalAlign.Top)
      .constraintSize({ maxWidth: 1200 })
      .alignSelf(ItemAlign.Center)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          if (this.result !== null) {
            // 离线横幅恒在外层内容顶部：单列全宽，双列横跨左右两列上方全宽；
            // 宽屏行高按实测横幅块高扣减（wideRowHeight），外层 Scroll 仍恰好不滚
            if (this.result.fromCache || this.dataMode === 'offlineCache') {
              ZcpOfflineBanner({ dataMode: this.dataMode, onGoLogin: (): void => this.goLogin(),
                onRetry: (): void => this.retry(), onBannerHeight: (heightVp: number): void => {
                  this.bannerHeightVp = heightVp;
                } })
            }
            if (this.isWide() && this.result.hasContext) {
              this.wideContent()
            } else {
              ZcpCtxCard({ result: this.result })
              if (!this.result.hasContext) {
                Text('当前学期暂无综评批次（未开放或无参评资格）')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .padding({ top: 16, bottom: 16 })
              } else {
                ZcpRadarCard({ result: this.result })
                ForEach(this.result.indicators, (root: ZcpIndicator) => {
                  ZcpIndicatorCard({ root: root })
                }, (root: ZcpIndicator) => root.zbdm + root.name + root.scoreText)
                if (this.result.indicators.length === 0) {
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
            }
          } else if (this.phase === 'bootstrap' || this.phase === 'loading') {
            ZcpLoadingCard({ text: this.phase === 'bootstrap' ? '正在建立综评会话…' : '正在获取综评数据…' })
          } else if (this.phase === 'error') {
            ZcpErrorCard(this.errorText, (): void => this.retry())
          } else {
            ZcpIdleCard({ loggedIn: this.dataMode === 'online', onRetry: (): void => this.retry(),
              onGoLogin: (): void => this.goLogin() })
          }
        }
        .padding({
          left: 16,
          right: 16,
          top: frostTopInsetVp(this.safeTopPx, this.getUIContext()),
          bottom: (this.result !== null && this.result.hasContext && this.isWide()) ? 0 : this.bottomInset()
        })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      }
      .onRefreshing(() => {
        this.doRefresh();
      })
      .width('100%')
      .height(this.refreshHeight)

      FrostBand() {
        Row({ space: 8 }) {
          Text('综评')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text(this.bandSubtitle())
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
