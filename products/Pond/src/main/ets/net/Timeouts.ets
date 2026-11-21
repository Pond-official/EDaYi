/**
 * 网络超时集中配置（B6：原各通道/仓库分散硬编码，统一收口便于按通道特性调优）。
 * 单位毫秒。
 */
export class Timeouts {
  /** 教务主通道（jwxt）：校园网内网服务，响应快，快速失败尽早回退离线缓存 */
  static readonly JW_MS: number = 8000;
  /** 通用 HTTP（ehall/综评/选课）：走统一门户与 WAF，放宽一档 */
  static readonly COMMON_MS: number = 10000;
  /** 图书馆通道：外部服务响应较慢，单独放宽 */
  static readonly LIBRARY_MS: number = 15000;
}
