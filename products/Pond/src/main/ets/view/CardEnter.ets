/**
 * 卡片转场体系：
 * - cardEnterEffect：级联上滑入场（上滑 24vp + 淡入，360ms EaseOut，按 delayMs 错峰）。
 *   供路由页（图书借阅/培养计划等）每次挂载时播放。
 * - mainEnterEffect：主页签（首页/成绩/综评/选课）卡片入场，仅在启动窗口内播级联；
 *   窗口结束后页签切换导致的重建直接出现（TransitionEffect.IDENTITY），不重播。
 * - cardFadeEffect：纯淡入淡出（250ms EaseOut），学期/筛选切换的渐变过渡，不重播上滑。
 * 调用方约定：延迟传 -1 表示不播级联，降级为 cardFadeEffect。
 */

/** 主页签启动入场窗口是否已结束 */
let mainEnterDone: boolean = false;

/** 标记启动入场窗口结束（主框架启动后延时调用一次）：此后主页签卡片挂载不再播级联 */
export function markMainEnterDone(): void {
  mainEnterDone = true;
}

/** 卡片级联入场：上滑 24vp + 淡入，360ms EaseOut 按 delayMs 错峰 */
export function cardEnterEffect(delayMs: number): TransitionEffect {
  return TransitionEffect.OPACITY
    .combine(TransitionEffect.translate({ y: 24 }))
    .animation({ duration: 360, curve: Curve.EaseOut, delay: delayMs });
}

/** 主页签卡片入场：启动窗口内播级联，之后（页签切换重建）直接出现 */
export function mainEnterEffect(delayMs: number): TransitionEffect {
  return mainEnterDone ? TransitionEffect.IDENTITY : cardEnterEffect(delayMs);
}

/** 卡片淡入淡出：250ms EaseOut（学期/筛选切换的渐变过渡） */
export function cardFadeEffect(): TransitionEffect {
  return TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut });
}
