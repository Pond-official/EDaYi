import { fileIo as fs } from '@kit.CoreFileKit';
import { AppLog } from './AppLog';

const TAG: string = 'CacheManager';
const DOMAIN: number = 0x0000;

/**
 * 本地缓存管理：统计与清理应用 cacheDir（含网页内核缓存等）。
 * 仅操作 cache 目录，不涉及 preferences（离线缓存/卡片数据）与 Cookie。
 */
export class CacheManager {
  /** 递归统计目录大小（字节），目录不存在返回 0 */
  static dirSize(path: string): number {
    let total: number = 0;
    try {
      const stat: fs.Stat = fs.statSync(path);
      if (!stat.isDirectory()) {
        return 0;
      }
      const names: string[] = fs.listFileSync(path);
      for (const name of names) {
        const child: string = path + '/' + name;
        const childStat: fs.Stat = fs.statSync(child);
        if (childStat.isDirectory()) {
          total += CacheManager.dirSize(child);
        } else {
          total += childStat.size;
        }
      }
    } catch (error) {
      // 目录不存在或不可读，按 0 处理
    }
    return total;
  }

  /** 递归清空目录内容（保留目录本身），单个子项处理失败时跳过继续清其余项 */
  static clearDir(path: string): void {
    let names: string[] = [];
    try {
      names = fs.listFileSync(path);
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'clearDir list skip: %{public}s %{public}s', path, `${error}`);
      return;
    }
    for (const name of names) {
      const child: string = path + '/' + name;
      try {
        const childStat: fs.Stat = fs.statSync(child);
        if (childStat.isDirectory()) {
          CacheManager.clearDir(child);
          fs.rmdirSync(child);
        } else {
          fs.unlinkSync(child);
        }
      } catch (error) {
        AppLog.warn(DOMAIN, TAG, 'clearDir skip: %{public}s %{public}s', child, `${error}`);
      }
    }
  }

  /** 字节数格式化为人类可读文本（B/KB/MB） */
  static formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb: number = bytes / 1024;
    if (kb < 1024) {
      return kb.toFixed(1) + ' KB';
    }
    return (kb / 1024).toFixed(1) + ' MB';
  }

  /**
   * 原子写文本文件（B4）：先写同目录临时文件再改名（同目录 rename 原子），
   * 避免写一半进程被杀留下损坏文件；临时文件残留时下次写入会截断覆盖。
   */
  static atomicWriteText(path: string, text: string): void {
    const tmpPath: string = `${path}.tmp`;
    const file: fs.File = fs.openSync(tmpPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
    fs.renameSync(tmpPath, path);
  }
}
