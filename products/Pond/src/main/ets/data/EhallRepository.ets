import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from './AppLog';
import { CrossDomainSession } from '../net/CrossDomainSession';
import { DOMAIN_EHALL } from '../net/DomainSpec';
import { getContext } from '../net/JwTransport';

/** ehall 门户根地址 */
const EHALL_BASE: string = 'https://ehall.dmu.edu.cn';
/** ehall「个人数据」聚合卡片端点（一个 endpoint 靠 method 区分动作） */
const EHALL_PERSONAL_CARD_PATH: string = '/execCardMethod/3829011985752059/SYS_CARD_PERSONALDATA';
/** 「校园卡余额」条目 wid（固定常量，可直接调 detail 不必先 list） */
const EHALL_WID_BALANCE: string = '1155858142346043392';
/** 「图书借阅（数量）」条目 wid（固定常量） */
const EHALL_WID_LOAN_COUNT: string = '1155080232673755136';
/** WAF 要求完整合法桌面 Chrome UA，必须含 (KHTML, like Gecko) */
const EHALL_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
const TAG: string = 'EhallRepository';
const DOMAIN: number = 0x0000;
/** needRetrieve 条目轮询次数/间隔：ehall 服务端聚合上游数据需数秒，data:null 时重试 */
const EHALL_RETRIEVE_ATTEMPTS: number = 6;
const EHALL_RETRIEVE_INTERVAL_MS: number = 1500;

/** ehall 会话失效标记：响应为 CAS 登录页 HTML 时抛出，据此重新走隐藏 Web 换票 */
export const EHALL_SESSION_INVALID: string = 'EHALL_SESSION_INVALID';

/** ehall 个人数据卡片请求体（getPersonalDataList / getPersonalDataDetail 共用结构） */
interface EhallCardRequest {
  cardId: string;
  cardWid: string;
  method: string;
  param: EhallCardParam;
  /** 防缓存随机数，任意浮点字符串 */
  n: string;
}

interface EhallCardParam {
  wid: string;
  extraInfo: string;
  lang: string;
  platformType: number;
}

/** ehall 统一响应：errcode 为字符串，"0" 即成功 */
interface EhallEnvelopeRaw {
  errcode?: string;
  errmsg?: string;
  data?: EhallPersonalDataRaw;
}

/** ehall 个人数据条目清单响应（data 为数组） */
interface EhallListEnvelopeRaw {
  errcode?: string;
  errmsg?: string;
  data?: EhallPersonalDataRaw[] | null;
}

/** 个人数据条目（getPersonalDataDetail 的 data 节点） */
interface EhallPersonalDataRaw {
  wid?: string;
  title?: string;
  /** 中文拼好的展示串（如「余额：10.38」「借阅数量：0」），取值需按前缀切 */
  mainInfo?: string | null;
  subInfo?: string | null;
  originalMainInfo?: string;
  accessTime?: string;
}

/** 首页统计本地缓存 JSON 结构（filesDir/ehall_stats.json，仅标准隐私模式写入） */
interface EhallStatsCacheRaw {
  balance?: string;
  loanCount?: number;
}

/**
 * ehall 门户数据仓库（首页学生卡统计）：
 * 校园卡余额与图书借阅数量在 ehall「个人数据」卡片内服务端聚合
 * （浏览器侧看不到一卡通/图书馆上游请求），一个端点按 method/wid 取值；
 * 会话为 ehall 门户 Cookie，由全 App 唯一的隐藏 Web（CrossDomainSession）
 * 加载 ehall 首页经 CAS 单点建立；
 * mainInfo 是中文拼好的字符串，取值按前缀切；
 * ehall 侧有缓存，accessTime 为 UTC，不保证实时。
 * 数据保留在内存（AppStorage jwEcardBalance / jwLoanCount）；
 * 标准隐私模式下另写 filesDir 本地缓存（离线回放），
 * 限制/严格隐私模式收紧与退出登录时连同本地缓存一并清除；
 * 标准隐私模式退出登录仅失效会话标记，缓存与页面数据保留。
 */
export class EhallRepository {
  /** ehall 门户会话是否已建立（隐藏 Web 换票完成） */
  private static sessionReady: boolean = false;
  private static lastCookie: string = '';
  /** 在途统计加载（单飞：并发调用共享同一次拉取） */
  private static currentLoad: Promise<boolean> | null = null;

  static isSessionReady(): boolean {
    return EhallRepository.sessionReady;
  }

  /** 隐藏 Web 换票完成后标记会话可用 */
  static markSessionReady(): void {
    EhallRepository.sessionReady = true;
  }

  /** 清除会话标记与内存数据（限制/严格隐私模式退出登录、隐私收紧时调用） */
  static clearSession(): void {
    EhallRepository.sessionReady = false;
    EhallRepository.lastCookie = '';
    EhallRepository.clearMemory();
  }

  /**
   * 仅失效会话标记与本地 Cookie（标准隐私模式退出登录时调用）：
   * Cookie 已随教务登出清空，ehall 会话必然失效；
   * 内存数据与 filesDir 本地缓存保留，页面继续显示离线数据。
   */
  static invalidateSession(): void {
    EhallRepository.sessionReady = false;
    EhallRepository.lastCookie = '';
  }

  /** 仅清内存数据（保留会话标记） */
  static clearMemory(): void {
    AppStorage.setOrCreate<string>('jwEcardBalance', '');
    AppStorage.setOrCreate<number>('jwLoanCount', -1);
  }

  /**
   * 首页统计加载入口（HomeView 启动/回前台时调用）：
   * AppStorage 尚无数据时先回放本地缓存（离线先显示），
   * 已连接教务系统（online）时在线刷新。
   */
  static ensureStatsLoaded(): void {
    if ((AppStorage.get<number>('jwLoanCount') ?? -1) < 0) {
      EhallRepository.applyCache();
    }
    if ((AppStorage.get<string>('jwDataMode') ?? 'preview') === 'online') {
      EhallRepository.refreshStats();
    }
  }

  /** 在线刷新余额与借阅数量（单飞；会话未建立时先走隐藏 Web 换票） */
  static refreshStats(): Promise<boolean> {
    if (EhallRepository.currentLoad !== null) {
      return EhallRepository.currentLoad;
    }
    const load: Promise<boolean> = EhallRepository.runStatsLoad(false);
    EhallRepository.currentLoad = load;
    load.then((ok: boolean) => {
      EhallRepository.currentLoad = null;
    });
    return load;
  }

  private static async runStatsLoad(retried: boolean): Promise<boolean> {
    if (!EhallRepository.sessionReady) {
      const ok: boolean = await CrossDomainSession.ensure(DOMAIN_EHALL);
      if (!ok) {
        AppLog.warn(DOMAIN, TAG, 'ehall bootstrap failed, stats not loaded');
        return false;
      }
      EhallRepository.sessionReady = true;
    }
    try {
      // wid 疑似按用户生成：先取本账号条目清单按标题解析 wid，失败回退内置常量
      let balanceWid: string = EHALL_WID_BALANCE;
      let loanCountWid: string = EHALL_WID_LOAN_COUNT;
      try {
        const entries: EhallPersonalDataRaw[] = await EhallRepository.fetchCardList();
        for (const entry of entries) {
          if (entry.title === '校园卡余额' && (entry.wid ?? '').length > 0) {
            balanceWid = entry.wid ?? balanceWid;
          }
          if (entry.title === '图书借阅' && (entry.wid ?? '').length > 0) {
            loanCountWid = entry.wid ?? loanCountWid;
          }
        }
        AppLog.info(DOMAIN, TAG, 'card wids resolved: balance=%{public}s loans=%{public}s',
          balanceWid, loanCountWid);
      } catch (listError) {
        AppLog.warn(DOMAIN, TAG, 'card list failed, fallback to builtin wids: %{public}s', `${listError}`);
      }
      // needRetrieve=1 的条目要等 ehall 服务端聚合上游（一卡通/图书馆）完成，
      // 首次 detail 常返回 data:null，轮询重试直到出值
      const balance: string =
        await EhallRepository.fetchMainInfoUntilReady(balanceWid, EHALL_RETRIEVE_ATTEMPTS);
      const balanceText: string = EhallRepository.parseValueText(balance);
      if (balanceText.length === 0) {
        throw new Error('余额数据解析失败');
      }
      const countInfo: string =
        await EhallRepository.fetchMainInfoUntilReady(loanCountWid, EHALL_RETRIEVE_ATTEMPTS);
      const loanCount: number = EhallRepository.parseCount(countInfo);
      AppStorage.setOrCreate<string>('jwEcardBalance', balanceText);
      AppStorage.setOrCreate<number>('jwLoanCount', loanCount);
      EhallRepository.saveCache(balanceText, loanCount);
      AppLog.info(DOMAIN, TAG, 'stats ok: balance=%{public}s loans=%{public}d', balanceText, loanCount);
      return true;
    } catch (error) {
      const message: string = `${error}`;
      if (message.indexOf(EHALL_SESSION_INVALID) >= 0) {
        // 会话失效：清标记并失效跨域就绪集；首次失效自动重换票重试一次
        EhallRepository.invalidateSession();
        CrossDomainSession.invalidate(DOMAIN_EHALL.key);
        if (!retried) {
          return EhallRepository.runStatsLoad(true);
        }
      }
      AppLog.error(DOMAIN, TAG, 'stats load failed: %{public}s', message);
      return false;
    }
  }

  /** 从 WebView Cookie 存储同步 ehall 会话 Cookie，失败时回退上次成功值 */
  private static syncCookie(): string {
    let cookie: string = '';
    try {
      cookie = webview.WebCookieManager.fetchCookieSync(EHALL_BASE + '/');
      EhallRepository.lastCookie = cookie;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
      cookie = EhallRepository.lastCookie;
    }
    return cookie;
  }

  /**
   * getPersonalDataDetail：按 wid 取单条聚合值；
   * needRetrieve 条目在服务端聚合完成前返回 data:null（mainInfo 空串），
   * 按 attempts 轮询重试直到出值；非 200、CAS 登录页 HTML 或 errcode != "0" 抛错。
   */
  private static async fetchMainInfoUntilReady(wid: string, attempts: number): Promise<string> {
    let mainInfo: string = '';
    for (let attempt = 0; attempt < attempts; attempt++) {
      mainInfo = await EhallRepository.fetchMainInfo(wid);
      if (mainInfo.length > 0) {
        return mainInfo;
      }
      AppLog.info(DOMAIN, TAG, 'fetchMainInfo not ready, retry=%{public}d/%{public}d wid=%{public}s',
        `${attempt + 1}`, `${attempts}`, wid);
      await EhallRepository.delay(EHALL_RETRIEVE_INTERVAL_MS);
    }
    return mainInfo;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: (value: void) => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /**
   * getPersonalDataDetail：按 wid 取单条聚合值；
   * 非 200、响应为 CAS 登录页 HTML（authserver）或 errcode != "0" 抛错。
   */
  private static async fetchMainInfo(wid: string): Promise<string> {
    const text: string = await EhallRepository.postCard('getPersonalDataDetail', wid);
    const envelope: EhallEnvelopeRaw = JSON.parse(text) as EhallEnvelopeRaw;
    if (envelope.errcode !== '0') {
      throw new Error(envelope.errmsg ?? 'ehall 接口返回失败');
    }
    return envelope.data?.mainInfo ?? '';
  }

  /**
   * getPersonalDataList：取当前用户个人数据条目清单（含各条目 wid）；
   * wid 疑似按用户生成（跨账号硬编码 wid 的 detail 返回 data:null），
   * 详情调用前先按标题解析本账号的 wid，失败时调用方回退内置常量。
   */
  static async fetchCardList(): Promise<EhallPersonalDataRaw[]> {
    const text: string = await EhallRepository.postCard('getPersonalDataList', '');
    const envelope: EhallListEnvelopeRaw = JSON.parse(text) as EhallListEnvelopeRaw;
    if (envelope.errcode !== '0') {
      throw new Error(envelope.errmsg ?? 'ehall 接口返回失败');
    }
    return envelope.data ?? [];
  }

  /** execCardMethod 通用 POST：返回响应原文；非 200 或 CAS 登录页 HTML 抛错 */
  private static async postCard(method: string, wid: string): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const request: EhallCardRequest = {
        cardId: 'SYS_CARD_PERSONALDATA',
        cardWid: '3829011985752059',
        method: method,
        param: { wid: wid, extraInfo: '', lang: 'zh_CN', platformType: 0 },
        n: '0.' + Math.floor(Math.random() * 1000000000)
      };
      const header: Record<string, string> = {
        'User-Agent': EHALL_UA,
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': EHALL_BASE + '/'
      };
      const cookie: string = EhallRepository.syncCookie();
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        extraData: JSON.stringify(request),
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      };
      const response: http.HttpResponse = await client.request(EHALL_BASE + EHALL_PERSONAL_CARD_PATH, options);
      if (response.responseCode !== 200) {
        AppLog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s method=%{public}s wid=%{public}s',
          `${response.responseCode}`, EHALL_PERSONAL_CARD_PATH, method, wid);
        throw new Error('HTTP ' + response.responseCode);
      }
      let text: string = '';
      if (typeof response.result === 'string') {
        text = response.result;
      }
      if (text.indexOf('authserver') >= 0) {
        AppLog.warn(DOMAIN, TAG, 'cas login page returned, ehall session invalid, method=%{public}s', method);
        throw new Error(EHALL_SESSION_INVALID);
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  /** 从 mainInfo 中文串取「：」后的值文本（如「余额：10.38」→「10.38」；无冒号返回原文） */
  static parseValueText(mainInfo: string): string {
    const index: number = mainInfo.indexOf('：');
    const text: string = index >= 0 ? mainInfo.substring(index + 1) : mainInfo;
    return text.trim();
  }

  /** 从 mainInfo 中文串取数量（如「借阅数量：0」→ 0；解析失败返回 -1） */
  static parseCount(mainInfo: string): number {
    const text: string = EhallRepository.parseValueText(mainInfo);
    if (text.length === 0) {
      return -1;
    }
    const parsed: number = Number.parseInt(text, 10);
    return Number.isNaN(parsed) ? -1 : parsed;
  }

  /** 本地缓存文件路径（应用级 filesDir，持久保存）；未注入上下文时返回空串 */
  private static cacheFilePath(): string {
    const context: common.UIAbilityContext | null = getContext();
    if (context === null) {
      return '';
    }
    return context.getApplicationContext().filesDir + '/ehall_stats.json';
  }

  /** 当前隐私模式是否允许统计缓存（仅标准模式） */
  private static cacheAllowed(): boolean {
    return (AppStorage.get<string>('jwPrivacyMode') ?? 'standard') === 'standard';
  }

  /** 在线获取成功后写本地缓存（仅标准隐私模式；失败不阻塞展示） */
  static saveCache(balance: string, loanCount: number): void {
    if (!EhallRepository.cacheAllowed()) {
      return;
    }
    const path: string = EhallRepository.cacheFilePath();
    if (path.length === 0) {
      return;
    }
    try {
      const raw: EhallStatsCacheRaw = { balance: balance, loanCount: loanCount };
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(raw));
      fs.closeSync(file);
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'saveCache failed: %{public}s', `${error}`);
    }
  }

  /** 回放本地缓存到 AppStorage（离线先显示）；无缓存/隐私受限时不写入 */
  static applyCache(): void {
    const raw: EhallStatsCacheRaw | null = EhallRepository.loadCache();
    if (raw === null) {
      return;
    }
    AppStorage.setOrCreate<string>('jwEcardBalance', raw.balance ?? '');
    AppStorage.setOrCreate<number>('jwLoanCount', raw.loanCount ?? -1);
  }

  /** 读取本地缓存；无缓存/解析失败/隐私受限返回 null */
  static loadCache(): EhallStatsCacheRaw | null {
    if (!EhallRepository.cacheAllowed()) {
      return null;
    }
    const path: string = EhallRepository.cacheFilePath();
    if (path.length === 0) {
      return null;
    }
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      return JSON.parse(fs.readTextSync(path)) as EhallStatsCacheRaw;
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'loadCache failed: %{public}s', `${error}`);
      return null;
    }
  }

  /** 本地缓存文件大小（字节，供"清理缓存"统计；不存在返回 0） */
  static cacheSizeBytes(): number {
    const path: string = EhallRepository.cacheFilePath();
    if (path.length === 0) {
      return 0;
    }
    try {
      if (fs.accessSync(path)) {
        return fs.statSync(path).size;
      }
    } catch (error) {
      // 按不存在处理
    }
    return 0;
  }

  /** 清除本地缓存文件（隐私收紧/退出登录/清理缓存时调用） */
  static clearCache(): void {
    const path: string = EhallRepository.cacheFilePath();
    if (path.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // 文件不存在或删除失败按已清除处理
    }
  }

  /** 图书馆借阅数量更新（详情页加载成功后同步刷新首页统计，保持两处一致） */
  static updateLoanCount(loanCount: number): void {
    AppStorage.setOrCreate<number>('jwLoanCount', loanCount);
    const cached: EhallStatsCacheRaw | null = EhallRepository.loadCache();
    if (cached !== null) {
      EhallRepository.saveCache(cached.balance ?? '', loanCount);
    }
  }
}
