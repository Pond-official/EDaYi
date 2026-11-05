import { hilog } from '@kit.PerformanceAnalysisKit';

/** 应用内日志条目（开发者选项日志查看用） */
export class LogEntry {
  /** 时间文本 HH:mm:ss.SSS */
  timeText: string = '';
  /** 级别缩写：D/I/W/E */
  level: string = 'I';
  /** 日志标签 */
  tag: string = '';
  /** 已格式化的日志内容 */
  message: string = '';
}

/**
 * 应用日志器：与 hilog 同签名（domain, tag, format, ...args），
 * 写入 hilog 的同时把格式化后的日志存入内存环形缓冲，
 * 供开发者选项"应用日志"实时查看与复制导出。
 */
export class AppLog {
  /** 环形缓冲最大条数 */
  private static readonly MAX_ENTRIES: number = 1000;
  /** 日志缓冲（旧→新） */
  private static entries: LogEntry[] = [];
  /** 上次通知 UI 刷新的时间戳（毫秒），节流用 */
  private static lastNotifyMs: number = 0;
  /** 是否已安排延迟刷新 */
  private static pendingNotify: boolean = false;

  static debug(domain: number, tag: string, format: string, ...args: Object[]): void {
    const message: string = AppLog.formatMessage(format, args);
    hilog.debug(domain, tag, '%{public}s', message);
    AppLog.push('D', tag, message);
  }

  static info(domain: number, tag: string, format: string, ...args: Object[]): void {
    const message: string = AppLog.formatMessage(format, args);
    hilog.info(domain, tag, '%{public}s', message);
    AppLog.push('I', tag, message);
  }

  static warn(domain: number, tag: string, format: string, ...args: Object[]): void {
    const message: string = AppLog.formatMessage(format, args);
    hilog.warn(domain, tag, '%{public}s', message);
    AppLog.push('W', tag, message);
  }

  static error(domain: number, tag: string, format: string, ...args: Object[]): void {
    const message: string = AppLog.formatMessage(format, args);
    hilog.error(domain, tag, '%{public}s', message);
    AppLog.push('E', tag, message);
  }

  /** 当前缓冲条数 */
  static count(): number {
    return AppLog.entries.length;
  }

  /** 最近日志（新→旧），limit 为返回上限 */
  static recent(limit: number): LogEntry[] {
    const n: number = Math.min(limit, AppLog.entries.length);
    const result: LogEntry[] = [];
    for (let i: number = 0; i < n; i++) {
      result.push(AppLog.entries[AppLog.entries.length - 1 - i]);
    }
    return result;
  }

  /** 全部日志文本（旧→新，时间+级别+标签+内容），供复制导出 */
  static recentText(): string {
    const lines: string[] = [];
    for (const entry of AppLog.entries) {
      lines.push(`${entry.timeText} ${entry.level}/${entry.tag}: ${entry.message}`);
    }
    return lines.join('\n');
  }

  /** 清空日志缓冲 */
  static clear(): void {
    AppLog.entries = [];
    AppLog.lastNotifyMs = Date.now();
    AppLog.doNotify();
  }

  private static push(level: string, tag: string, message: string): void {
    const entry: LogEntry = new LogEntry();
    entry.timeText = AppLog.nowText();
    entry.level = level;
    entry.tag = tag;
    entry.message = message;
    AppLog.entries.push(entry);
    if (AppLog.entries.length > AppLog.MAX_ENTRIES) {
      AppLog.entries.splice(0, AppLog.entries.length - AppLog.MAX_ENTRIES);
    }
    AppLog.notifyChanged();
  }

  /**
   * 通知日志视图刷新（通过 AppStorage 版本号，300ms 节流；
   * 节流窗口内到达的日志会安排一次延迟刷新，保证最后一条日志也会显示）。
   */
  private static notifyChanged(): void {
    const now: number = Date.now();
    if (now - AppLog.lastNotifyMs >= 300) {
      AppLog.lastNotifyMs = now;
      AppLog.doNotify();
      return;
    }
    if (!AppLog.pendingNotify) {
      AppLog.pendingNotify = true;
      setTimeout(() => {
        AppLog.pendingNotify = false;
        AppLog.lastNotifyMs = Date.now();
        AppLog.doNotify();
      }, 300);
    }
  }

  private static doNotify(): void {
    const revision: number = (AppStorage.get<number>('appLogRevision') ?? 0) + 1;
    AppStorage.setOrCreate('appLogRevision', revision);
  }

  /** 把 hilog 风格的 %{public}s/%{private}s 占位符依序替换为参数，得到可读文本 */
  private static formatMessage(format: string, args: Object[]): string {
    if (args.length === 0) {
      return format;
    }
    let result: string = '';
    let argIndex: number = 0;
    let cursor: number = 0;
    while (argIndex < args.length) {
      const start: number = format.indexOf('%{', cursor);
      if (start < 0) {
        break;
      }
      const close: number = format.indexOf('}', start + 2);
      if (close < 0 || close + 1 >= format.length) {
        break;
      }
      result += format.substring(cursor, start);
      result += `${args[argIndex]}`;
      argIndex += 1;
      cursor = close + 2;
    }
    result += format.substring(cursor);
    return result;
  }

  private static nowText(): string {
    const date: Date = new Date();
    return AppLog.pad2(date.getHours()) + ':' + AppLog.pad2(date.getMinutes()) + ':' +
      AppLog.pad2(date.getSeconds()) + '.' + AppLog.pad3(date.getMilliseconds());
  }

  private static pad2(value: number): string {
    return value < 10 ? '0' + `${value}` : `${value}`;
  }

  private static pad3(value: number): string {
    if (value < 10) {
      return '00' + `${value}`;
    }
    if (value < 100) {
      return '0' + `${value}`;
    }
    return `${value}`;
  }
}
