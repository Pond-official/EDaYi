import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ZcpContext, ZcpDetailItem, ZcpIndicator, ZcpProcessState, ZcpResult } from '../model/ZcpModels';

/** 学生综合服务门户域名 */
const XG_BASE: string = 'https://xgfw.dmu.edu.cn';
/** 综合测评报表应用基址 */
const ZCP_APP_BASE: string = XG_BASE + '/xsfw/sys/zhcptybbapp';
/** 页面入口（综测得分页 #/zcdf 所在外壳） */
const ZCP_INDEX_URL: string = ZCP_APP_BASE + '/*default/index.do';
/** xgfw 系统级接口基址（角色切换等跨应用接口） */
const XG_SYS_BASE: string = XG_BASE + '/xsfw/sys';
/** 学生组角色 RoleID（查询综评必须切换到该角色） */
const ZCP_ROLE_STUDENT: string = 'd8e99cba2c4d431abfb950e6734d9522';
/** WAF 要求完整合法桌面 Chrome UA，必须含 (KHTML, like Gecko) */
const ZCP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
const ZCP_FORM_CONTENT_TYPE: string = 'application/x-www-form-urlencoded; charset=UTF-8';
const TAG: string = 'ZcpRepository';
const DOMAIN: number = 0x0000;

/** 会话失效标记：响应为 CAS 登录页 HTML 时抛出，界面据此重新走 Web 单点引导 */
export const ZCP_SESSION_INVALID_ERROR: string = 'ZCP_SESSION_INVALID';

/** EMAP .do 接口统一信封：data 承载业务数据（对象或数组） */
interface ZcpEnvelopeRaw<T> {
  data?: T;
}

/** getPageInitParams → data（批次上下文 + 页面开关） */
interface ZcpInitDataRaw {
  ZHCP_SZ?: ZcpCtxRaw;
  /** 是否在学生测评时间内（服务端开关） */
  IS_XSCPSJ?: boolean;
  /** 综合测评是否开启 */
  IS_SFBKCP?: boolean;
  IS_NEW_STUDENT?: boolean;
}

/** 批次上下文（ZHCP_SZ） */
interface ZcpCtxRaw {
  CPXN?: string;
  CPXQ?: string;
  PCDM?: string;
  CPXN_DISPLAY?: string;
  CPXQ_DISPLAY?: string;
  ZBKMC?: string;
  DXMC?: string;
  XSKSSJ?: string;
  XSJSSJ?: string;
  XZKSSJ?: string;
  XZJSSJ?: string;
}

/** getEvaluationProcess → data */
interface ZcpProcessDataRaw {
  PERSONAL_RESULT?: ZcpPersonalRaw;
}

interface ZcpPersonalRaw {
  STATE?: string;
  SHZT_DISPLAY?: string;
  THYY?: string;
}

/** 指标条目（getAllZbList / get23zbScore 同形） */
interface ZcpZbItemRaw {
  ZBDM?: string;
  ZBMC?: string;
  ZBLB_DISPLAY?: string;
  /** 占比 %（字符串或数字，实测以字符串为主） */
  BL?: string | number;
  /** 分值上限（附加项为 999 兜底） */
  ZDZ?: string | number;
  LS?: string;
  PX?: string | number;
  CJ?: string | number;
  FS?: string | number;
  GDFS?: string | number;
  FJFTGFS?: string | number;
  FJFFS?: string | number;
  ZBSM?: string;
}

/** getZbFjfDetail → data[] 条目 */
interface ZcpFjfDetailRaw {
  FJFMX?: ZcpFjfItemRaw[];
}

/** 本地缓存 JSON 结构（filesDir/zcp_cache.json，仅标准隐私模式写入） */
interface ZcpContextCacheRaw {
  cpxn?: string;
  cpxq?: string;
  pcdm?: string;
  termDisplay?: string;
  batchName?: string;
  targetName?: string;
  fillWindow?: string;
  auditWindow?: string;
  windowOpen?: boolean;
}

interface ZcpProcessCacheRaw {
  state?: number;
  statusText?: string;
  rejectReason?: string;
}

interface ZcpIndicatorCacheRaw {
  zbdm?: string;
  name?: string;
  category?: string;
  parentCode?: string;
  level?: number;
  order?: number;
  scoreText?: string;
  ratioPercent?: string;
  capText?: string;
  fixedScore?: string;
  extraGained?: string;
  extraApplied?: string;
  note?: string;
  children?: ZcpIndicatorCacheRaw[];
}

interface ZcpResultCacheRaw {
  context?: ZcpContextCacheRaw;
  hasContext?: boolean;
  process?: ZcpProcessCacheRaw;
  indicators?: ZcpIndicatorCacheRaw[];
}

interface ZcpFjfItemRaw {
  JXMC?: string;
  MXFS?: string;
  FJFMC?: string;
  MXSM?: string;
  SHZT_DISPLAY?: string;
  FJFSM?: string;
}

/**
 * 综评（综合测评）数据仓库：
 * xgfw 域会话由视图层隐藏 Web 组件加载页面入口（CAS 单点）建立，
 * Cookie 落入 WebCookieManager 后由本仓库手动携带发起原生 HTTP 请求；
 * 业务接口均为 POST，表单体只含 data=<urlencoded JSON>；
 * 首次业务调用前必须完成两步角色切换（changeAppRole + setXgCommonAppRole）到学生组，
 * 否则 getPageInitParams 返回 403 框架权限页。
 * 数据保留在内存（AppStorage）；标准隐私模式下另写 filesDir 本地缓存（登录失效时回放），
 * 文件置于 filesDir 持久保存（cacheDir 可能被系统回收导致回放数据丢失）；
 * 限制/严格隐私模式退出登录、隐私模式收紧与清理缓存时连同本地缓存一并清除，
 * 标准隐私模式退出登录仅失效会话标记，缓存与页面数据保留。
 * 仅调用只读 get* 接口，不调用任何测评写入接口。
 */
export class ZcpRepository {
  /** Web 单点引导是否已完成（会话 Cookie 已落入 WebView 存储） */
  private static sessionReady: boolean = false;
  private static lastCookie: string = '';
  private static appContext: common.UIAbilityContext | null = null;

  /** 注入主 Ability 上下文（PondAbility 启动时调用），用于综评本地缓存读写 */
  static attachContext(context: common.UIAbilityContext): void {
    ZcpRepository.appContext = context;
    ZcpRepository.migrateLegacyCache();
  }

  /** 一次性迁移旧版 cacheDir 缓存到 filesDir（缓存路径升级，避免存量回放数据丢失） */
  private static migrateLegacyCache(): void {
    const context: common.UIAbilityContext | null = ZcpRepository.appContext;
    if (context === null) {
      return;
    }
    try {
      const newPath: string = context.getApplicationContext().filesDir + '/zcp_cache.json';
      const legacyPath: string = context.getApplicationContext().cacheDir + '/zcp_cache.json';
      if (fs.accessSync(newPath) || !fs.accessSync(legacyPath)) {
        return;
      }
      const raw: string = fs.readTextSync(legacyPath);
      const file: fs.File = fs.openSync(newPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, raw);
      fs.closeSync(file);
      fs.unlinkSync(legacyPath);
      hilog.info(DOMAIN, TAG, 'zcp cache migrated from cacheDir to filesDir');
    } catch (error) {
      // 迁移失败保持现状，下次在线获取成功后写入新路径
    }
  }

  /** 页面入口 URL（隐藏 Web 单点引导的加载地址） */
  static indexUrl(): string {
    return ZCP_INDEX_URL;
  }

  static isSessionReady(): boolean {
    return ZcpRepository.sessionReady;
  }

  /** Web 单点引导完成后标记会话可用 */
  static markSessionReady(): void {
    ZcpRepository.sessionReady = true;
    hilog.info(DOMAIN, TAG, 'session ready (web sso done)');
  }

  /** 清除会话标记与内存数据（限制/严格隐私模式退出登录、严格隐私清理、会话失效时调用） */
  static clearSession(): void {
    ZcpRepository.sessionReady = false;
    ZcpRepository.lastCookie = '';
    ZcpRepository.clearMemory();
  }

  /**
   * 仅失效会话标记与本地 Cookie（标准隐私模式退出登录时调用）：
   * Cookie 已随教务登出清空，xgfw 会话必然失效；
   * 内存数据与 filesDir 本地缓存保留，页面继续显示离线数据。
   */
  static invalidateSession(): void {
    ZcpRepository.sessionReady = false;
    ZcpRepository.lastCookie = '';
  }

  /** 仅清内存数据（保留会话标记，重进页签后可直接在线重拉） */
  static clearMemory(): void {
    AppStorage.setOrCreate<ZcpResult | null>('jwZcpResult', null);
  }

  /** 从 WebView Cookie 存储按请求 URL（域名+路径）同步 xgfw 会话 Cookie，失败时回退上次成功值 */
  private static syncCookie(url: string): string {
    let cookie: string = '';
    try {
      cookie = webview.WebCookieManager.fetchCookieSync(url);
      ZcpRepository.lastCookie = cookie;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
      cookie = ZcpRepository.lastCookie;
    }
    return cookie;
  }

  /**
   * 统一 POST：按接口要求携带桌面 UA/XHR/Origin/Referer 头与 xgfw 会话 Cookie；
   * 非 200 或响应为 CAS 登录页 HTML（authserver）时抛错；
   * 空表单体不设置 extraData（空串会被 http 栈判定 Parameter error）。
   */
  private static async postForm(url: string, form: string): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': ZCP_UA,
        'Accept': '*/*',
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': ZCP_FORM_CONTENT_TYPE,
        'Referer': ZCP_INDEX_URL,
        'Origin': XG_BASE
      };
      const cookie: string = ZcpRepository.syncCookie(url);
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      };
      if (form.length > 0) {
        options.extraData = form;
      }
      const response: http.HttpResponse = await client.request(url, options);
      if (response.responseCode !== 200) {
        hilog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s', `${response.responseCode}`, url);
        throw new Error('HTTP ' + `${response.responseCode}` + '（角色或会话异常，请稍后重试）');
      }
      let text: string = '';
      if (typeof response.result === 'string') {
        text = response.result;
      }
      if (text.indexOf('authserver') >= 0) {
        hilog.warn(DOMAIN, TAG, 'cas login page returned, session invalid, len=%{public}s', `${text.length}`);
        throw new Error(ZCP_SESSION_INVALID_ERROR);
      }
      return text;
    } finally {
      client.destroy();
    }
  }

  /** 业务接口：体固定为 data=<urlencoded JSON>；controllerPath 已含前缀差异（New 控制器不带 modules/） */
  private static async postData(controllerPath: string, payload: Record<string, string>): Promise<string> {
    const body: string = 'data=' + encodeURIComponent(JSON.stringify(payload));
    return ZcpRepository.postForm(ZCP_APP_BASE + '/' + controllerPath, body);
  }

  /** 两步角色切换到学生组（第一步改会话活动角色，第二步落库） */
  private static async switchRole(): Promise<void> {
    const url1: string = XG_SYS_BASE + '/funauthapp/api/changeAppRole/zhcptybbapp/' + ZCP_ROLE_STUDENT + '.do';
    const text1: string = await ZcpRepository.postForm(url1, '');
    if (text1.indexOf('"success":true') < 0) {
      hilog.warn(DOMAIN, TAG, 'changeAppRole not confirmed: len=%{public}s', `${text1.length}`);
      throw new Error('角色切换未生效，请稍后重试');
    }
    const body2: string = 'requestParamStr=' + encodeURIComponent('{"ROLEID":"' + ZCP_ROLE_STUDENT + '"}');
    const url2: string = XG_SYS_BASE + '/swpubapp/userinfo/setXgCommonAppRole.do';
    const text2: string = await ZcpRepository.postForm(url2, body2);
    if (text2.indexOf('#E000000000000') < 0) {
      hilog.warn(DOMAIN, TAG, 'setXgCommonAppRole not confirmed: len=%{public}s', `${text2.length}`);
      throw new Error('角色切换未生效，请稍后重试');
    }
    hilog.info(DOMAIN, TAG, 'role switched to student');
  }

  /**
   * 拉取综评全量数据：角色切换 → 批次上下文 → 测评状态 → 指标树 → 二级得分回填。
   * 无批次上下文（未开放/无参评资格）时返回 hasContext=false 的空结果。
   */
  static async loadAll(): Promise<ZcpResult> {
    await ZcpRepository.switchRole();

    const emptyPayload: Record<string, string> = {};
    const initText: string =
      await ZcpRepository.postData('evaluationApplyNewController/getPageInitParams.do', emptyPayload);
    const initEnvelope: ZcpEnvelopeRaw<ZcpInitDataRaw> = JSON.parse(initText) as ZcpEnvelopeRaw<ZcpInitDataRaw>;
    const initData: ZcpInitDataRaw | undefined = initEnvelope.data;

    const result: ZcpResult = new ZcpResult();
    const ctxRaw: ZcpCtxRaw | undefined = initData?.ZHCP_SZ;
    if (ctxRaw !== undefined && (ctxRaw.PCDM ?? '').length > 0) {
      const ctx: ZcpContext = new ZcpContext();
      ctx.cpxn = ctxRaw.CPXN ?? '';
      ctx.cpxq = ctxRaw.CPXQ ?? '';
      ctx.pcdm = ctxRaw.PCDM ?? '';
      ctx.termDisplay = (ctxRaw.CPXN_DISPLAY ?? '') + (ctxRaw.CPXQ_DISPLAY ?? '');
      ctx.batchName = ctxRaw.ZBKMC ?? '';
      ctx.targetName = ctxRaw.DXMC ?? '';
      ctx.fillWindow = ZcpRepository.windowText(ctxRaw.XSKSSJ, ctxRaw.XSJSSJ);
      ctx.auditWindow = ZcpRepository.windowText(ctxRaw.XZKSSJ, ctxRaw.XZJSSJ);
      ctx.windowOpen = initData?.IS_XSCPSJ === true;
      result.context = ctx;
      result.hasContext = true;
    }
    if (!result.hasContext) {
      hilog.warn(DOMAIN, TAG, 'no ZHCP_SZ context, evaluation not available');
      return result;
    }

    const pcdm: string = result.context.pcdm;
    const processPayload: Record<string, string> = {};
    processPayload['CPXN'] = result.context.cpxn;
    processPayload['CPXQ'] = result.context.cpxq;
    processPayload['PCDM'] = pcdm;
    try {
      const processText: string =
        await ZcpRepository.postData('evaluationApplyNewController/getEvaluationProcess.do', processPayload);
      const processEnvelope: ZcpEnvelopeRaw<ZcpProcessDataRaw> =
        JSON.parse(processText) as ZcpEnvelopeRaw<ZcpProcessDataRaw>;
      const personal: ZcpPersonalRaw | undefined = processEnvelope.data?.PERSONAL_RESULT;
      if (personal !== undefined) {
        result.process.state = ZcpRepository.toNumber(personal.STATE);
        result.process.statusText = personal.SHZT_DISPLAY ?? '';
        result.process.rejectReason = personal.THYY ?? '';
      }
    } catch (processError) {
      // 状态接口失败不阻塞指标树展示
      hilog.warn(DOMAIN, TAG, 'getEvaluationProcess failed: %{public}s', `${processError}`);
    }

    const listPayload: Record<string, string> = {};
    listPayload['PCDM'] = pcdm;
    const listText: string =
      await ZcpRepository.postData('evaluationApplyNewController/getAllZbList.do', listPayload);
    const listEnvelope: ZcpEnvelopeRaw<ZcpZbItemRaw[]> = JSON.parse(listText) as ZcpEnvelopeRaw<ZcpZbItemRaw[]>;
    const items: ZcpZbItemRaw[] = listEnvelope.data ?? [];
    const flat: ZcpIndicator[] = ZcpRepository.buildTree(items, result.indicators);
    hilog.info(DOMAIN, TAG, 'indicators: %{public}s raw -> %{public}s roots', `${items.length}`, `${flat.length}`);

    const rootZbdm: string = ZcpRepository.findScoreRoot(items);
    if (rootZbdm.length > 0) {
      try {
        const scorePayload: Record<string, string> = {};
        scorePayload['ZBDM'] = rootZbdm;
        const scoreText: string =
          await ZcpRepository.postData('evaluationApplyNewController/get23zbScore.do', scorePayload);
        const scoreEnvelope: ZcpEnvelopeRaw<ZcpZbItemRaw[]> =
          JSON.parse(scoreText) as ZcpEnvelopeRaw<ZcpZbItemRaw[]>;
        ZcpRepository.mergeScores(flat, scoreEnvelope.data ?? []);
      } catch (scoreError) {
        // 得分接口失败时指标树仍展示（FS 为空），不阻塞
        hilog.warn(DOMAIN, TAG, 'get23zbScore failed: %{public}s', `${scoreError}`);
      }
    }
    return result;
  }

  /** 附加分明细（附加项指标点击展开时拉取），无明细时返回空数组 */
  static async fetchDetail(zbdm: string): Promise<ZcpDetailItem[]> {
    const payload: Record<string, string> = {};
    payload['ZBDM'] = zbdm;
    const text: string = await ZcpRepository.postData('modules/selfEvaluation/getZbFjfDetail.do', payload);
    const envelope: ZcpEnvelopeRaw<ZcpFjfDetailRaw[]> = JSON.parse(text) as ZcpEnvelopeRaw<ZcpFjfDetailRaw[]>;
    const rows: ZcpFjfDetailRaw[] = envelope.data ?? [];
    const list: ZcpDetailItem[] = [];
    for (const row of rows) {
      const items: ZcpFjfItemRaw[] | undefined = row.FJFMX;
      if (items === undefined) {
        continue;
      }
      for (const item of items) {
        const detail: ZcpDetailItem = new ZcpDetailItem();
        detail.name = item.JXMC ?? '';
        detail.score = item.MXFS ?? '';
        detail.category = item.FJFMC ?? '';
        detail.note = item.MXSM ?? '';
        detail.status = item.SHZT_DISPLAY ?? '';
        detail.rule = item.FJFSM ?? '';
        list.push(detail);
      }
    }
    hilog.info(DOMAIN, TAG, 'fjf detail %{public}s: %{public}s items', zbdm, `${list.length}`);
    return list;
  }

  /** 本地缓存文件路径（应用级 filesDir，持久保存，系统不会自动回收）；未注入上下文时返回空串 */
  private static cacheFilePath(): string {
    const context: common.UIAbilityContext | null = ZcpRepository.appContext;
    if (context === null) {
      return '';
    }
    return context.getApplicationContext().filesDir + '/zcp_cache.json';
  }

  /** 本地缓存文件大小（字节，供"清理缓存"页面统计；不存在或无法读取返回 0） */
  static cacheSizeBytes(): number {
    if (ZcpRepository.appContext === null) {
      return 0;
    }
    try {
      const path: string = ZcpRepository.cacheFilePath();
      if (path.length > 0 && fs.accessSync(path)) {
        return fs.statSync(path).size;
      }
    } catch (error) {
      // 按不存在处理
    }
    return 0;
  }

  /** 当前隐私模式是否允许综评临时缓存（仅标准模式） */
  private static cacheAllowed(): boolean {
    return (AppStorage.get<string>('jwPrivacyMode') ?? 'standard') === 'standard';
  }

  /** 在线获取成功后写入临时缓存（仅标准隐私模式；失败不阻塞在线数据展示） */
  static saveCache(result: ZcpResult): void {
    if (ZcpRepository.appContext === null || !ZcpRepository.cacheAllowed()) {
      return;
    }
    try {
      const path: string = ZcpRepository.cacheFilePath();
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(result));
      fs.closeSync(file);
      hilog.info(DOMAIN, TAG, 'zcp cache saved');
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'saveCache failed: %{public}s', `${error}`);
    }
  }

  /** 读取临时缓存重建结果（恢复类实例以保留方法），无缓存/解析失败/隐私受限返回 null */
  static loadCache(): ZcpResult | null {
    if (ZcpRepository.appContext === null || !ZcpRepository.cacheAllowed()) {
      return null;
    }
    try {
      const path: string = ZcpRepository.cacheFilePath();
      if (!fs.accessSync(path)) {
        return null;
      }
      const raw: ZcpResultCacheRaw = JSON.parse(fs.readTextSync(path)) as ZcpResultCacheRaw;
      const result: ZcpResult = new ZcpResult();
      const ctxRaw: ZcpContextCacheRaw | undefined = raw.context;
      if (ctxRaw !== undefined) {
        result.context.cpxn = ctxRaw.cpxn ?? '';
        result.context.cpxq = ctxRaw.cpxq ?? '';
        result.context.pcdm = ctxRaw.pcdm ?? '';
        result.context.termDisplay = ctxRaw.termDisplay ?? '';
        result.context.batchName = ctxRaw.batchName ?? '';
        result.context.targetName = ctxRaw.targetName ?? '';
        result.context.fillWindow = ctxRaw.fillWindow ?? '';
        result.context.auditWindow = ctxRaw.auditWindow ?? '';
        result.context.windowOpen = ctxRaw.windowOpen ?? false;
      }
      result.hasContext = raw.hasContext ?? false;
      const procRaw: ZcpProcessCacheRaw | undefined = raw.process;
      if (procRaw !== undefined) {
        result.process.state = procRaw.state ?? 0;
        result.process.statusText = procRaw.statusText ?? '';
        result.process.rejectReason = procRaw.rejectReason ?? '';
      }
      const listRaw: ZcpIndicatorCacheRaw[] | undefined = raw.indicators;
      if (listRaw !== undefined) {
        for (const item of listRaw) {
          result.indicators.push(ZcpRepository.cacheIndicator(item));
        }
      }
      result.fromCache = true;
      return result;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'loadCache failed: %{public}s', `${error}`);
      return null;
    }
  }

  /** 递归重建缓存指标节点 */
  private static cacheIndicator(raw: ZcpIndicatorCacheRaw): ZcpIndicator {
    const indicator: ZcpIndicator = new ZcpIndicator();
    indicator.zbdm = raw.zbdm ?? '';
    indicator.name = raw.name ?? '';
    indicator.category = raw.category ?? '';
    indicator.parentCode = raw.parentCode ?? '';
    indicator.level = raw.level ?? 0;
    indicator.order = raw.order ?? 0;
    indicator.scoreText = raw.scoreText ?? '';
    indicator.ratioPercent = raw.ratioPercent ?? '';
    indicator.capText = raw.capText ?? '';
    indicator.fixedScore = raw.fixedScore ?? '';
    indicator.extraGained = raw.extraGained ?? '';
    indicator.extraApplied = raw.extraApplied ?? '';
    indicator.note = raw.note ?? '';
    const children: ZcpIndicatorCacheRaw[] | undefined = raw.children;
    if (children !== undefined) {
      for (const child of children) {
        indicator.children.push(ZcpRepository.cacheIndicator(child));
      }
    }
    return indicator;
  }

  /** 清除临时缓存文件（限制/严格隐私模式退出登录、隐私模式收紧、清理缓存时调用） */
  static clearCache(): void {
    if (ZcpRepository.appContext === null) {
      return;
    }
    try {
      const path: string = ZcpRepository.cacheFilePath();
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
      hilog.info(DOMAIN, TAG, 'zcp cache cleared');
    } catch (error) {
      // 文件不存在或删除失败按已清除处理
    }
  }

  /** 扁平指标数组组树（LS 父指针，实测最深 3 层），填充 roots 并返回全量平铺列表（引用相同，便于回填） */
  private static buildTree(items: ZcpZbItemRaw[], roots: ZcpIndicator[]): ZcpIndicator[] {
    const byCode: Map<string, ZcpIndicator> = new Map();
    const flat: ZcpIndicator[] = [];
    for (const item of items) {
      const zbdm: string = item.ZBDM ?? '';
      if (zbdm.length === 0) {
        continue;
      }
      const indicator: ZcpIndicator = ZcpRepository.toIndicator(item);
      flat.push(indicator);
      byCode.set(zbdm, indicator);
    }
    for (const indicator of flat) {
      const parent: ZcpIndicator | undefined =
        indicator.parentCode.length > 0 ? byCode.get(indicator.parentCode) : undefined;
      if (parent !== undefined && parent !== indicator) {
        parent.children.push(indicator);
      } else {
        roots.push(indicator);
      }
    }
    ZcpRepository.sortChildren(roots);
    // 「学期平均分」为成绩分根节点（无子项、非评定指标），不在综评页展示
    for (let i: number = roots.length - 1; i >= 0; i--) {
      if (roots[i].name === '学期平均分') {
        roots.splice(i, 1);
      }
    }
    return flat;
  }

  /** 按同层排序（PX）递归排序指标树 */
  private static sortChildren(items: ZcpIndicator[]): void {
    items.sort((a: ZcpIndicator, b: ZcpIndicator): number => a.order - b.order);
    for (const item of items) {
      if (item.children.length > 0) {
        ZcpRepository.sortChildren(item.children);
      }
    }
  }

  private static toIndicator(item: ZcpZbItemRaw): ZcpIndicator {
    const indicator: ZcpIndicator = new ZcpIndicator();
    indicator.zbdm = item.ZBDM ?? '';
    indicator.name = item.ZBMC ?? '';
    indicator.category = item.ZBLB_DISPLAY ?? '';
    indicator.parentCode = item.LS ?? '';
    indicator.level = ZcpRepository.toNumber(item.CJ);
    indicator.order = ZcpRepository.toNumber(item.PX);
    indicator.scoreText = ZcpRepository.toText(item.FS);
    indicator.ratioPercent = ZcpRepository.toText(item.BL);
    indicator.capText = ZcpRepository.toText(item.ZDZ);
    indicator.fixedScore = ZcpRepository.toText(item.GDFS);
    indicator.extraGained = ZcpRepository.toText(item.FJFTGFS);
    indicator.extraApplied = ZcpRepository.toText(item.FJFFS);
    indicator.note = item.ZBSM ?? '';
    return indicator;
  }

  /**
   * 得分查询的根指标：由二级指标的 LS 反推（「综合素质」为二级的父级），
   * 退化时取 PX 最靠前的 CJ=1 项；取错根会返回空数组。
   */
  private static findScoreRoot(items: ZcpZbItemRaw[]): string {
    for (const item of items) {
      if (ZcpRepository.toNumber(item.CJ) === 2 && (item.LS ?? '').length > 0) {
        return item.LS ?? '';
      }
    }
    let fallbackCode: string = '';
    let fallbackOrder: number = Number.MAX_SAFE_INTEGER;
    for (const item of items) {
      if (ZcpRepository.toNumber(item.CJ) !== 1) {
        continue;
      }
      const order: number = ZcpRepository.toNumber(item.PX);
      if (order < fallbackOrder) {
        fallbackOrder = order;
        fallbackCode = item.ZBDM ?? '';
      }
    }
    return fallbackCode;
  }

  /** 把 get23zbScore 返回的得分/附加分回填进指标树（平铺列表与树节点为同一引用） */
  private static mergeScores(flat: ZcpIndicator[], items: ZcpZbItemRaw[]): void {
    const byCode: Map<string, ZcpIndicator> = new Map();
    for (const indicator of flat) {
      byCode.set(indicator.zbdm, indicator);
    }
    let merged: number = 0;
    for (const item of items) {
      const zbdm: string = item.ZBDM ?? '';
      const indicator: ZcpIndicator | undefined = byCode.get(zbdm);
      if (indicator === undefined) {
        continue;
      }
      indicator.scoreText = ZcpRepository.toText(item.FS);
      indicator.fixedScore = ZcpRepository.toText(item.GDFS);
      indicator.extraGained = ZcpRepository.toText(item.FJFTGFS);
      indicator.extraApplied = ZcpRepository.toText(item.FJFFS);
      merged++;
    }
    hilog.info(DOMAIN, TAG, 'scores merged: %{public}s / %{public}s', `${merged}`, `${items.length}`);
  }

  /** 时间窗文本：起止任一为空返回空串，否则 `起 ~ 止` */
  private static windowText(begin?: string, end?: string): string {
    const b: string = begin ?? '';
    const e: string = end ?? '';
    if (b.length === 0 || e.length === 0) {
      return '';
    }
    return b + ' ~ ' + e;
  }

  /** 宽容归一化服务端字段（字符串/数字/null 均可），null 与缺失返回空串 */
  private static toText(value?: string | number): string {
    if (value === undefined || value === null) {
      return '';
    }
    return `${value}`;
  }

  /** 宽容数字解析：解析失败或 null 返回 0 */
  private static toNumber(value?: string | number): number {
    if (value === undefined || value === null || `${value}`.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseFloat(`${value}`);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
}
