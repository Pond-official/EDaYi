import { BreakpointSystem } from '@ohos/common';
import { display, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { HdsNavigation, HdsTabs, HdsTabsController, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HomeView } from '../view/HomeView';
import { GradeView } from '../view/GradeView';
import { ZcpView } from '../view/ZcpView';
import { SelectionView } from '../view/SelectionView';
import { SettingsEntryButton } from '../view/SettingsEntryButton';
import { JwxtRepository } from '../data/JwxtRepository';
import { MaterialUtils } from '../utils/MaterialUtils';
import { CrossDomainSession } from '../net/CrossDomainSession';

/** 悬浮页签栏最大宽度（宽屏基准），窄屏按屏宽收缩 */
const BAR_MAX_WIDTH: number = 392;
/** 悬浮页签栏左右留白（vp） */
const BAR_SIDE_MARGIN: number = 32;
/** 悬浮页签栏与屏幕底部边距（vp） */
const BAR_BOTTOM_MARGIN: number = 16;
/** 悬浮页签栏高度（vp） */
const BAR_HEIGHT: number = 64;
/** 沉浸光感（uiMaterial/barFloatingStyle）所需系统版本：26.0.0 对应 distributionOSApiVersion 26*10000 */
const IMMERSIVE_OS_API_VERSION: number = 260000;
/** HDS 组件（UI Design Kit）系统能力标识 */
const HDS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core';
/** 首页页签索引（驱动首页页签切回时检查已结束考试） */
const TAB_INDEX_HOME: number = 0;
/** 综评页签索引（驱动综评页首次可见时自动建立会话并加载） */
const TAB_INDEX_ZCP: number = 2;
/** 选课页签索引（驱动选课页首次可见时自动加载验证码） */
const TAB_INDEX_SELECTION: number = 3;
/** 右上角设置入口与屏幕顶部边距（vp） */
const SETTINGS_TOP_MARGIN: number = 10;
/** 右上角设置入口与屏幕右侧边距（vp） */
const SETTINGS_SIDE_MARGIN: number = 16;

/**
 * 应用主框架：首页、成绩、综评、选课四个页签 + 右上角设置入口（所有页面可见）。
 * 底栏（HDS 版本，主路径）：
 *   build 以 Stack 为根，HdsNavigation 包裹 HdsTabs，
 *   HdsTabs 设 barFloatingStyle 悬浮导航栏样式（沉浸材质 + 光效指示器），
 *   选中页签由悬浮导航栏系统光效指示（lightColor 光感反馈，按压/选中处透出光晕）；
 *   内容区支持左右滑动切换页签（scrollable），页签栏轻点与内容滑动互通；
 *   页签栏宽度随窗口尺寸变化自动重算（横竖屏切换、折叠屏开合、分屏/悬浮窗拖动），
 *   各视图通过断点（mainBreakpoint）自动适配横竖屏布局；
 *   设备缺少 HDS 能力时降级：API 26+ 走 uiMaterial 悬浮页签栏，再退普通底栏。
 */
@Entry
@Component
struct Index {
  /** 悬浮页签栏宽度（vp），随窗口宽度自适应（启动取屏宽，运行中随区域变化重算） */
  @State barWidthVp: number = BAR_MAX_WIDTH;
  /** 当前选中页签索引；变化时同步选课/综评页签激活状态 */
  @State @Watch('onTabChanged') currentTabIndex: number = 0;
  /** 状态栏避让区高度（px）：沉浸式全屏下设置入口按钮顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** 设备是否具备 HDS 组件能力（UI Design Kit） */
  private hdsSupported: boolean = false;
  /** 当前设备是否支持悬浮页签栏 + 沉浸光感（API 26+），降级分支使用 */
  private supportsFloatingBar: boolean = false;
  /** 降级分支页签栏沉浸光感材质 */
  private barMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  tabLabels: string[] = ['首页', '成绩', '综评', '选课'];
  private readonly hdsTabsController: HdsTabsController = new HdsTabsController();
  private readonly tabsController: TabsController = new TabsController();
  private readonly breakpointSystem: BreakpointSystem = new BreakpointSystem('mainBreakpoint');
  /** 跨域会话换票用常驻隐藏 Web 的控制器（CrossDomainSession 全 App 唯一宿主） */
  private readonly cross: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.breakpointSystem.register(this.getUIContext());
    this.fitBarWidth();
    this.hdsSupported = canIUse(HDS_SYSCAP);
    this.supportsFloatingBar = deviceInfo.distributionOSApiVersion >= IMMERSIVE_OS_API_VERSION;
    this.barMaterial = this.buildBarMaterial();
    JwxtRepository.ensureLoaded();
    this.onTabChanged();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister();
  }

  /** 页面重新可见（从设置/登录等路由页返回）：更新前台时刻戳，
   * 驱动首页刷新"今日课程"并检查已结束的期末倒计时 */
  onPageShow(): void {
    JwxtRepository.notifyForeground();
  }

  /**
   * 页签切换：写入选课/综评页签激活状态（AppStorage），
   * 选课页据此在首次可见且未登录时自动获取图形验证码，
   * 综评页据此在首次可见时自动建立 xgfw 会话并加载综评数据，
   * 避免应用启动（Tabs 全量构建页签内容）即触发网络请求。
   */
  onTabChanged(): void {
    AppStorage.setOrCreate<boolean>('jwHomeTabActive', this.currentTabIndex === TAB_INDEX_HOME);
    AppStorage.setOrCreate<boolean>('jwSelectionTabActive', this.currentTabIndex === TAB_INDEX_SELECTION);
    AppStorage.setOrCreate<boolean>('jwZcpTabActive', this.currentTabIndex === TAB_INDEX_ZCP);
  }

  /** 右上角设置入口顶部边距（vp）：沉浸式全屏下叠加状态栏避让区，保持与原视觉位置一致 */
  private settingsTopMargin(): number {
    return this.getUIContext().px2vp(this.safeTopPx) + SETTINGS_TOP_MARGIN;
  }

  /** 按给定窗口宽度收缩悬浮页签栏宽度：栏宽 = min(基准宽, 窗宽 - 左右留白) */
  private fitBarWidthTo(windowWidthVp: number): void {
    const width: number = Math.min(BAR_MAX_WIDTH, Math.floor(windowWidthVp - BAR_SIDE_MARGIN * 2));
    if (width > 0 && width !== this.barWidthVp) {
      this.barWidthVp = width;
    }
  }

  /** 启动时按屏幕宽度初始化悬浮页签栏宽度 */
  private fitBarWidth(): void {
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      this.fitBarWidthTo(screen.width / screen.densityPixels);
    } catch (error) {
      // 取默认宽度
    }
  }

  /**
   * 降级分支页签栏沉浸光感材质：MaterialUtils 统一构造（与底栏/顶部材质条同款），
   * 设备不支持沉浸光感时返回 undefined，由系统使用默认页签样式。
   */
  private buildBarMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (!this.supportsFloatingBar) {
      return undefined;
    }
    return MaterialUtils.barMaterial();
  }

  /** HDS 悬浮导航栏材质：设备支持沉浸材质时使用沉浸材质，否则跟随系统材质策略 */
  private buildHdsMaterial(): SystemMaterialParams {
    try {
      const supported: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      if (supported.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        return {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        };
      }
    } catch (error) {
      // 跟随系统材质策略
    }
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
    };
  }

  private tabIcon(index: number): Resource {
    if (index === 0) {
      return $r('sys.symbol.house');
    }
    if (index === 1) {
      return $r('sys.symbol.doc_text');
    }
    if (index === 2) {
      return $r('sys.symbol.medal');
    }
    return $r('sys.symbol.list_bullet');
  }

  /** 页签栏 symbol 图标：常态默认色，选中态跟随应用激活色（TabBarSymbol 为数据类型，须以对象字面量构造） */
  private tabSymbol(index: number): TabBarSymbol {
    const icon: Resource = this.tabIcon(index);
    const symbol: TabBarSymbol = {
      normal: new SymbolGlyphModifier(icon),
      selected: new SymbolGlyphModifier(icon)
        .fontColor([$r('sys.color.ohos_id_color_text_primary_activated')])
    };
    return symbol;
  }

  /** 四个页签页（HDS/悬浮/普通三种底栏共用）：TabContent 顶部安全区扩展，配合视图内顶部材质条上扩覆盖状态栏 */
  @Builder
  tabPages() {
    TabContent() {
      HomeView()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(0), this.tabLabels[0]))

    TabContent() {
      GradeView()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(1), this.tabLabels[1]))

    TabContent() {
      ZcpView()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(2), this.tabLabels[2]))

    TabContent() {
      SelectionView()
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(3), this.tabLabels[3]))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 跨域会话换票用 1×1 隐藏 Web（任务 14）：全 App 唯一宿主，常驻整个主框架生命周期。
      // 必须用 opacity(0.01) 隐藏（Visibility.None 可能导致 Web 不真正加载、onPageEnd 不触发），
      // 也不能条件渲染（会产生新 controller 使 CrossDomainSession.attach 失效）。
      Web({ src: 'about:blank', controller: this.cross })
        .width(1)
        .height(1)
        .opacity(0.01)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onControllerAttached(() => {
          CrossDomainSession.attach(this.cross);
        })
        .onPageEnd(() => {
          let endedUrl: string = '';
          try {
            endedUrl = this.cross.getUrl();
          } catch (error) {
            endedUrl = '';
          }
          CrossDomainSession.onPageEnd(endedUrl);
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event.request.isMainFrame()) {
            CrossDomainSession.onError();
          }
        })

      if (this.hdsSupported) {
        HdsNavigation() {
          HdsTabs({ controller: this.hdsTabsController }) {
            this.tabPages()
          }
          .barPosition(BarPosition.End)
          .vertical(false)
          .scrollable(true)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .barOverlap(true)
          .barHeight(BAR_HEIGHT)
          .animationDuration(300)
          .onSelected((index: number) => {
            this.currentTabIndex = index;
          })
          .barFloatingStyle({
            barWidth: {
              smallWidth: this.barWidthVp,
              mediumWidth: this.barWidthVp,
              largeWidth: this.barWidthVp
            },
            barSideMargin: BAR_SIDE_MARGIN,
            barBottomMargin: BAR_BOTTOM_MARGIN,
            lightColor: Color.White,
            systemMaterialEffect: this.buildHdsMaterial()
          })
          .width('100%')
          .height('100%')
        }
        .hideTitleBar(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .width('100%')
        .height('100%')
      } else if (this.supportsFloatingBar) {
        Tabs({
          barPosition: BarPosition.End,
          controller: this.tabsController
        }) {
          this.tabPages()
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .barHeight(BAR_HEIGHT)
        .animationDuration(300)
        .onSelected((index: number) => {
          this.currentTabIndex = index;
        })
        .barFloatingStyle({
          barWidth: {
            smallBarWidth: this.barWidthVp,
            mediumBarWidth: this.barWidthVp,
            largeBarWidth: this.barWidthVp
          },
          barSideMargin: BAR_SIDE_MARGIN,
          barBottomMargin: BAR_BOTTOM_MARGIN,
          systemMaterial: this.barMaterial
        })
        .width('100%')
        .height('100%')
      } else {
        Tabs({
          barPosition: BarPosition.End,
          controller: this.tabsController
        }) {
          this.tabPages()
        }
        .vertical(false)
        .scrollable(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .barHeight(BAR_HEIGHT)
        .animationDuration(300)
        .onSelected((index: number) => {
          this.currentTabIndex = index;
        })
        .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .width('100%')
        .height('100%')
      }

      // 右上角设置入口：全屏透传覆盖层（不挡下层触摸），仅按钮自身可点，所有页签可见
      Stack({ alignContent: Alignment.TopEnd }) {
        SettingsEntryButton()
          .margin({ top: this.settingsTopMargin(), right: SETTINGS_SIDE_MARGIN })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((oldArea: Area, newArea: Area) => {
      if (typeof newArea.width === 'number') {
        this.fitBarWidthTo(newArea.width);
      }
    })
  }
}
