/**
 * 卡片启动入场转场（与图书借阅页同款）：上滑 24vp + 淡入，360ms EaseOut，按 delayMs 错峰。
 * 仅在卡片首次挂载（应用启动）时自然播放；带 geometryTransition 的卡片在横竖屏
 * 布局切换时由几何转场配对接管。传 -1 表示回退为纯透明度过渡（不重播上滑）。
 */
export function cardEnterEffect(delayMs: number): TransitionEffect {
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: 24 }))
    .animation({ duration: 360, curve: Curve.EaseOut, delay: delayMs });
}
