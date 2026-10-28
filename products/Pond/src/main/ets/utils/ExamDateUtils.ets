const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const MS_PER_DAY: number = 86400000;

/**
 * 期末考试日期工具：'YYYY-MM-DD' 文本的解析、格式化与倒计时计算。
 * 日期统一按本地时区当天零点处理，倒计时按自然日差计算。
 */
export class ExamDateUtils {
  /** Date 转 'YYYY-MM-DD' */
  static toYmd(date: Date): string {
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const monthText: string = month < 10 ? '0' + month : `${month}`;
    const dayText: string = day < 10 ? '0' + day : `${day}`;
    return year + '-' + monthText + '-' + dayText;
  }

  /** 'YYYY-MM-DD' 解析为当天零点的 Date；格式或日期非法（如 2 月 30 日）返回 null */
  static parseYmd(dateText: string): Date | null {
    const parts: string[] = dateText.split('-');
    if (parts.length !== 3) {
      return null;
    }
    const year: number = Number(parts[0]);
    const month: number = Number(parts[1]);
    const day: number = Number(parts[2]);
    const date: Date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
      return null;
    }
    return date;
  }

  /** 目标日期距今天的自然日数：今天 0、未来为正、过去为负 */
  static daysFromDate(target: Date): number {
    const now: Date = new Date();
    const todayStart: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    return Math.round((target.getTime() - todayStart.getTime()) / MS_PER_DAY);
  }

  /** 显示文本：同年 '12月28日 周一'，跨年含年份 '2027年1月5日 周二'；非法日期原样返回 */
  static formatDisplay(dateText: string): string {
    const date: Date | null = ExamDateUtils.parseYmd(dateText);
    if (date === null) {
      return dateText;
    }
    const now: Date = new Date();
    const yearPrefix: string = date.getFullYear() === now.getFullYear() ? '' : date.getFullYear() + '年';
    return yearPrefix + (date.getMonth() + 1) + '月' + date.getDate() + '日 ' + WEEKDAY_NAMES[date.getDay()];
  }

  /** 倒计时文本：未来 '还有X天'、当天 '今天考试'、过去 '已结束' */
  static countdownText(days: number): string {
    if (days === 0) {
      return '今天考试';
    }
    if (days > 0) {
      return '还有' + days + '天';
    }
    return '已结束';
  }
}
