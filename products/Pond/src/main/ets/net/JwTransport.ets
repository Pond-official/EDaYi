import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { AppLog } from '../data/AppLog';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

/** 教务系统根地址（原 JwxtRepository 常量迁入，值不变） */
export const JW_APP_ROOT: string = 'https://jwxt.dmu.edu.cn/jwapp';

const TAG: string = 'JwxtRepository';
const DOMAIN: number = 0x0000;

/** 最近一次成功取到的 Cookie（fetchCookieSync 失败时兜底），随网络层模块级保存 */
let lastCookie: string = '';
/** 主 Ability 上下文（PondAbility 启动时注入） */
let appContext: common.UIAbilityContext | null = null;

/** 供 UI 层获取主 Ability 上下文（如 openLink 拉起浏览器）；未注入时返回 null */
export function getContext(): common.UIAbilityContext | null {
  return appContext;
}

/** 注入主 Ability 上下文（由 JwxtRepository.attachContext 转发） */
export function attachContext(context: common.UIAbilityContext): void {
  appContext = context;
}

/** 退出登录时清空兜底 Cookie（随会话失效） */
export function clearLastCookie(): void {
  lastCookie = '';
}

function syncCookie(): string {
  let cookie: string = '';
  try {
    cookie = webview.WebCookieManager.fetchCookieSync(JW_APP_ROOT + '/');
    lastCookie = cookie;
  } catch (error) {
    const err: BusinessError = error as BusinessError;
    AppLog.error(DOMAIN, TAG, 'fetchCookieSync failed: %{public}s %{public}s', `${err.code}`, `${err.message}`);
    cookie = lastCookie;
  }
  return cookie;
}

async function request(path: string, form: string, method: http.RequestMethod): Promise<string> {
  const client: http.HttpRequest = http.createHttp();
  try {
    const header: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json'
    };
    const cookie: string = syncCookie();
    if (cookie.length > 0) {
      header['Cookie'] = cookie;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: header,
      connectTimeout: 8000,
      readTimeout: 8000,
      expectDataType: http.HttpDataType.STRING
    };
    if (form.length > 0) {
      options.extraData = form;
    }
    const response: http.HttpResponse = await client.request(JW_APP_ROOT + path, options);
    if (response.responseCode !== 200) {
      AppLog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s', `${response.responseCode}`, path);
      throw new Error('HTTP ' + response.responseCode);
    }
    let text: string = '';
    if (typeof response.result === 'string') {
      text = response.result;
    }
    return text;
  } finally {
    client.destroy();
  }
}

export async function postForm(path: string, form: string): Promise<string> {
  return request(path, form, http.RequestMethod.POST);
}

export async function getForm(path: string): Promise<string> {
  return request(path, '', http.RequestMethod.GET);
}
