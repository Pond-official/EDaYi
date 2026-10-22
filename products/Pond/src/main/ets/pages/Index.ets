import { BreakpointSystem } from '@ohos/common';
import { HomeView } from '../view/HomeView';
import { GradeView } from '../view/GradeView';
import { SelectionView } from '../view/SelectionView';
import { JwxtRepository } from '../data/JwxtRepository';

const CAPSULE_ITEM_WIDTH: number = 96;
const CAPSULE_ITEM_COUNT: number = 3;
const CAPSULE_INDICATOR_MAX_X: number = CAPSULE_ITEM_WIDTH * (CAPSULE_ITEM_COUNT - 1);

/**
 * 应用主框架：原生 Tabs 页签导航（首页、成绩、选课）。
 * 手机/分栏：悬浮胶囊底栏（backgroundEffect 沉浸光感，内容从栏后透出）；
 * 平板/电脑：侧边页签（vertical），三端原生自适应。
 */
@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  /** >=0 表示正在按住拖动药丸指示器（此时的 x 位置），-1 表示空闲 */
  @State dragX: number = -1;
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  tabLabels: string[] = ['首页', '成绩', '选课'];
  private tabIndices: number[] = [0, 1, 2];
  private dragStartX: number = 0;
  private readonly tabsController: TabsController = new TabsController();
  private readonly breakpointSystem: BreakpointSystem = new BreakpointSystem('mainBreakpoint');

  aboutToAppear(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      JwxtRepository.attachContext(ctx);
    }
    this.breakpointSystem.register(this.getUIContext());
    JwxtRepository.ensureLoaded();
  }

  aboutToDisappear(): void {
    this.breakpointSystem.unregister();
  }

  private isBottomBar(): boolean {
    return this.currentBreakpoint === 'sm' || this.currentBreakpoint === 'md';
  }

  private tabIcon(index: number): Resource {
    if (index === 0) {
      return $r('sys.symbol.house');
    }
    if (index === 1) {
      return $r('sys.symbol.doc_text');
    }
    return $r('sys.symbol.list_bullet');
  }

  private activeIndex(): number {
    if (this.dragX >= 0) {
      const nearest: number = Math.round(this.dragX / CAPSULE_ITEM_WIDTH);
      if (nearest < 0) {
        return 0;
      }
      if (nearest > CAPSULE_ITEM_COUNT - 1) {
        return CAPSULE_ITEM_COUNT - 1;
      }
      return nearest;
    }
    return this.currentIndex;
  }

  private isActive(index: number): boolean {
    return this.activeIndex() === index;
  }

  private activeColor(): Resource {
    return $r('sys.color.ohos_id_color_text_primary_activated');
  }

  private inactiveColor(): Resource {
    return $r('sys.color.ohos_id_color_text_secondary');
  }

  /**
   * 侧边页签项（lg 断点）。
   */
  @Builder
  tabItem(index: number) {
    Row({ space: 8 }) {
      SymbolGlyph(this.tabIcon(index))
        .fontSize(24)
        .fontColor([this.isActive(index) ? this.activeColor() : this.inactiveColor()])
      Text(this.tabLabels[index])
        .fontSize(16)
        .fontWeight(this.isActive(index) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.isActive(index) ? this.activeColor() : this.inactiveColor())
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
    .width(176)
    .height(56)
    .padding({ left: 20 })
    .borderRadius(16)
    .backgroundColor(this.isActive(index) ?
      $r('sys.color.ohos_id_color_button_normal') : Color.Transparent)
    .margin({ left: 12, right: 12, bottom: 4 })
  }

  /**
   * 悬浮胶囊底栏（sm/md 断点）：backgroundEffect 沉浸光感，
   * 内容从胶囊后透出；支持按住拖动药丸指示器跟手滑动，松手吸附最近页签。
   */
  @Builder
  capsuleBar() {
    Stack({ alignContent: Alignment.Start }) {
      Column()
        .width(CAPSULE_ITEM_WIDTH)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .margin({ left: 4, top: 4 })
        .translate({ x: this.dragX >= 0 ? this.dragX : this.currentIndex * CAPSULE_ITEM_WIDTH })
        .animation(this.dragX >= 0 ? { duration: 0 } : { duration: 250, curve: Curve.EaseInOut })
      Row() {
        ForEach(this.tabIndices, (index: number) => {
          Column({ space: 3 }) {
            SymbolGlyph(this.tabIcon(index))
              .fontSize(22)
              .fontColor([this.isActive(index) ? this.activeColor() : this.inactiveColor()])
            Text(this.tabLabels[index])
              .fontSize(11)
              .fontWeight(this.isActive(index) ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.isActive(index) ? this.activeColor() : this.inactiveColor())
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width(CAPSULE_ITEM_WIDTH)
          .height(56)
          .onClick(() => {
            if (this.currentIndex !== index) {
              this.tabsController.changeIndex(index);
            }
          })
        }, (index: number) => 'capsuleTab' + index)
      }
      .height(64)
      .padding({ left: 4, right: 4 })
    }
    .height(64)
    .borderRadius(32)
    .backgroundEffect({
      radius: 24,
      saturation: 1.05,
      brightness: 1.05,
      color: '#40FFFFFF',
      adaptiveColor: AdaptiveColor.AVERAGE
    })
    .border({ width: 0.5, color: '#1F000000' })
    .shadow({ radius: 16, color: '#1A000000', offsetX: 0, offsetY: 4 })
    .margin({ left: 32, right: 32, bottom: 16 })
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart((event: GestureEvent) => {
          this.dragStartX = this.currentIndex * CAPSULE_ITEM_WIDTH;
          this.dragX = this.dragStartX;
        })
        .onActionUpdate((event: GestureEvent) => {
          let next: number = this.dragStartX + event.offsetX;
          if (next < 0) {
            next = 0;
          }
          if (next > CAPSULE_INDICATOR_MAX_X) {
            next = CAPSULE_INDICATOR_MAX_X;
          }
          this.dragX = next;
        })
        .onActionEnd((event: GestureEvent) => {
          const nearest: number = Math.round(this.dragX / CAPSULE_ITEM_WIDTH);
          let target: number = nearest;
          if (target < 0) {
            target = 0;
          }
          if (target > CAPSULE_ITEM_COUNT - 1) {
            target = CAPSULE_ITEM_COUNT - 1;
          }
          this.dragX = -1;
          if (this.currentIndex !== target) {
            this.currentIndex = target;
            this.tabsController.changeIndex(target);
          }
        })
        .onActionCancel(() => {
          this.dragX = -1;
        })
    )
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Tabs({
        barPosition: this.isBottomBar() ? BarPosition.End : BarPosition.Start,
        controller: this.tabsController
      }) {
        TabContent() {
          HomeView()
        }
        .tabBar(this.tabItem(0))
        TabContent() {
          GradeView()
        }
        .tabBar(this.tabItem(1))
        TabContent() {
          SelectionView()
        }
        .tabBar(this.tabItem(2))
      }
      .vertical(!this.isBottomBar())
      .scrollable(false)
      .barMode(BarMode.Fixed)
      .barWidth(this.isBottomBar() ? '100%' : 200)
      .barHeight(this.isBottomBar() ? 0 : '100%')
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .animationDuration(300)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))

      if (this.isBottomBar()) {
        this.capsuleBar()
      }
    }
    .width('100%')
    .height('100%')
  }
}
