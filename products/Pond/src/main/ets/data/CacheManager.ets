import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

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

  /** 递归清空目录内容（保留目录本身），单个文件删除失败时跳过继续 */
  static clearDir(path: string): void {
    try {
      const names: string[] = fs.listFileSync(path);
      for (const name of names) {
        const child: string = path + '/' + name;
        const childStat: fs.Stat = fs.statSync(child);
        if (childStat.isDirectory()) {
          CacheManager.clearDir(child);
          fs.rmdirSync(child);
        } else {
          fs.unlinkSync(child);
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'clearDir skip: %{public}s %{public}s', path, `${error}`);
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
}
