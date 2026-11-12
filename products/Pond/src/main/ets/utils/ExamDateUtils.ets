const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const MS_PER_MINUTE: number = 60000;
const MS_PER_HOUR: number = 3600000;
const MS_PER_DAY: number = 86400000;
/** 旧版仅日期数据（'YYYY-MM-DD'）的补全时刻：当天 23:59，保证考试当天全天计入倒计时 */
const LEGACY_END_OF_DAY_MINUTES: number = 23 * 60 + 59;

/**
 * 期末考试时间工具：'YYYY-MM-DD HH:mm' 文本的解析、格式化与倒计时计算。
 * 时间精确到分钟；旧版 'YYYY-MM-DD' 数据视为当天 23:59（向后兼容）。
 * 倒计时规则：剩余超过一天显示整天，不足一天显示小时，到点视为已结束。
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

  /** 日期 + 时分（0-23 / 0-59）转 'YYYY-MM-DD HH:mm'（期末考试时间标准格式） */
  static toMinuteText(date: Date, hour: number, minute: number): string {
    const hourText: string = hour < 10 ? '0' + hour : `${hour}`;
    const minuteText: string = minute < 10 ? '0' + minute : `${minute}`;
    return ExamDateUtils.toYmd(date) + ' ' + hourText + ':' + minuteText;
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

  /** 'HH:mm' 解析为当日分钟数（0-1439），非法返回 -1 */
  static parseHm(timeText: string): number {
    const parts: string[] = timeText.split(':');
    if (parts.length !== 2) {
      return -1;
    }
    const hour: number = Number(parts[0]);
    const minute: number = Number(parts[1]);
    if (!Number.isInteger(hour) || !Number.isInteger(minute)
      || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return -1;
    }
    return hour * 60 + minute;
  }

  /**
   * 解析期末考试时间：
   * - 'YYYY-MM-DD HH:mm'：精确到分钟的时刻；
   * - 'YYYY-MM-DD'（旧版数据）：视为当天 23:59，考试当天全天计入倒计时。
   * 格式或日期非法返回 null。
   */
  static parseExamDate(text: string): Date | null {
    const segments: string[] = text.split(' ');
    if (segments.length === 0 || segments.length > 2) {
      return null;
    }
    const dayStart: Date | null = ExamDateUtils.parseYmd(segments[0]);
    if (dayStart === null) {
      return null;
    }
    if (segments.length === 1) {
      return new Date(dayStart.getTime() + LEGACY_END_OF_DAY_MINUTES * MS_PER_MINUTE);
    }
    const minutes: number = ExamDateUtils.parseHm(segments[1]);
    if (minutes < 0) {
      return null;
    }
    return new Date(dayStart.getTime() + minutes * MS_PER_MINUTE);
  }

  /** 目标时刻的日历日距今天数（按目标自身年月日零点计算，今天 0、未来为正、过去为负） */
  static calendarDaysFrom(target: Date): number {
    const now: Date = new Date();
    const todayStart: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const targetStart: Date = new Date(target.getFullYear(), target.getMonth(), target.getDate());
    return Math.round((targetStart.getTime() - todayStart.getTime()) / MS_PER_DAY);
  }

  /** 距目标时刻的剩余毫秒数（负数表示已到点） */
  static remainingMs(target: Date): number {
    return target.getTime() - Date.now();
  }

  /**
   * 倒计时文本：剩余超过一天显示整天（'还有X天'），
   * 不足一天显示小时（'还有X小时'，向上取整且至少 1 小时），已到点显示'已结束'。
   */
  static countdownTextOf(target: Date): string {
    const remaining: number = ExamDateUtils.remainingMs(target);
    if (remaining <= 0) {
      return '已结束';
    }
    const days: number = Math.floor(remaining / MS_PER_DAY);
    if (days >= 1) {
      return '还有' + days + '天';
    }
    const hours: number = Math.ceil(remaining / MS_PER_HOUR);
    return '还有' + hours + '小时';
  }

  /** 显示文本：'YYYY-MM-DD HH:mm' → 同年 '12月28日 周一 14:30'（跨年含年份）；
   * 旧版 'YYYY-MM-DD' → '12月28日 周一'；非法文本原样返回 */
  static formatDisplay(dateText: string): string {
    const date: Date | null = ExamDateUtils.parseExamDate(dateText);
    if (date === null) {
      return dateText;
    }
    const now: Date = new Date();
    const yearPrefix: string = date.getFullYear() === now.getFullYear() ? '' : date.getFullYear() + '年';
    const base: string =
      yearPrefix + (date.getMonth() + 1) + '月' + date.getDate() + '日 ' + WEEKDAY_NAMES[date.getDay()];
    const segments: string[] = dateText.split(' ');
    if (segments.length === 2) {
      return base + ' ' + segments[1];
    }
    return base;
  }
}
