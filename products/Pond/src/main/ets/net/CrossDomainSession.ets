import { AppLog } from '../data/AppLog';
import { DomainSpec } from './DomainSpec';

const TAG: string = 'CrossDomainSession';
const DOMAIN: number = 0x0000;
/** 请求隐藏 Web 宿主挂载后的等待上限：超时按失败清空队列，保证 Promise 不悬挂 */
const HOST_WAIT_TIMEOUT_MS: number = 10000;

/** 隐藏 Web 宿主接口：只暴露静默加载能力，避免本模块依赖 webview 类型（冷启动优化 ③） */
export interface HiddenWebHost {
  /** 静默加载 URL；失败（controller 失效等）返回 false */
  loadQuietly(url: string): boolean;
}

/** 一次跨域引导请求（目标域 + 完成回调 + 超时定时器句柄） */
class Req {
  spec: DomainSpec;
  resolve: (ok: boolean) => void;
  timer: number;
  /** 已进入门户预热阶段：onPageEnd/onError 不再收尾，由 warmupTimer 到点结算 */
  warming: boolean = false;
  warmupTimer: number = -1;
  /** 已被 reset() 取消：迟到的定时器/回调据此 no-op，不再回写 ready 或结算 */
  cancelled: boolean = false;

  constructor(spec: DomainSpec, resolve: (ok: boolean) => void, timer: number) {
    this.spec = spec;
    this.resolve = resolve;
    this.timer = timer;
  }
}

/**
 * 跨域会话服务（任务 14）：全 App 唯一的隐藏 Web 换票服务。
 * 学校各系统分散在多个域名（jwxt/xgfw/ehall/jwxk），CAS 登录一次后仍需逐域「换票」；
 * 本服务借助根页面按需挂载的 1×1 隐藏 Web（见 view/HiddenWeb.ets 与 pages/Index.ets）
 * 加载目标域入口页，由 WebView 完成 CAS 单点重定向链并把会话 Cookie 落入系统 Cookie 存储。
 *
 * 设计（冷启动优化 ③ 起）：
 * - 本模块零 webview 依赖，宿主通过 HiddenWebHost 接口注入；
 * - 宿主未挂载时由 setHostRequestCallback 注册的回调请求根页面条件渲染 HiddenWeb，
 *   到点（HOST_WAIT_TIMEOUT_MS）未挂载则排队请求全部按失败返回；
 * - 同一域就绪后并发 ensure 只回 true 不重跑；不同域排队串行执行；
 * - 落到 CAS 登录页（URL 含 authserver）视为教务会话过期，返回 false；
 * - 超时/主文档加载失败返回 false；
 * - 登出/会话失效必须调用 reset()，否则会把过期会话当成已就绪。
 */
export class CrossDomainSession {
  private static host: HiddenWebHost | null = null;
  /** 宿主已 attach 且初始页面加载完成（onPageEnd 首次触发）才置 true：
   * controller attach 时初始 about:blank 仍在加载，此时 loadUrl 会被静默吞掉，
   * 排队请求将空转到超时，必须等 onHostReady 信号后才真正发起加载 */
  private static hostReady: boolean = false;
  private static hostRequestCallback: (() => void) | null = null;
  /** 已向宿主页请求挂载隐藏 Web（防重复请求；挂载成功或等待超时后复位） */
  private static hostRequested: boolean = false;
  private static hostWaitTimer: number = -1;
  private static ready: Set<string> = new Set<string>();
  private static queue: Req[] = [];
  private static current: Req | null = null;

  /** 根页面注册「需要挂载隐藏 Web」回调（Index.aboutToAppear，置 crossHostNeeded） */
  static setHostRequestCallback(callback: () => void): void {
    CrossDomainSession.hostRequestCallback = callback;
  }

  /** 隐藏 Web 宿主 controller 就绪后绑定（HiddenWeb.onControllerAttached）；
   * 此时初始 about:blank 仍在加载，loadUrl 会被吞掉，pump 等 onHostReady 才发起 */
  static onHostAttached(host: HiddenWebHost): void {
    CrossDomainSession.host = host;
    CrossDomainSession.hostReady = false;
    AppLog.info(DOMAIN, TAG, 'hidden web host attached');
  }

  /** 隐藏 Web 宿主真正可用（首个页面加载完成）后由 HiddenWeb.onPageEnd 调用，才开始排队请求的拉取 */
  static onHostReady(): void {
    if (CrossDomainSession.hostWaitTimer >= 0) {
      clearTimeout(CrossDomainSession.hostWaitTimer);
      CrossDomainSession.hostWaitTimer = -1;
    }
    CrossDomainSession.hostRequested = false;
    if (!CrossDomainSession.hostReady) {
      CrossDomainSession.hostReady = true;
      AppLog.info(DOMAIN, TAG, 'hidden web host ready');
    }
    CrossDomainSession.pump();
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
    const host: HiddenWebHost | null = CrossDomainSession.host;
    if (host === null) {
      // 宿主尚未挂载：请求根页面条件渲染 HiddenWeb，等 onHostAttached/onHostReady 后重新 pump
      CrossDomainSession.requestHost();
      return;
    }
    if (!CrossDomainSession.hostReady) {
      // 宿主已 attach 但初始 about:blank 未加载完：此刻 loadUrl 会被静默吞掉，等 onHostReady 再拉
      return;
    }
    const req: Req | undefined = CrossDomainSession.queue.shift();
    if (req === undefined) {
      return;
    }
    // B5：排队期间该域可能已被其他请求引导完成（settle 后 ready 已就位），直接兑现不重复引导
    if (CrossDomainSession.ready.has(req.spec.key)) {
      AppLog.info(DOMAIN, TAG, 'queue hit ready, domain: %{public}s -> ok', req.spec.key);
      req.resolve(true);
      CrossDomainSession.pump();
      return;
    }
    AppLog.info(DOMAIN, TAG, 'bootstrap domain: %{public}s', req.spec.key);
    req.timer = setTimeout(() => {
      CrossDomainSession.settle(false);
    }, req.spec.timeoutMs);
    CrossDomainSession.current = req;
    if (!host.loadQuietly(req.spec.entryUrl)) {
      // loadUrl 抛出（controller 已失效等）：按失败结算，保证 Promise 不悬挂
      clearTimeout(req.timer);
      CrossDomainSession.current = null;
      AppLog.info(DOMAIN, TAG, 'loadUrl threw, domain: %{public}s -> fail', req.spec.key);
      req.resolve(false);
      CrossDomainSession.pump();
    }
  }

  /** 请求根页面挂载隐藏 Web 宿主（防重复请求；超时未挂载则清空队列全部按失败返回） */
  private static requestHost(): void {
    if (CrossDomainSession.hostRequested) {
      return;
    }
    CrossDomainSession.hostRequested = true;
    if (CrossDomainSession.hostWaitTimer >= 0) {
      clearTimeout(CrossDomainSession.hostWaitTimer);
    }
    CrossDomainSession.hostWaitTimer = setTimeout(() => {
      CrossDomainSession.hostWaitTimer = -1;
      CrossDomainSession.hostRequested = false;
      AppLog.error(DOMAIN, TAG, 'hidden web host not ready in %{public}dms, drain queue', `${HOST_WAIT_TIMEOUT_MS}`);
      CrossDomainSession.drain(false);
    }, HOST_WAIT_TIMEOUT_MS);
    const callback: (() => void) | null = CrossDomainSession.hostRequestCallback;
    if (callback !== null) {
      AppLog.info(DOMAIN, TAG, 'request hidden web host mount');
      callback();
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
      const host: HiddenWebHost | null = CrossDomainSession.host;
      if (host === null || !host.loadQuietly(cur.spec.warmupUrl)) {
        // 无宿主或加载失败：会话已建立，按成功收尾（预热是尽力而为）
        CrossDomainSession.ready.add(cur.spec.key);
        CrossDomainSession.settle(true);
        return;
      }
      AppLog.info(DOMAIN, TAG, 'warmup start: %{public}s dwell=%{public}dms', cur.spec.key, `${cur.spec.warmupMs}`);
      cur.warmupTimer = setTimeout(() => {
        if (cur.cancelled) {
          return;
        }
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
    if (cur === null || cur.cancelled) {
      return;
    }
    clearTimeout(cur.timer);
    if (cur.warmupTimer >= 0) {
      clearTimeout(cur.warmupTimer);
      cur.warmupTimer = -1;
    }
    CrossDomainSession.current = null;
    const host: HiddenWebHost | null = CrossDomainSession.host;
    if (host !== null) {
      host.loadQuietly('about:blank');
    }
    AppLog.info(DOMAIN, TAG, 'bootstrap domain: %{public}s -> %{public}s', cur.spec.key, ok ? 'ok' : 'fail');
    cur.resolve(ok);
    CrossDomainSession.pump();
  }

  /** 无宿主 Web 等待超时时清空队列并全部按失败返回 */
  private static drain(ok: boolean): void {
    while (CrossDomainSession.queue.length > 0) {
      const r: Req | undefined = CrossDomainSession.queue.shift();
      if (r === undefined) {
        return;
      }
      r.resolve(ok);
    }
  }

  /** 登出/会话失效时必须调用，否则会把过期会话当成已就绪；同时在途/排队请求全部标记取消并按失败返回 */
  static reset(): void {
    CrossDomainSession.ready.clear();
    const cur: Req | null = CrossDomainSession.current;
    if (cur !== null) {
      // 取消在途请求：清超时/预热定时器，防止迟到回调把已清空的 ready 键复活
      cur.cancelled = true;
      clearTimeout(cur.timer);
      if (cur.warmupTimer >= 0) {
        clearTimeout(cur.warmupTimer);
        cur.warmupTimer = -1;
      }
      CrossDomainSession.current = null;
      cur.resolve(false);
    }
    while (CrossDomainSession.queue.length > 0) {
      const r: Req | undefined = CrossDomainSession.queue.shift();
      if (r === undefined) {
        return;
      }
      r.cancelled = true;
      r.resolve(false);
    }
  }

  /** 失效单个域的就绪标记（如图书馆 JWT 过期需重新换票，但不影响其他域） */
  static invalidate(key: string): void {
    CrossDomainSession.ready.delete(key);
  }
}
