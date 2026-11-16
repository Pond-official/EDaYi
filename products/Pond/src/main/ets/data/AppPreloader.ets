import { AppLog } from './AppLog';
import { ZcpRepository, ZCP_SESSION_INVALID_ERROR } from './ZcpRepository';
import { ZcpResult } from '../model/ZcpModels';
import { LibraryRepository } from './LibraryRepository';
import { EhallRepository } from './EhallRepository';
import { LoanPage } from '../model/LibraryModels';
import { LIBSP_SESSION_INVALID } from '../net/LibSpTransport';
import { CrossDomainSession } from '../net/CrossDomainSession';
import { DOMAIN_LIBSP, DOMAIN_XGFW } from '../net/DomainSpec';

const TAG: string = 'AppPreloader';
const DOMAIN: number = 0x0000;
/** LibSP 令牌写入 Cookie 滞后于 onPageEnd 的轮询次数/间隔（对齐 LibraryIndex） */
const TOKEN_RETRY_COUNT: number = 6;
const TOKEN_RETRY_INTERVAL_MS: number = 500;

/**
 * 登录后预载协调器：
 * 综评、ehall 统计与图书借阅原本等页签/页面激活才拉取（懒加载），这里提前静默加载——
 * 登录确认时与教务主数据并行（返回首页仍以主数据成功为准，见 LoginIndex.syncAndReturn），
 * 冷启动已有会话时由 jwDataMode 转 online 触发（见 HomeView.onDataModeChanged）。
 * 每次运行至多执行一轮（logout 时 reset 以支持重新登录）；失败静默——页面激活时仍走原加载流程兜底。
 */
export class AppPreloader {
  private static started: boolean = false;

  /** 重置预载标记（退出登录时调用）：下次登录/上线重新预载 */
  static reset(): void {
    AppPreloader.started = false;
  }

  /** 触发一轮预载（幂等） */
  static preloadIfNeeded(): void {
    if (AppPreloader.started) {
      return;
    }
    AppPreloader.started = true;
    AppLog.info(DOMAIN, TAG, 'preload: start');
    AppPreloader.preloadEhall();
    AppPreloader.preloadZcp();
    AppPreloader.preloadLibrary();
  }

  /** 预载 ehall 统计：隐藏 Web 换票 + 校园卡余额/借阅数轮询（内部单飞去重） */
  private static async preloadEhall(): Promise<void> {
    try {
      const ok: boolean = await EhallRepository.refreshStats();
      if (!ok) {
        AppLog.warn(DOMAIN, TAG, 'preload ehall: stats not loaded');
        return;
      }
      AppLog.info(DOMAIN, TAG, 'preload ehall: ok');
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'preload ehall failed: %{public}s', `${error}`);
    }
  }

  /** 预载综评：xgfw 换票 + loadAll 写入 AppStorage；在线结果（fromCache=false）使综评页签打开即显且不重拉 */
  private static async preloadZcp(): Promise<void> {
    try {
      if (!ZcpRepository.isSessionReady()) {
        const ok: boolean = await CrossDomainSession.ensure(DOMAIN_XGFW);
        if (!ok) {
          AppLog.warn(DOMAIN, TAG, 'preload zcp: xgfw bootstrap failed');
          return;
        }
        ZcpRepository.markSessionReady();
      }
      const loaded: ZcpResult = await ZcpRepository.loadAll();
      ZcpRepository.saveCache(loaded);
      AppStorage.setOrCreate<ZcpResult>('jwZcpResult', loaded);
      AppLog.info(DOMAIN, TAG, 'preload zcp: ok');
    } catch (error) {
      const message: string = `${error}`;
      if (message.indexOf(ZCP_SESSION_INVALID_ERROR) >= 0) {
        // CAS 会话已过期：清除会话标记与跨域就绪集，综评页签激活时重新换票
        ZcpRepository.clearSession();
        CrossDomainSession.reset();
      }
      AppLog.warn(DOMAIN, TAG, 'preload zcp failed: %{public}s', message);
    }
  }

  /** 预载图书借阅：LibSP 换票建立令牌 + 在借/历史拉取 + 借阅数回写首页统计；页面进入时凭令牌直拉数据 */
  private static async preloadLibrary(): Promise<void> {
    try {
      if (!LibraryRepository.hasToken() && !LibraryRepository.bindTokenFromCookie()) {
        const ok: boolean = await CrossDomainSession.ensure(DOMAIN_LIBSP);
        if (!ok) {
          AppLog.warn(DOMAIN, TAG, 'preload library: libsp bootstrap failed');
          return;
        }
        let bound: boolean = false;
        for (let attempt = 0; attempt < TOKEN_RETRY_COUNT; attempt++) {
          if (LibraryRepository.bindTokenFromCookie()) {
            bound = true;
            break;
          }
          await AppPreloader.delay(TOKEN_RETRY_INTERVAL_MS);
        }
        if (!bound) {
          AppLog.warn(DOMAIN, TAG, 'preload library: token not bound');
          return;
        }
      }
      const loans: LoanPage = await LibraryRepository.fetchLoans();
      await LibraryRepository.fetchHistory();
      EhallRepository.updateLoanCount(loans.numFound);
      AppLog.info(DOMAIN, TAG, 'preload library: ok, loans=%{public}s', `${loans.numFound}`);
    } catch (error) {
      const message: string = `${error}`;
      if (message.indexOf(LIBSP_SESSION_INVALID) >= 0) {
        LibraryRepository.clearToken();
      }
      AppLog.warn(DOMAIN, TAG, 'preload library failed: %{public}s', message);
    }
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}
