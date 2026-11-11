import { webview } from '@kit.ArkWeb';
import { AppLog } from '../data/AppLog';
import { DomainSpec } from './DomainSpec';

const TAG: string = 'CrossDomainSession';
const DOMAIN: number = 0x0000;

/** 一次跨域引导请求（目标域 + 完成回调 + 超时定时器句柄） */
class Req {
  spec: DomainSpec;
  resolve: (ok: boolean) => void;
  timer: number;

  constructor(spec: DomainSpec, resolve: (ok: boolean) => void, timer: number) {
    this.spec = spec;
    this.resolve = resolve;
    this.timer = timer;
  }
}

/**
 * 跨域会话服务（任务 14）：全 App 唯一的隐藏 Web 换票服务。
 * 学校各系统分散在多个域名（jwxt/xgfw/ehall/jwxk），CAS 登录一次后仍需逐域「换票」；
 * 本服务借助根页面常驻的 1×1 隐藏 Web（见 pages/Index.ets）加载目标域入口页，
 * 由 WebView 完成 CAS 单点重定向链并把会话 Cookie 落入系统 Cookie 存储。
 *
 * 设计：
 * - 同一域就绪后并发 ensure 只回 true 不重跑；不同域排队串行执行；
 * - 落到 CAS 登录页（URL 含 authserver）视为教务会话过期，返回 false；
 * - 超时/主文档加载失败返回 false；
 * - 登出/会话失效必须调用 reset()，否则会把过期会话当成已就绪。
 */
export class CrossDomainSession {
  private static controller: webview.WebviewController | null = null;
  private static ready: Set<string> = new Set<string>();
  private static queue: Req[] = [];
  private static current: Req | null = null;

  /** 根页面隐藏 Web 的 controller 就绪后绑定（Index.onControllerAttached） */
  static attach(controller: webview.WebviewController): void {
    CrossDomainSession.controller = controller;
  }

  /** 该域会话是否已就绪（本进程内，reset() 前持续有效） */
  static isReady(key: string): boolean {
    return CrossDomainSession.ready.has(key);
  }

  /** 确保目标域会话可用：同一域并发只跑一次；不同域排队串行 */
  static ensure(spec: DomainSpec): Promise<boolean> {
    if (CrossDomainSession.ready.has(spec.key)) {
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const req: Req = new Req(spec, resolve, -1);
      CrossDomainSession.queue.push(req);
      CrossDomainSession.pump();
    });
  }

  private static pump(): void {
    if (CrossDomainSession.current !== null || CrossDomainSession.queue.length === 0) {
      return;
    }
    const controller: webview.WebviewController | null = CrossDomainSession.controller;
    if (controller === null) {
      CrossDomainSession.drain(false);
      return;
    }
    const req: Req | undefined = CrossDomainSession.queue.shift();
    if (req === undefined) {
      return;
    }
    AppLog.info(DOMAIN, TAG, 'bootstrap domain: %{public}s', req.spec.key);
    req.timer = setTimeout(() => {
      CrossDomainSession.settle(false);
    }, req.spec.timeoutMs);
    CrossDomainSession.current = req;
    if (!CrossDomainSession.loadQuietly(controller, req.spec.entryUrl)) {
      // loadUrl 抛出（controller 已失效等）：按失败结算，保证 Promise 不悬挂
      clearTimeout(req.timer);
      CrossDomainSession.current = null;
      AppLog.info(DOMAIN, TAG, 'loadUrl threw, domain: %{public}s -> fail', req.spec.key);
      req.resolve(false);
      CrossDomainSession.pump();
    }
  }

  /** 静默加载：loadUrl 可能抛出（controller 失效等），失败返回 false 由调用方按失败结算 */
  private static loadQuietly(controller: webview.WebviewController, url: string): boolean {
    try {
      controller.loadUrl(url);
      return true;
    } catch (error) {
      return false;
    }
  }

  /** 由根页面隐藏 Web 的 onPageEnd 调用（about:blank 收尾页由 current === null 挡掉） */
  static onPageEnd(endedUrl: string): void {
    const cur: Req | null = CrossDomainSession.current;
    if (cur === null) {
      return;
    }
    if (endedUrl.indexOf('authserver') >= 0) {
      CrossDomainSession.settle(false);
      return;
    }
    if (endedUrl.indexOf(cur.spec.host) >= 0) {
      CrossDomainSession.ready.add(cur.spec.key);
      CrossDomainSession.settle(true);
    }
  }

  /** 主文档加载失败（仅主框架）时由根页面隐藏 Web 的 onErrorReceive 调用 */
  static onError(): void {
    CrossDomainSession.settle(false);
  }

  private static settle(ok: boolean): void {
    const cur: Req | null = CrossDomainSession.current;
    if (cur === null) {
      return;
    }
    clearTimeout(cur.timer);
    CrossDomainSession.current = null;
    const controller: webview.WebviewController | null = CrossDomainSession.controller;
    if (controller !== null) {
      CrossDomainSession.loadQuietly(controller, 'about:blank');
    }
    AppLog.info(DOMAIN, TAG, 'bootstrap domain: %{public}s -> %{public}s', cur.spec.key, ok ? 'ok' : 'fail');
    cur.resolve(ok);
    CrossDomainSession.pump();
  }

  /** 无宿主 Web（controller 未 attach）时清空队列并全部按失败返回 */
  private static drain(ok: boolean): void {
    while (CrossDomainSession.queue.length > 0) {
      const r: Req | undefined = CrossDomainSession.queue.shift();
      if (r === undefined) {
        return;
      }
      r.resolve(ok);
    }
  }

  /** 登出/会话失效时必须调用，否则会把过期会话当成已就绪 */
  static reset(): void {
    CrossDomainSession.ready.clear();
  }
}
