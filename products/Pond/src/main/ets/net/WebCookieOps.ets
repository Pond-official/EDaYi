import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../data/AppLog';

const TAG: string = 'WebCookieOps';
const DOMAIN: number = 0x0000;

/**
 * 全 App 唯一的 WebView Cookie 读写收口（冷启动优化 ③）：
 * webview（ArkWeb）模块只被本文件静态 import，所有数据层调用方一律
 * `import lazy { WebCookieOps }`，使 ArkWeb 模块求值与 Cookie 存储初始化
 * 移出冷启动首帧，首次 Cookie 操作时才加载（会话 Cookie 存在 WebView Cookie
 * 存储中，该加载不可避免，但由网络等待期吸收而非阻塞首帧渲染）。
 */
export class WebCookieOps {
  /** 从 WebView Cookie 存储按 URL 同步读取 Cookie；可能抛出（BusinessError），调用方自行兜底 */
  static fetchCookieSync(url: string): string {
    return webview.WebCookieManager.fetchCookieSync(url);
  }

  /** 清空全部 WebView Cookie（退出登录用）；失败仅记日志不抛出（登出流程尽力而为） */
  static clearAllCookiesSync(): void {
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLog.error(DOMAIN, TAG, 'clearAllCookiesSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
    }
  }
}
