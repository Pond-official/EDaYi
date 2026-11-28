/**
 * 跨域会话目标域配置（任务 14：跨域会话服务化）。
 * 新增一个域只需在本文件加一条 DomainSpec 常量，
 * 业务侧一行 CrossDomainSession.ensure(DOMAIN_XXX) 即可，无需新增组件/定时器/状态机。
 */
export class DomainSpec {
  readonly key: string;
  readonly host: string;
  readonly entryUrl: string;
  readonly timeoutMs: number;
  /** 换票成功后的门户预热页（空串 = 不预热） */
  readonly warmupUrl: string;
  /** 门户预热停留时长（毫秒） */
  readonly warmupMs: number;

  constructor(key: string, host: string, entryUrl: string, timeoutMs: number,
    warmupUrl: string = '', warmupMs: number = 0) {
    this.key = key;
    this.host = host;
    this.entryUrl = entryUrl;
    this.timeoutMs = timeoutMs;
    this.warmupUrl = warmupUrl;
    this.warmupMs = warmupMs;
  }
}

/** 学生综合服务系统（综评）域：entryUrl 取原 ZcpRepository.indexUrl() 的值，未做任何改动 */
export const DOMAIN_XGFW: DomainSpec =
  new DomainSpec('xgfw', 'xgfw.dmu.edu.cn',
    'https://xgfw.dmu.edu.cn/xsfw/sys/zhcptybbapp/*default/index.do', 20000);

/** ehall 门户域：校园卡余额/图书借阅数量走其个人数据聚合卡片（execCardMethod），需门户会话 Cookie；
 * entryUrl 必须用 /login（302 到 cas authserver 换票后回跳建立门户 session），
 * 用根路径 / 只会 302 到落地页 default/index.html，不触发 CAS，接口会报「无权限调用」。
 * 换票后必须预热：加载门户页停留 15 秒让页面 JS 运行，否则服务端不会聚合用户数据，
 * getPersonalDataDetail 持续返回 data:null（list 是全局配置不受影响） */
export const DOMAIN_EHALL: DomainSpec =
  new DomainSpec('ehall', 'ehall.dmu.edu.cn', 'https://ehall.dmu.edu.cn/login', 20000,
    'https://ehall.dmu.edu.cn/default/index.html', 15000);

/** 图书馆（汇文 LibSP）域：经超星 CAS 中转 SSO 链换取 JWT（落 cookie jwt/jwtHeader），供借阅详情接口使用 */
export const DOMAIN_LIBSP: DomainSpec =
  new DomainSpec('libsp', 'finddmu.libsp.cn',
    'https://tyrzfw.chaoxing.com/auth3/dmu/cas/init?isLogout=0&refer='
    + encodeURIComponent('https://finddmu.libsp.cn/find/sso/login/dmu/0?pageType=5&navigation=1'), 25000);

/** 教务系统（jwapp）域：JW 应用会话过期（探针 currentUser.do 应答未登录）时，
 * 借隐藏 Web 静默重走 CAS 换票链恢复——CAS TGT 仍有效即无感续票（新会话 Cookie 落系统 Cookie 存储），
 * CAS 也已过期时引导链落到 authserver 登录页，按失败返回回退离线；
 * entryUrl 与登录页同源（/sys/homeapp/index.do，未登录 302 → CAS 换票 → 回跳 jwxt 建立新会话），
 * 纯 API 域无需门户预热（warmupUrl 留空） */
export const DOMAIN_JW: DomainSpec =
  new DomainSpec('jw', 'jwxt.dmu.edu.cn',
    'https://jwxt.dmu.edu.cn/jwapp/sys/homeapp/index.do', 20000);
