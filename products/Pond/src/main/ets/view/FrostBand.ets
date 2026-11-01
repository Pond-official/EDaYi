/** 顶部材质条高度（vp）：设置按钮区（10 上边距 + 44 按钮 + 10 下边距）所在带 */
export const FROST_BAND_HEIGHT: number = 64;

/** 内容缺省值：空顶带（选课页等无带内内容的场景） */
@Builder
function emptyBandContent() {
}

/**
 * 顶部毛玻璃遮罩：整宽顶带（状态栏避让区 + 56vp 带）。
 * 半透明 scrim（frost_band_scrim，base/dark 自适配）：滚动内容从带下穿过时透出，
 * 呈磨砂遮罩观感；带底 20% 渐变淡出到透明（frost_band_scrim_clear），
 * 与带下内容平滑衔接，无硬切边；实测当前模拟器 backgroundBlurStyle 降级为
 * 不透明乳白、backdropBlur 采到窗口外壁纸串色，两者均不可用，故仅保留 scrim；
 * 高度为「状态栏避让区 + 56vp」，通过 expandSafeArea 向上扩展绘制覆盖状态栏区域；
 * 触摸测试透传，不阻挡下层滚动手势；带内子内容（文字/按钮）仍可正常响应。
 */
@Component
export struct FrostBand {
  @BuilderParam content: () => void = emptyBandContent;
  /** 状态栏避让区高度（px），由 PondAbility 在 onWindowStageCreate 测量写入 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;

  /** 遮罩总高度（vp）：状态栏避让区 + 56vp 带 */
  private bandHeight(): number {
    return this.getUIContext().px2vp(this.safeTopPx) + FROST_BAND_HEIGHT;
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.bandHeight())
    .linearGradient({
      angle: 180,
      colors: [
        [$r('app.color.frost_band_scrim'), 0.0],
        [$r('app.color.frost_band_scrim'), 0.80],
        [$r('app.color.frost_band_scrim_clear'), 1.0]
      ]
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
