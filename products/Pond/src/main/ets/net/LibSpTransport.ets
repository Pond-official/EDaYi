import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
// 冷启动优化 ③：Cookie 读写收口到 WebCookieOps（内部才 import webview），lazy 使 ArkWeb 不进冷启动模块图
import lazy { WebCookieOps } from './WebCookieOps';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../data/AppLog';
import { Timeouts } from './Timeouts';

/** 图书馆（汇文 LibSP，finddmu.libsp.cn）根地址 */
export const LIB_BASE: string = 'https://finddmu.libsp.cn';
/** 本校图书馆 groupCode（每个请求必传） */
export const LIB_GROUP_CODE: string = '200262';

const TAG: string = 'LibSpTransport';
const DOMAIN: number = 0x0000;

/** 会话失效标记：JWT 过期/未登录时抛出，调用方据此重新走隐藏 Web 换票 */
export const LIBSP_SESSION_INVALID: string = 'LIBSP_AUTH_EXPIRED';

/** 一次登录得到的图书馆令牌（jwt 值 + 动态请求头名） */
export interface LibSpToken {
  jwt: string;
  /** 请求头名，取自 cookie 的 jwtHeader（勿硬编码 jwtOpacAuth） */
  jwtHeader: string;
}

/** 从 WebView Cookie 存储读取图书馆 JWT 令牌；未登录/未取到返回 null */
export function readLibTokenFromCookie(): LibSpToken | null {
  let cookie: string = '';
  try {
    cookie = WebCookieOps.fetchCookieSync(LIB_BASE + '/');
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    AppLog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
    return null;
  }
  if (cookie.length === 0) {
    return null;
  }
  let jwt: string = '';
  let header: string = '';
  const segments: string[] = cookie.split(';');
  for (const segment of segments) {
    const seg: string = segment.trim();
    const eq: number = seg.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key: string = seg.substring(0, eq).trim();
    const value: string = seg.substring(eq + 1).trim();
    if (key === 'jwt') {
      jwt = value;
    } else if (key === 'jwtHeader') {
      header = value;
    }
  }
  if (jwt.length === 0) {
    return null;
  }
  const token: LibSpToken = { jwt: jwt, jwtHeader: header.length > 0 ? header : 'jwtOpacAuth' };
  return token;
}

/** 解 JWT payload（不验签），返回原始 JSON 字符串；失败返回空串 */
export function decodeJwtPayload(jwt: string): string {
  try {
    const parts: string[] = jwt.split('.');
    if (parts.length < 2) {
      return '';
    }
    let body: string = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    while (body.length % 4 !== 0) {
      body += '=';
    }
    const helper: util.Base64Helper = new util.Base64Helper();
    const bytes: Uint8Array = helper.decodeSync(body);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  } catch (error) {
    return '';
  }
}

/** 从 JWT payload 取 userId（"sub" 字段，getTotalMoney 等接口查询参数用） */
export function libUserIdOf(jwt: string): string {
  const payload: string = decodeJwtPayload(jwt);
  if (payload.length === 0) {
    return '';
  }
  const matched: RegExpMatchArray | null = payload.match(/"sub":"([^"]+)"/);
  return matched !== null && matched.length > 1 ? matched[1] : '';
}

/** JWT 是否已过期（按 exp 秒级时间戳；解析失败按过期处理，强制重新换票） */
export function isLibTokenExpired(jwt: string): boolean {
  const payload: string = decodeJwtPayload(jwt);
  if (payload.length === 0) {
    return true;
  }
  const matched: RegExpMatchArray | null = payload.match(/"exp":(\d+)/);
  if (matched === null || matched.length < 2) {
    return false;
  }
  const exp: number = Number.parseInt(matched[1], 10);
  return Date.now() / 1000 >= exp;
}

/**
 * 图书馆统一请求入口：
 * JWT 请求头（头名动态）+ groupCode 必传 + mappingPath 根路径传空串；
 * 仅 HTTP 401 视为 JWT 过期抛 LIBSP_SESSION_INVALID（信封 errCode 由各解析方按 401 判断，
 * 响应体子串匹配 "401" 会误判——书名/索书号含 401 即触发，已移除）。
 */
export async function libRequest(
  token: LibSpToken,
  path: string,
  method: http.RequestMethod,
  bodyJson: string = ''
): Promise<string> {
  const client: http.HttpRequest = http.createHttp();
  try {
    const header: Record<string, string> = {
      'Content-Type': 'application/json;charset=UTF-8',
      'Accept': 'application/json, text/plain, */*',
      'x-lang': 'CHI',
      'content-language': 'zh_CN',
      'groupCode': LIB_GROUP_CODE,
      'mappingPath': ''
    };
    header[token.jwtHeader] = token.jwt;
    const options: http.HttpRequestOptions = {
      method: method,
      header: header,
      connectTimeout: Timeouts.LIBRARY_MS,
      readTimeout: Timeouts.LIBRARY_MS,
      expectDataType: http.HttpDataType.STRING
    };
    if (method === http.RequestMethod.POST && bodyJson.length > 0) {
      options.extraData = bodyJson;
    }
    const response: http.HttpResponse = await client.request(LIB_BASE + path, options);
    const status: number = response.responseCode;
    let text: string = '';
    if (typeof response.result === 'string') {
      text = response.result;
    }
    if (status === 401) {
      AppLog.warn(DOMAIN, TAG, 'lib jwt expired: %{public}s on %{public}s', `${status}`, path);
      throw new Error(LIBSP_SESSION_INVALID);
    }
    if (status < 200 || status >= 300) {
      AppLog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s', `${status}`, path);
      throw new Error('HTTP ' + status);
    }
    return text;
  } finally {
    client.destroy();
  }
}
