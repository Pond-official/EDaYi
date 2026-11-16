import { webview } from '@kit.ArkWeb';
import { CrossDomainSession, HiddenWebHost } from '../net/CrossDomainSession';

/**
 * 跨域会话换票用 1×1 隐藏 Web 宿主（冷启动优化 ③）：
 * 由 Index 按需条件渲染（crossHostNeeded），CrossDomainSession 首次需要换票时
 * 才请求挂载，使 ArkWeb 模块求值、Web 实例创建与渲染进程启动移出冷启动首帧；
 * 一旦挂载即常驻主框架生命周期（crossHostNeeded 只置 true 不复位，宿主不卸载，
 * 保证 controller 稳定存活，onControllerAttached 重挂时自动重绑）。
 * 必须用 opacity(0.01) 隐藏（Visibility.None 可能导致 Web 不真正加载、onPageEnd 不触发）。
 */
@Component
export struct HiddenWeb {
  private readonly controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Web({ src: 'about:blank', controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0.01)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onControllerAttached(() => {
        CrossDomainSession.onHostAttached(new ControllerHost(this.controller));
      })
      .onPageEnd(() => {
        let endedUrl: string = '';
        try {
          endedUrl = this.controller.getUrl();
        } catch (error) {
          endedUrl = '';
        }
        CrossDomainSession.onPageEnd(endedUrl);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (event.request.isMainFrame()) {
          CrossDomainSession.onError();
        }
      })
  }
}

/** HiddenWebHost 的 controller 实现：loadUrl 可能抛出（controller 失效等），内部吞掉返回 false */
class ControllerHost implements HiddenWebHost {
  private readonly controller: webview.WebviewController;

  constructor(controller: webview.WebviewController) {
    this.controller = controller;
  }

  loadQuietly(url: string): boolean {
    try {
      this.controller.loadUrl(url);
      return true;
    } catch (error) {
      return false;
    }
  }
}
