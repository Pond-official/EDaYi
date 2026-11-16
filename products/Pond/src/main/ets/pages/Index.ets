import { BreakpointSystem } from '@ohos/common';
import { display, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsTabs, HdsTabsController, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HomeView } from '../view/HomeView';
// 非首屏页签视图延迟加载（lazy import）：冷启动不求值其模块图
// （含 SelectionRepository 的 huks 加密、ZcpView 图表等），首次切页签时才加载（一次性 ~10-50ms）
import lazy { GradeView } from '../view/GradeView';
import lazy { ZcpView } from '../view/ZcpView';
import lazy { SelectionView } from '../view/SelectionView';
// 冷启动优化 ③：跨域换票隐藏 Web 宿主同样延迟加载，ArkWeb 实例首次换票时才创建
import lazy { HiddenWeb } from '../view/HiddenWeb';
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
  /** 底栏光效颜色（开发者选项自定义，#RRGGBB）：变化时重建降级分支页签栏材质（HDS 主路径由状态驱动自动刷新） */
  @StorageProp('jwLightEffectColor') @Watch('onLightEffectColorChanged') lightEffectColor: string = '#FFFFFF';
  /** 底栏材质档位（开发者选项自定义，ADAPTIVE/EXQUISITE/GENTLE/SMOOTH） */
  @StorageProp('jwMaterialLevel') materialLevel: string = 'ADAPTIVE';
  /** 设备是否具备 HDS 组件能力（UI Design Kit） */
  private hdsSupported: boolean = false;
  /** 当前设备是否支持悬浮页签栏 + 沉浸光感（API 26+），降级分支使用 */
  private supportsFloatingBar: boolean = false;
  /** 降级分支页签栏沉浸光感材质（随光效颜色自定义重建） */
  @State barMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  tabLabels: string[] = ['首页', '成绩', '综评', '选课'];
  /** 页签内容重建分支：每次激活已访问页签时翻转，强制视图重建以重播级联入场（TabContent 懒加载只构建一次，转场仅首次激活播放） */
  @State tabFresh: boolean[] = [false, false, false, false];
  /** 页签是否已被激活过（首页启动即激活）：首次激活走懒加载入场，之后激活靠翻转重建重播 */
  private tabVisited: boolean[] = [true, false, false, false];
  private readonly hdsTabsController: HdsTabsController = new HdsTabsController();
  private readonly tabsController: TabsController = new TabsController();
  private readonly breakpointSystem: BreakpointSystem = new BreakpointSystem('mainBreakpoint');
  /** 跨域换票隐藏 Web 宿主是否需要挂载（冷启动优化 ③）：
   * CrossDomainSession 首次换票时经回调置 true（条件渲染 HiddenWeb），
   * 只置 true 不复位 —— 宿主一旦挂载常驻主框架生命周期，不随换票结束卸载 */
  @State crossHostNeeded: boolean = false;

  aboutToAppear(): void {
    this.breakpointSystem.register(this.getUIContext());
    this.fitBarWidth();
    this.hdsSupported = canIUse(HDS_SYSCAP);
    this.supportsFloatingBar = deviceInfo.distributionOSApiVersion >= IMMERSIVE_OS_API_VERSION;
    this.barMaterial = this.buildBarMaterial();
    CrossDomainSession.setHostRequestCallback(() => {
      this.crossHostNeeded = true;
    });
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

  /** 页签选中（HDS/悬浮/普通底栏共用）：已访问页签翻转重建分支重播级联渐入，首次激活仅记录（懒加载自带入场） */
  private onTabSelected(index: number): void {
    if (this.tabVisited[index]) {
      this.tabFresh[index] = !this.tabFresh[index];
    } else {
      this.tabVisited[index] = true;
    }
    this.currentTabIndex = index;
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

  /** 光效颜色自定义变化：重建降级分支页签栏沉浸材质，使 lightEffect 新颜色立即生效 */
  onLightEffectColorChanged(): void {
    this.barMaterial = this.buildBarMaterial();
  }

  /**
   * 降级分支页签栏沉浸光感材质：MaterialUtils 统一构造（与底栏/顶部材质条同款），
   * 光效颜色取开发者选项自定义值，设备不支持沉浸光感时返回 undefined，由系统使用默认页签样式。
   */
  private buildBarMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (!this.supportsFloatingBar) {
      return undefined;
    }
    return MaterialUtils.barMaterial(this.lightEffectColor);
  }

  /** HDS 悬浮导航栏材质档位（开发者选项自定义映射到 hdsMaterial.MaterialLevel） */
  private hdsMaterialLevel(): hdsMaterial.MaterialLevel {
    if (this.materialLevel === 'EXQUISITE') {
      return hdsMaterial.MaterialLevel.EXQUISITE;
    }
    if (this.materialLevel === 'GENTLE') {
      return hdsMaterial.MaterialLevel.GENTLE;
    }
    if (this.materialLevel === 'SMOOTH') {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    return hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /** HDS 悬浮导航栏材质：设备支持沉浸材质时使用沉浸材质（档位取开发者选项自定义），否则跟随系统材质策略 */
  private buildHdsMaterial(): SystemMaterialParams {
    try {
      const supported: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      if (supported.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        return {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: this.hdsMaterialLevel()
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

  /** 四个页签页（HDS/悬浮/普通三种底栏共用）：TabContent 顶部安全区扩展，配合视图内顶部材质条上扩覆盖状态栏。
   * 视图置于 tabFresh 翻转分支内：每次激活已访问页签时分支互换强制重建，重播级联渐入（左右切换叠加，同图书借阅页入场）。 */
  @Builder
  tabPages() {
    TabContent() {
      if (this.tabFresh[0]) {
        HomeView()
      } else {
        HomeView()
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(0), this.tabLabels[0]))

    TabContent() {
      if (this.tabFresh[1]) {
        GradeView()
      } else {
        GradeView()
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(1), this.tabLabels[1]))

    TabContent() {
      if (this.tabFresh[2]) {
        ZcpView()
      } else {
        ZcpView()
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(2), this.tabLabels[2]))

    TabContent() {
      if (this.tabFresh[3]) {
        SelectionView()
      } else {
        SelectionView()
      }
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .tabBar(new BottomTabBarStyle(this.tabSymbol(3), this.tabLabels[3]))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 跨域会话换票用 1×1 隐藏 Web（任务 14，冷启动优化 ③ 按需挂载版）：
      // 首帧不创建 ArkWeb 实例，CrossDomainSession 首次换票时经回调置 crossHostNeeded
      // 才条件渲染 HiddenWeb；挂载后常驻整个主框架生命周期（crossHostNeeded 不复位）。
      if (this.crossHostNeeded) {
        HiddenWeb()
      }

      if (this.hdsSupported) {
        HdsNavigation() {
          if (this.supportsFloatingBar) {
            // API 26+：悬浮页签栏 + 沉浸材质 + 光效指示器（barFloatingStyle 为 26 版本属性）
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
              this.onTabSelected(index);
            })
            .barFloatingStyle({
              barWidth: {
                smallWidth: this.barWidthVp,
                mediumWidth: this.barWidthVp,
                largeWidth: this.barWidthVp
              },
              barSideMargin: BAR_SIDE_MARGIN,
              barBottomMargin: BAR_BOTTOM_MARGIN,
              lightColor: this.lightEffectColor,
              systemMaterialEffect: this.buildHdsMaterial()
            })
            .width('100%')
            .height('100%')
          } else {
            // API 26 以下：HDS 常规底栏（悬浮栏样式为高版本属性，低版本设备调用会抛异常，条件渲染规避）
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
              this.onTabSelected(index);
            })
            .width('100%')
            .height('100%')
          }
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
          this.onTabSelected(index);
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
          this.onTabSelected(index);
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
