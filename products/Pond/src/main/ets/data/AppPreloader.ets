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
 * 综评与图书借阅原本等页签/页面激活才拉取（懒加载），这里在教务数据转为
 * online（登录成功回到首页 / 启动时已有会话）时提前静默加载，使后续首次打开即时可见。
 * 每次运行至多执行一轮；失败静默——页面激活时仍走原加载流程兜底。
 */
export class AppPreloader {
  private static started: boolean = false;

  /** 触发一轮预载（幂等） */
  static preloadIfNeeded(): void {
    if (AppPreloader.started) {
      return;
    }
    AppPreloader.started = true;
    AppLog.info(DOMAIN, TAG, 'preload: start');
    AppPreloader.preloadZcp();
    AppPreloader.preloadLibrary();
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
