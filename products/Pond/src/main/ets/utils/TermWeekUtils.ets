import { ExamDateUtils } from './ExamDateUtils';

const MS_PER_DAY: number = 86400000;

/**
 * 学期教学周工具：周一锚点推算周次。
 * 教务接口仅在同步时返回当前周次（classWeek），离线缓存回放或应用跨周挂起时
 * 以最近同步时的周一锚点推算经过的整周数，本地推进周次，避免课表停留旧周。
 */
export class TermWeekUtils {
  /** date 所在周的周一（date 本身为周一时返回同日零点） */
  static mondayOf(date: Date): Date {
    const dayNum: number = date.getDay() === 0 ? 7 : date.getDay();
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() - (dayNum - 1));
  }

  /** date 所在周的周一（'YYYY-MM-DD'） */
  static mondayYmdOf(date: Date): string {
    return ExamDateUtils.toYmd(TermWeekUtils.mondayOf(date));
  }

  /**
   * 自锚点周一到 now 所在周一经过的整周数（同周为 0）。
   * 锚点缺失/格式非法/晚于 now 所在周（时钟回拨）返回 null，调用方应保持原周次。
   */
  static weeksBetween(anchorYmd: string, now: Date): number | null {
    const anchor: Date | null = ExamDateUtils.parseYmd(anchorYmd);
    if (anchor === null) {
      return null;
    }
    const nowMonday: Date = TermWeekUtils.mondayOf(now);
    const diffDays: number = Math.round((nowMonday.getTime() - anchor.getTime()) / MS_PER_DAY);
    if (diffDays < 0) {
      return null;
    }
    return Math.floor(diffDays / 7);
  }
}
