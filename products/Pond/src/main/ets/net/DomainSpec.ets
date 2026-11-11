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

  constructor(key: string, host: string, entryUrl: string, timeoutMs: number) {
    this.key = key;
    this.host = host;
    this.entryUrl = entryUrl;
    this.timeoutMs = timeoutMs;
  }
}

/** 学生综合服务系统（综评）域：entryUrl 取原 ZcpRepository.indexUrl() 的值，未做任何改动 */
export const DOMAIN_XGFW: DomainSpec =
  new DomainSpec('xgfw', 'xgfw.dmu.edu.cn',
    'https://xgfw.dmu.edu.cn/xsfw/sys/zhcptybbapp/*default/index.do', 20000);
