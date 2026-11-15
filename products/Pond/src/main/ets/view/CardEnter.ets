/**
 * 卡片转场体系：
 * - cardEnterEffect：级联上滑入场（上滑 24vp + 淡入，360ms EaseOut，按 delayMs 错峰）。
 *   路由页（图书借阅/培养计划等）每次挂载与主页签（首页/成绩/综评/选课）切换时均播放。
 * - cardFadeEffect：纯淡入淡出（250ms EaseOut），学期/筛选切换的渐变过渡，不重播上滑。
 * 调用方约定：延迟传 -1 表示不播级联，降级为 cardFadeEffect。
 */

/** 卡片级联入场：上滑 24vp + 淡入，360ms EaseOut 按 delayMs 错峰 */
export function cardEnterEffect(delayMs: number): TransitionEffect {
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: 24 }))
    .animation({ duration: 360, curve: Curve.EaseOut, delay: delayMs });
}

/** 卡片淡入淡出：250ms EaseOut（学期/筛选切换的渐变过渡） */
export function cardFadeEffect(): TransitionEffect {
  return TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut });
}
