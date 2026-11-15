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
  /** 已进入门户预热阶段：onPageEnd/onError 不再收尾，由 warmupTimer 到点结算 */
  warming: boolean = false;
  warmupTimer: number = -1;

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

  /**
   * 取 URL 的 host 部分（不含端口/路径/查询参数），非 http(s) URL 返回空串。
   * 引导完成判定必须用本方法做 host 全等比较：
   * 不能用 indexOf(host) —— libsp 入口 URL 的 refer 查询参数里就含目标域字符串，
   * 会把 chaoxing 入口页误判为已完成，提前 about:blank 杀掉 SSO 重定向链。
   */
  private static urlHost(url: string): string {
    const schemeEnd: number = url.indexOf('://');
    if (schemeEnd < 0) {
      return '';
    }
    const hostStart: number = schemeEnd + 3;
    let hostEnd: number = url.indexOf('/', hostStart);
    if (hostEnd < 0) {
      hostEnd = url.length;
    }
    let host: string = url.substring(hostStart, hostEnd);
    const portIndex: number = host.indexOf(':');
    if (portIndex >= 0) {
      host = host.substring(0, portIndex);
    }
    return host;
  }

  /** 由根页面隐藏 Web 的 onPageEnd 调用（about:blank 收尾页由 current === null 挡掉） */
  static onPageEnd(endedUrl: string): void {
    const cur: Req | null = CrossDomainSession.current;
    if (cur === null) {
      return;
    }
    AppLog.info(DOMAIN, TAG, 'page end: %{public}s', endedUrl);
    if (endedUrl.indexOf('authserver') >= 0) {
      CrossDomainSession.settle(false);
      return;
    }
    if (CrossDomainSession.urlHost(endedUrl) === cur.spec.host) {
      if (cur.spec.warmupUrl.length === 0) {
        CrossDomainSession.ready.add(cur.spec.key);
        CrossDomainSession.settle(true);
        return;
      }
      if (cur.warming) {
        // 预热页加载完成：停留期内由 warmupTimer 到点收尾
        return;
      }
      // 换票链已落到目标域：进入门户预热（加载门户页停留 warmupMs，让页面 JS 触发服务端数据聚合）
      cur.warming = true;
      clearTimeout(cur.timer);
      const controller: webview.WebviewController | null = CrossDomainSession.controller;
      if (controller === null || !CrossDomainSession.loadQuietly(controller, cur.spec.warmupUrl)) {
        // 无宿主或加载失败：会话已建立，按成功收尾（预热是尽力而为）
        CrossDomainSession.ready.add(cur.spec.key);
        CrossDomainSession.settle(true);
        return;
      }
      AppLog.info(DOMAIN, TAG, 'warmup start: %{public}s dwell=%{public}dms', cur.spec.key, `${cur.spec.warmupMs}`);
      cur.warmupTimer = setTimeout(() => {
        CrossDomainSession.ready.add(cur.spec.key);
        CrossDomainSession.settle(true);
      }, cur.spec.warmupMs);
    }
  }

  /** 主文档加载失败（仅主框架）时由根页面隐藏 Web 的 onErrorReceive 调用 */
  static onError(): void {
    const cur: Req | null = CrossDomainSession.current;
    if (cur !== null && cur.warming) {
      // 预热期门户页主文档失败不致命：会话已建立，等待 warmupTimer 收尾
      return;
    }
    CrossDomainSession.settle(false);
  }

  private static settle(ok: boolean): void {
    const cur: Req | null = CrossDomainSession.current;
    if (cur === null) {
      return;
    }
    clearTimeout(cur.timer);
    if (cur.warmupTimer >= 0) {
      clearTimeout(cur.warmupTimer);
      cur.warmupTimer = -1;
    }
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

  /** 失效单个域的就绪标记（如图书馆 JWT 过期需重新换票，但不影响其他域） */
  static invalidate(key: string): void {
    CrossDomainSession.ready.delete(key);
  }
}
