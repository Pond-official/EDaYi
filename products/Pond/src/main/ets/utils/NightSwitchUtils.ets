/**
 * 2*4 课表小卡"晚间显示明日课程"到点切换的取时工具（纯函数，边界由本地单测覆盖）：
 * 卡片刷新链路（CardDataStore.scheduleNightRefresh）用其计算
 * formProvider.setFormNextRefreshTime 的预约分钟数，到点由系统准点触发刷新。
 */
export class NightSwitchUtils {
  /** formProvider.setFormNextRefreshTime 可预约的最小分钟数（低于该值预约无效） */
  static readonly MIN_SCHEDULE_MINUTES: number = 5;

  /**
   * 距下一个"晚间显示明日课程"到点时刻的毫秒数：
   * 今日到点未过取今日同刻；已过（含恰好到点，此时数据端已按明日构建）取明日同刻。
   * @param now 当前时刻
   * @param nightMinutes 每天开始默认展示明日课程的时刻（当日分钟数，0-1439）
   */
  static nextSwitchDelayMs(now: Date, nightMinutes: number): number {
    const target: Date = new Date(now.getTime());
    target.setHours(Math.floor(nightMinutes / 60), nightMinutes % 60, 0, 0);
    if (target.getTime() <= now.getTime()) {
      target.setDate(target.getDate() + 1);
    }
    return target.getTime() - now.getTime();
  }

  /**
   * 把毫秒间隔换算为 setFormNextRefreshTime 的预约分钟数：
   * 向上取整保证不早于到点时刻触发，不足预约下限（5 分钟）时按下限约（晚几分钟仍当日切换）。
   */
  static toScheduleMinutes(deltaMs: number): number {
    return Math.max(NightSwitchUtils.MIN_SCHEDULE_MINUTES, Math.ceil(deltaMs / 60000));
  }
}
