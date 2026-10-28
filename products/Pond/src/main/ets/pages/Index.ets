import { BreakpointSystem } from '@ohos/common';
import { curves, display, SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import { uiEffect } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavigation, HdsTabs, HdsTabsController, hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import { HomeView } from '../view/HomeView';
import { GradeView } from '../view/GradeView';
import { SelectionView } from '../view/SelectionView';
import { SettingsView, SettingsSubPage, PAGE_PUSH_DURATION } from '../view/SettingsView';
import { JwxtRepository } from '../data/JwxtRepository';

const TAB_COUNT: number = 4;
/** 悬浮页签栏最大宽度（宽屏基准），窄屏按屏宽收缩 */
const BAR_MAX_WIDTH: number = 392;
/** 悬浮页签栏左右留白（vp） */
const BAR_SIDE_MARGIN: number = 32;
/** 悬浮页签栏与屏幕底部边距（vp） */
const BAR_BOTTOM_MARGIN: number = 16;
/** 悬浮页签栏高度（vp） */
const BAR_HEIGHT: number = 64;
/** 液态指示器胶囊宽度（vp） */
const CAPSULE_WIDTH: number = 72;
/** 液态指示器胶囊高度（vp） */
const CAPSULE_HEIGHT: number = 40;
/** 液态指示器光晕中心色（60% 不透明度白） */
const GLOW_CENTER_COLOR: string = '#99FFFFFF';
/** 液态指示器光晕过渡色（25% 不透明度白） */
const GLOW_MID_COLOR: string = '#40FFFFFF';
/** 液态指示器光晕边缘色（18% 不透明度白）：边缘不淡出为透明，延续白色过渡与胶囊栏自然衔接 */
const GLOW_EDGE_COLOR: string = '#2EFFFFFF';
/** 液态指示器光晕半径（vp）：覆盖胶囊对角，边缘淡出为透明 */
const GLOW_RADIUS: number = 42;
/** 液态指示器光晕 HDR 提亮倍数：>1 触发 HDR 渲染管线，超出设备上限时按上限处理 */
const GLOW_HDR_BRIGHTNESS_RATIO: number = 2.0;
/** 跟手拖拽判定阈值（vp）：按下到抬起位移超过该值视为拖拽吸附，否则视为轻点 */
const DRAG_SLOP: number = 8;
/** 沉浸光感（uiMaterial/barFloatingStyle）所需系统版本：26.0.0 对应 distributionOSApiVersion 26*10000 */
const IMMERSIVE_OS_API_VERSION: number = 260000;
/** HDS 组件（UI Design Kit）系统能力标识 */
const HDS_SYSCAP: string = 'SystemCapability.UIDesign.HDSComponent.Core';
/** 设置页签索引（onBackPress 据此判断返回事件是否需要先弹回设置主页） */
const TAB_INDEX_SETTINGS: number = 3;

/**
 * 应用主框架：首页、成绩、选课、设置四个页签。
 * 底栏（HDS 版本，主路径）：
 *   build 以 Stack 为根，HdsNavigation 包裹 HdsTabs，
 *   HdsTabs 设 barFloatingStyle 悬浮导航栏样式（沉浸材质 + 光感反馈），
 *   根 Stack 内与 HdsNavigation 同级的覆盖层定位在悬浮导航栏区域、层级更高，
 *   其中放置液态指示器胶囊：一团白色光晕（胶囊大小）随选中页签或手指位置弹簧滑动、
 *   轻微回弹，支持在悬浮导航栏区域按住拖动跟手、松手就近吸附切换页签，
 *   页签图标从光晕中透出，深浅色自适应；
 *   页签栏宽度随窗口尺寸变化自动重算（横竖屏切换、折叠屏开合、分屏/悬浮窗拖动），
 *   各视图通过断点（mainBreakpoint）自动适配横竖屏布局；
 *   设备缺少 HDS 能力时降级：API 26+ 走 uiMaterial 悬浮页签栏，再退普通底栏。
 */
@Entry
@Component
struct Index {
  /** 悬浮页签栏宽度（vp），随窗口宽度自适应（启动取屏宽，运行中随区域变化重算） */
  @State barWidthVp: number = BAR_MAX_WIDTH;
  /** 当前选中页签索引，驱动液态指示器滑动 */
  @State currentTabIndex: number = 0;
  /** 液态指示器是否处于跟手状态（手指在悬浮导航栏区域按下/拖动） */
  @State indicatorDragging: boolean = false;
  /** 跟手状态下胶囊左边缘横坐标（vp） */
  @State indicatorDragX: number = 0;
  /** 触摸起始横坐标（vp），用于区分轻点与拖拽 */
  private touchStartX: number = 0;
  /** 设备是否具备 HDS 组件能力（UI Design Kit） */
  private hdsSupported: boolean = false;
  /** 当前设备是否支持悬浮页签栏 + 沉浸光感（API 26+），降级分支使用 */
  private supportsFloatingBar: boolean = false;
  /** 降级分支页签栏沉浸光感材质 */
  private barMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  /** 光晕 HDR 提亮滤镜：作用于光晕胶囊合成后的整体图像，设备不支持 HDR 时自动退回 SDR */
  private readonly hdrGlowFilter: uiEffect.Filter =
    uiEffect.createFilter().hdrBrightnessRatio(GLOW_HDR_BRIGHTNESS_RATIO);
  tabLabels: string[] = ['首页', '成绩', '选课', '设置'];
  private readonly hdsTabsController: HdsTabsController = new HdsTabsController();
  private readonly tabsController: TabsController = new TabsController();
  private readonly breakpointSystem: BreakpointSystem = new BreakpointSystem('mainBreakpoint');

  aboutToAppear(): void {
    this.breakpointSystem.register(this.getUIContext());
    this.fitBarWidth();
    this.hdsSupported = canIUse(HDS_SYSCAP);
    this.supportsFloatingBar = deviceInfo.distributionOSApiVersion >= IMMERSIVE_OS_API_VERSION;
    this.barMaterial = this.buildBarMaterial();
    JwxtRepository.ensureLoaded();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister();
  }

  /**
   * 设备返回（侧滑/返回键）：设置页签下若二级页（开发者选项/关于应用）打开，
   * 先以推入/弹出同款转场弹回设置主页并拦截本次返回；
   * 其余情况不拦截，走系统默认返回行为。
   */
  onBackPress(): boolean {
    if (this.currentTabIndex === TAB_INDEX_SETTINGS) {
      const sub: number | undefined = AppStorage.get<number>('jwSettingsSubPage');
      if (sub !== undefined && sub !== SettingsSubPage.Main) {
        this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
          AppStorage.setOrCreate<number>('jwSettingsSubPage', SettingsSubPage.Main);
        });
        return true;
      }
    }
    return false;
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
   * 根据系统沉浸光效强度（设备算力档位）自动调节降级分支页签栏材质：
   * 强（EXQUISITE）/均衡（GENTLE）档使用 REGULAR 常规材质，呈现完整沉浸光感；
   * 弱（SMOOTH）档使用 THIN 薄材质，保证流畅；
   * lightEffect 开启光感交互反馈，点击底栏时点击处呈现高光；
   * 设备不支持沉浸光感时返回 undefined，由系统使用默认页签样式。
   */
  private buildBarMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (!this.supportsFloatingBar) {
      return undefined;
    }
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        return undefined;
      }
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      const style: uiMaterial.ImmersiveStyle = level === uiMaterial.MaterialLevel.SMOOTH
        ? uiMaterial.ImmersiveStyle.THIN
        : uiMaterial.ImmersiveStyle.REGULAR;
      const light: uiMaterial.LightEffectOptions = { color: Color.White };
      return new uiMaterial.ImmersiveMaterial({
        style: style,
        lightEffect: light
      });
    } catch (error) {
      return undefined;
    }
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

  /** 液态指示器胶囊横坐标（非跟手态）：在选中页签单元格内水平居中 */
  private capsuleX(): number {
    const cellWidth: number = this.barWidthVp / TAB_COUNT;
    return this.currentTabIndex * cellWidth + (cellWidth - CAPSULE_WIDTH) / 2;
  }

  /** 限制胶囊左边缘横坐标在悬浮导航栏范围内 */
  private clampCapsuleX(x: number): number {
    const maxX: number = this.barWidthVp - CAPSULE_WIDTH;
    return Math.min(Math.max(x, 0), maxX);
  }

  /** 液态指示器胶囊实际显示横坐标：跟手态取手指位置，松手后取选中页签单元格中心 */
  private capsuleDisplayX(): number {
    if (this.indicatorDragging) {
      return this.indicatorDragX;
    }
    return this.capsuleX();
  }

  /**
   * 液态指示器跟手处理：
   * 按下/拖动时胶囊中心跟随手指横坐标（限悬浮导航栏范围内）；
   * 抬起时位移超过阈值按落点就近页签吸附并切换页签，
   * 轻点时按落点所在页签切换（与页签栏自身点击处理幂等一致）；
   * 取消（来电等打断）时胶囊弹回当前选中页签。
   */
  private onIndicatorTouch(event: TouchEvent): void {
    const cellWidth: number = this.barWidthVp / TAB_COUNT;
    if (event.type === TouchType.Down) {
      const p: TouchObject = event.touches[0];
      this.touchStartX = p.x;
      this.indicatorDragX = this.clampCapsuleX(p.x - CAPSULE_WIDTH / 2);
      this.indicatorDragging = true;
    } else if (event.type === TouchType.Move) {
      const p: TouchObject = event.touches[0];
      this.indicatorDragX = this.clampCapsuleX(p.x - CAPSULE_WIDTH / 2);
    } else if (event.type === TouchType.Up) {
      const p: TouchObject = event.changedTouches[0];
      const moved: number = Math.abs(p.x - this.touchStartX);
      // 落点所在页签：按单元格边界（0/98/196/294…）取整，与页签栏原生点击区域一致；
      // 若取 round 会把边界挪到单元格中心，导致中间页签判定范围侵入相邻页签
      const target: number = Math.min(TAB_COUNT - 1, Math.max(0, Math.floor(p.x / cellWidth)));
      this.indicatorDragging = false;
      if (moved > DRAG_SLOP || target !== this.currentTabIndex) {
        this.currentTabIndex = target;
        this.hdsTabsController.changeIndex(target);
      }
    } else if (event.type === TouchType.Cancel) {
      this.indicatorDragging = false;
    }
  }

  private tabIcon(index: number): Resource {
    if (index === 0) {
      return $r('sys.symbol.house');
    }
    if (index === 1) {
      return $r('sys.symbol.doc_text');
    }
    if (index === 2) {
      return $r('sys.symbol.list_bullet');
    }
    return $r('sys.symbol.gearshape');
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

  /** 四个页签页（HDS/悬浮/普通三种底栏共用） */
  @Builder
  tabPages() {
    TabContent() {
      HomeView()
    }
    .tabBar(new BottomTabBarStyle(this.tabSymbol(0), this.tabLabels[0]))

    TabContent() {
      GradeView()
    }
    .tabBar(new BottomTabBarStyle(this.tabSymbol(1), this.tabLabels[1]))

    TabContent() {
      SelectionView()
    }
    .tabBar(new BottomTabBarStyle(this.tabSymbol(2), this.tabLabels[2]))

    TabContent() {
      SettingsView()
    }
    .tabBar(new BottomTabBarStyle(this.tabSymbol(3), this.tabLabels[3]))
  }

  /**
   * 液态指示器：定位在悬浮导航栏区域、层级高于 HdsTabs 的覆盖层。
   * 一团白色光晕（径向渐变：中心亮，向边缘延续白色过渡、不淡出为透明，
   * 边缘保留微弱白色与胶囊栏颜色自然衔接），胶囊大小，圆角与胶囊外形一致，
   * 随选中页签或手指位置以弹簧曲线滑动（轻微回弹形成液态质感）；
   * 底栏整体不降低不透明度，页签文字始终保持清晰；
   * 覆盖层默认触摸测试：自身接收触摸实现跟手，不阻断下层页签栏的原生点击。
   */
  @Builder
  liquidIndicator() {
    Stack() {
      Column()
        .width(CAPSULE_WIDTH)
        .height(CAPSULE_HEIGHT)
        .borderRadius(CAPSULE_HEIGHT / 2)
        .radialGradient({
          center: [CAPSULE_WIDTH / 2, CAPSULE_HEIGHT / 2],
          radius: GLOW_RADIUS,
          colors: [
            [GLOW_CENTER_COLOR, 0.0],
            [GLOW_MID_COLOR, 0.5],
            [GLOW_EDGE_COLOR, 1.0]
          ]
        })
        .position({ x: this.capsuleDisplayX(), y: (BAR_HEIGHT - CAPSULE_HEIGHT) / 2 })
        .animation({ curve: curves.springMotion(0.32, 0.82) })
        .compositingFilter(this.hdrGlowFilter)
    }
    .width(this.barWidthVp)
    .height(BAR_HEIGHT)
    .margin({ bottom: BAR_BOTTOM_MARGIN })
    .onTouch((event: TouchEvent) => {
      this.onIndicatorTouch(event);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.hdsSupported) {
        HdsNavigation() {
          HdsTabs({ controller: this.hdsTabsController }) {
            this.tabPages()
          }
          .barPosition(BarPosition.End)
          .vertical(false)
          .scrollable(false)
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
        .width('100%')
        .height('100%')

        this.liquidIndicator()
      } else if (this.supportsFloatingBar) {
        Tabs({
          barPosition: BarPosition.End,
          controller: this.tabsController
        }) {
          this.tabPages()
        }
        .barOverlap(true)
        .vertical(false)
        .scrollable(false)
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
        .scrollable(false)
        .barHeight(BAR_HEIGHT)
        .animationDuration(300)
        .onSelected((index: number) => {
          this.currentTabIndex = index;
        })
        .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      if (typeof newArea.width === 'number') {
        this.fitBarWidthTo(newArea.width);
      }
    })
  }
}
