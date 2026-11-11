import { http } from '@kit.NetworkKit';
import { AppLog } from './AppLog';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import {
  CaptchaData,
  CourseListResult,
  SelectionBatch,
  SelectionCredentials,
  SelectionCourse,
  SelectionOutcome,
  SelectedCourse
} from '../model/SelectionModels';

const XK_ROOT: string = 'https://jwxk.dmu.edu.cn/xsxk';
const XK_CAPTCHA: string = XK_ROOT + '/auth/captcha';
const XK_LOGIN: string = XK_ROOT + '/auth/login';
const XK_LOGOUT: string = XK_ROOT + '/auth/logout';
const XK_USER: string = XK_ROOT + '/elective/user';
const XK_CLAZZ_LIST: string = XK_ROOT + '/elective/clazz/list';
const XK_CLAZZ_ADD: string = XK_ROOT + '/elective/clazz/add';
const XK_SELECT: string = XK_ROOT + '/elective/select';
const XK_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36';
/** 登录页 HTML 硬编码的 AES 密钥（公开可下载，非秘密），仅用于满足服务端要求的密码提交格式 */
const XK_AES_KEY: string = 'MWMqg2tPcDkxcm11';
const JSON_CONTENT_TYPE: string = 'application/json; charset=UTF-8';
const FORM_CONTENT_TYPE: string = 'application/x-www-form-urlencoded';
/** 关键资产存储中登录凭据的别名（唯一标识一条资产记录） */
const XK_CRED_ALIAS: string = 'edaiyi.jwxk.credentials';
const TAG: string = 'SelectionRepository';
const DOMAIN: number = 0x0000;

/** 会话失效标记：响应为登录页 HTML（含 loginname 表单）时抛出，界面据此回到登录页 */
export const SESSION_INVALID_ERROR: string = 'SESSION_INVALID';

/** 通用响应信封：code 为数字 200（与 jwxt 的字符串 "0" 不同） */
interface XkResponseRaw<T> {
  code?: number;
  msg?: string;
  data?: T;
}

interface CaptchaRaw {
  /** 服务端返回字符串 "1"/"2"（实测），统一转数字 */
  type?: string | number;
  captcha?: string;
  uuid?: string;
}

interface LoginDataRaw {
  token?: string;
  student?: StudentRaw;
}

interface StudentRaw {
  XM?: string;
}

interface ElectiveUserDataRaw {
  student?: ElectiveStudentRaw;
}

interface ElectiveStudentRaw {
  XM?: string;
  electiveBatchList?: BatchRaw[];
}

interface BatchRaw {
  code?: string;
  name?: string;
  canSelect?: string;
  beginTime?: string;
  endTime?: string;
  typeName?: string;
  tacticName?: string;
  weekRange?: string;
}

/** clazz/list 请求体 */
interface CourseQueryBody {
  teachingClassType: string;
  pageNumber: number;
  pageSize: number;
  orderBy: string;
  campus: string;
  KEY?: string;
}

interface SkSjRaw {
  /** 周次文本 */
  SKZCMC?: string;
  /** 星期（1=一 … 7=日） */
  SKXQ?: string | number;
  /** 开始节次 */
  KSJC?: string | number;
  /** 结束节次 */
  JSJC?: string | number;
  /** 地点 */
  YPSJDD?: string;
}

interface ClazzRowRaw {
  JXBID?: string;
  secretVal?: string;
  KCH?: string;
  KCM?: string;
  KXH?: string;
  SKJS?: string;
  XF?: string;
  KRL?: number;
  YXRS?: number;
  SKSJ?: SkSjRaw[];
}

interface ClazzListDataRaw {
  total?: number;
  rows?: ClazzRowRaw[];
}

interface SelectedRowRaw {
  JXBID?: string;
  KCM?: string;
  SKJS?: string;
  XF?: string;
  selectStatus?: number;
  CZSJ?: string;
}

/** clazz/add 响应的 data 字段不使用，仅占位满足泛型信封 */
interface XkAddDataRaw {
  placeholder?: string;
}

/** 凭据资产明文（SECRET）的 JSON 结构 */
interface CredentialBlobRaw {
  n?: string;
  p?: string;
}

/**
 * 选课系统（jwxk）数据仓库：独立账号体系，原生登录（AES 加密密码 + 图形验证码），
 * 登录凭证（token）仅保留在内存，不持久化；
 * 退出登录、严格隐私模式清理时调用 clearSession 立即清除。
 * 登录凭据（学号/密码）经用户勾选后保存于系统关键资产存储（Asset Store，系统级加密、仅本机），
 * 取消勾选、受限/严格隐私模式清理时调用 clearSavedCredentials 立即清除。
 * 提交选课（clazz/add）为异步入队且服务端要求绝不重试，本仓库不实现任何自动重发。
 */
export class SelectionRepository {
  private static token: string = '';
  private static studentNameValue: string = '';

  static isLoggedIn(): boolean {
    return SelectionRepository.token.length > 0;
  }

  static currentStudentName(): string {
    return SelectionRepository.studentNameValue;
  }

  /** 清除登录凭证（仅内存态，无持久化数据需要清理） */
  static clearSession(): void {
    SelectionRepository.token = '';
    SelectionRepository.studentNameValue = '';
  }

  /** 凭据资产别名转字节（asset ALIAS/SECRET 均为 Uint8Array） */
  private static credentialAlias(): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(XK_CRED_ALIAS);
  }

  /**
   * 保存登录凭据到系统关键资产存储（Asset Store，系统级加密、仅本机、随应用卸载移除）；
   * 设备不支持或存储失败时静默降级（不记密码，不影响登录）。
   */
  static async saveCredentials(loginName: string, password: string): Promise<void> {
    if (!canIUse('SystemCapability.Security.Asset')) {
      return;
    }
    const encoder: util.TextEncoder = new util.TextEncoder();
    const blob: CredentialBlobRaw = { n: loginName, p: password };
    const secret: Uint8Array = encoder.encodeInto(JSON.stringify(blob));
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, SelectionRepository.credentialAlias());
    attributes.set(asset.Tag.SECRET, secret);
    // 首次解锁后即可访问：无锁屏密码时等同开机后可访问
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    try {
      try {
        await asset.add(attributes);
      } catch (addError) {
        // 24000003 资产已存在：改为更新
        const query: asset.AssetMap = new Map();
        query.set(asset.Tag.ALIAS, SelectionRepository.credentialAlias());
        const updateAttrs: asset.AssetMap = new Map();
        updateAttrs.set(asset.Tag.SECRET, secret);
        await asset.update(query, updateAttrs);
      }
      AppLog.info(DOMAIN, TAG, 'credentials saved');
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      AppLog.warn(DOMAIN, TAG, 'save credentials failed: code=%{public}s msg=%{public}s',
        `${err.code ?? ''}`, `${err.message ?? ''}`);
    }
  }

  /** 读取已保存的登录凭据（密码可能为空：登录尝试时保存的学号草稿）；不存在或读取失败返回 null */
  static async loadCredentials(): Promise<SelectionCredentials | null> {
    if (!canIUse('SystemCapability.Security.Asset')) {
      AppLog.warn(DOMAIN, TAG, 'load credentials: asset unsupported');
      return null;
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SelectionRepository.credentialAlias());
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const records: Array<asset.AssetMap> = await asset.query(query);
      if (records.length === 0) {
        AppLog.info(DOMAIN, TAG, 'load credentials: no record');
        return null;
      }
      const value: boolean | number | Uint8Array | undefined = records[0].get(asset.Tag.SECRET);
      if (!(value instanceof Uint8Array)) {
        AppLog.warn(DOMAIN, TAG, 'load credentials: secret missing');
        return null;
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      const raw: CredentialBlobRaw = JSON.parse(decoder.decodeToString(value)) as CredentialBlobRaw;
      const credentials: SelectionCredentials = new SelectionCredentials();
      credentials.loginName = raw.n ?? '';
      credentials.password = raw.p ?? '';
      if (credentials.loginName.length === 0) {
        return null;
      }
      AppLog.info(DOMAIN, TAG, 'credentials loaded: hasPassword=%{public}s', `${credentials.password.length > 0}`);
      return credentials;
    } catch (error) {
      // 24000002 资产不存在等：无已保存凭据
      const err: BusinessError = error as BusinessError;
      AppLog.info(DOMAIN, TAG, 'load credentials: none or failed, code=%{public}s', `${err.code ?? ''}`);
      return null;
    }
  }

  /**
   * 登录尝试时保存学号草稿（密码留空，待登录成功后补全）：
   * 仅当本地尚无已保存凭据时写入，避免覆盖已记住的正确密码。
   */
  static async saveLoginNameDraft(loginName: string): Promise<void> {
    if (loginName.length === 0) {
      return;
    }
    const existing: SelectionCredentials | null = await SelectionRepository.loadCredentials();
    if (existing !== null) {
      return;
    }
    await SelectionRepository.saveCredentials(loginName, '');
  }

  /** 清除已保存的登录凭据（取消勾选、受限/严格隐私模式时调用），失败仅记录日志 */
  static async clearSavedCredentials(): Promise<void> {
    if (!canIUse('SystemCapability.Security.Asset')) {
      return;
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, SelectionRepository.credentialAlias());
      await asset.remove(query);
      AppLog.info(DOMAIN, TAG, 'credentials cleared');
    } catch (error) {
      // 24000002 资产不存在视为已清除
      const err: BusinessError = error as BusinessError;
      if (err.code === 24000002) {
        return;
      }
      AppLog.warn(DOMAIN, TAG, 'clear credentials failed: code=%{public}s msg=%{public}s',
        `${err.code ?? ''}`, `${err.message ?? ''}`);
    }
  }

  /**
   * 统一 POST：按接口要求切换 JSON/表单体格式，
   * 未登录会话返回登录页 HTML（含 loginname）时抛 SESSION_INVALID_ERROR。
   */
  private static async post(path: string, body: string, contentType: string, withAuth: boolean): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {
        'User-Agent': XK_UA,
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': contentType,
        'Accept': 'application/json'
      };
      if (withAuth && SelectionRepository.token.length > 0) {
        // 服务端要求 token 原样放入 Authorization，不加 Bearer
        header['Authorization'] = SelectionRepository.token;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: header,
        connectTimeout: 10000,
        readTimeout: 10000,
        expectDataType: http.HttpDataType.STRING
      };
      // 空 body 时不得设置 extraData（空字符串会被 http 栈判定 Parameter error 401）
      if (body.length > 0) {
        options.extraData = body;
      }
      let response: http.HttpResponse;
      try {
        response = await client.request(path, options);
      } catch (reqError) {
        // 原生层拒绝值非 Error 实例（字符串化为 [object Object]），统一转可读错误码/信息
        const reqErr: BusinessError = reqError as BusinessError;
        AppLog.error(DOMAIN, TAG, 'request failed: code=%{public}s msg=%{public}s url=%{public}s',
          `${reqErr.code ?? ''}`, `${reqErr.message ?? ''}`, path);
        throw new Error('网络连接失败（' + `${reqErr.code ?? ''}` + '：'
          + `${reqErr.message ?? '请检查网络后重试'}` + '）');
      }
      if (response.responseCode !== 200) {
        AppLog.error(DOMAIN, TAG, 'HTTP %{public}s on %{public}s', `${response.responseCode}`, path);
        throw new Error('网络请求失败（HTTP ' + `${response.responseCode}` + '）');
      }
      return typeof response.result === 'string' ? response.result : '';
    } finally {
      client.destroy();
    }
  }

  /**
   * 解析响应信封前的 HTML 检测：
   * 含 loginname 的 HTML 为登录页（会话失效）；含「友情提示」的为业务拦截页；
   * 其余非 JSON 内容统一报格式异常。
   */
  private static parseEnvelope<T>(text: string, apiName: string): XkResponseRaw<T> {
    if (text.indexOf('loginname') >= 0) {
      throw new Error(SESSION_INVALID_ERROR);
    }
    if (text.indexOf('友情提示') >= 0) {
      throw new Error('系统拦截提示（可能不在选课轮次或时间）');
    }
    try {
      return JSON.parse(text) as XkResponseRaw<T>;
    } catch (parseError) {
      AppLog.error(DOMAIN, TAG, '%{public}s: non-json response, len=%{public}s, head=%{public}s',
        apiName, `${text.length}`, text.length > 0 ? text.substring(0, 60) : '(empty)');
      throw new Error('服务返回异常，请稍后重试');
    }
  }

  /** 校验信封 code==200 并取 data，业务失败时抛服务端 msg */
  private static checkCode<T>(raw: XkResponseRaw<T>, apiName: string): T {
    if (raw.code !== 200) {
      const msg: string = raw.msg !== undefined && raw.msg.length > 0 ? raw.msg : '请求失败（code ' + `${raw.code ?? -1}` + '）';
      AppLog.warn(DOMAIN, TAG, '%{public}s: code=%{public}s msg=%{public}s', apiName, `${raw.code ?? -1}`, msg);
      throw new Error(msg);
    }
    if (raw.data === undefined) {
      throw new Error('服务未返回数据');
    }
    return raw.data;
  }

  /** 初始化验证码：每次刷新换新 uuid，uuid 与验证码成对使用 */
  static async fetchCaptcha(): Promise<CaptchaData> {
    const text: string = await SelectionRepository.post(XK_CAPTCHA, '', JSON_CONTENT_TYPE, false);
    const data: CaptchaRaw =
      SelectionRepository.checkCode<CaptchaRaw>(SelectionRepository.parseEnvelope<CaptchaRaw>(text, 'captcha'), 'captcha');
    const captcha: CaptchaData = new CaptchaData();
    // 服务端 type 为字符串，统一归一化为数字：1=图形 2=交互式
    const rawType: string = data.type !== undefined ? `${data.type}`.trim() : '';
    const parsedType: number = rawType.length > 0 ? Number.parseInt(rawType) : 0;
    captcha.type = parsedType > 0 ? parsedType : 1;
    captcha.captcha = data.captcha ?? '';
    captcha.uuid = data.uuid ?? '';
    if (captcha.captcha.length === 0 || captcha.uuid.length === 0) {
      throw new Error('验证码数据不完整，请重试');
    }
    AppLog.info(DOMAIN, TAG, 'captcha ok: type=%{public}d imgLen=%{public}s',
      captcha.type, `${captcha.captcha.length}`);
    return captcha;
  }

  /**
   * 密码加密：AES-128-ECB-PKCS7（无 IV），密钥为登录页 HTML 公开硬编码值，
   * 输出标准 Base64，与服务端登录页 CryptoJS 实现一致。
   */
  private static async encryptPassword(plain: string): Promise<string> {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const keyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const keyBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(XK_AES_KEY) };
    const symKey: cryptoFramework.SymKey = await keyGen.convertKey(keyBlob);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|ECB|PKCS7');
    // ECB 模式无 IV/附加参数，params 传 null
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, null);
    const plainBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(plain) };
    const cipherBlob: cryptoFramework.DataBlob = await cipher.doFinal(plainBlob);
    const base64: util.Base64Helper = new util.Base64Helper();
    return base64.encodeToStringSync(cipherBlob.data);
  }

  /** 登录：表单体（loginname/password/captcha/uuid），成功后 token 仅保留在内存 */
  static async login(loginName: string, password: string, captcha: string, uuid: string): Promise<void> {
    const encrypted: string = await SelectionRepository.encryptPassword(password);
    const body: string = 'loginname=' + encodeURIComponent(loginName)
      + '&password=' + encodeURIComponent(encrypted)
      + '&captcha=' + encodeURIComponent(captcha)
      + '&uuid=' + encodeURIComponent(uuid);
    const text: string = await SelectionRepository.post(XK_LOGIN, body, FORM_CONTENT_TYPE, false);
    const data: LoginDataRaw =
      SelectionRepository.checkCode<LoginDataRaw>(SelectionRepository.parseEnvelope<LoginDataRaw>(text, 'login'), 'login');
    if (data.token === undefined || data.token.length === 0) {
      throw new Error('登录失败：未获取到凭证');
    }
    SelectionRepository.token = data.token;
    SelectionRepository.studentNameValue = data.student?.XM ?? '';
    AppLog.info(DOMAIN, TAG, 'login ok');
  }

  /** 学生信息 + 全部选课轮次；轮次未初始化时服务端返回 HTML 提示页，按格式异常处理 */
  static async loadBatches(): Promise<SelectionBatch[]> {
    const text: string = await SelectionRepository.post(XK_USER, '{}', JSON_CONTENT_TYPE, true);
    const data: ElectiveUserDataRaw =
      SelectionRepository.checkCode<ElectiveUserDataRaw>(SelectionRepository.parseEnvelope<ElectiveUserDataRaw>(text, 'user'), 'user');
    const student: ElectiveStudentRaw | undefined = data.student;
    if (student !== undefined && student.XM !== undefined && student.XM.length > 0) {
      SelectionRepository.studentNameValue = student.XM;
    }
    const list: SelectionBatch[] = [];
    const rows: BatchRaw[] | undefined = student?.electiveBatchList;
    if (rows !== undefined) {
      for (const row of rows) {
        const code: string = row.code ?? '';
        if (code.length === 0) {
          continue;
        }
        const batch: SelectionBatch = new SelectionBatch();
        batch.code = code;
        batch.name = row.name ?? '';
        batch.canSelect = row.canSelect ?? '';
        batch.beginTime = row.beginTime ?? '';
        batch.endTime = row.endTime ?? '';
        batch.typeName = row.typeName ?? '';
        batch.tacticName = row.tacticName ?? '';
        batch.weekRange = row.weekRange ?? '';
        list.push(batch);
      }
    }
    AppLog.info(DOMAIN, TAG, 'batches: %{public}s', `${list.length}`);
    return list;
  }

  /** 可选课程列表（JSON 体）：keyword 为检索词，pageNumber 从 1 起 */
  static async loadCourses(keyword: string, pageNumber: number, pageSize: number): Promise<CourseListResult> {
    const body: CourseQueryBody = {
      teachingClassType: 'XGKC',
      pageNumber: pageNumber,
      pageSize: pageSize,
      orderBy: '',
      campus: '1'
    };
    if (keyword.length > 0) {
      body.KEY = keyword;
    }
    const text: string = await SelectionRepository.post(XK_CLAZZ_LIST, JSON.stringify(body), JSON_CONTENT_TYPE, true);
    const data: ClazzListDataRaw =
      SelectionRepository.checkCode<ClazzListDataRaw>(SelectionRepository.parseEnvelope<ClazzListDataRaw>(text, 'clazzList'), 'clazzList');
    const result: CourseListResult = new CourseListResult();
    result.total = data.total ?? 0;
    const rows: ClazzRowRaw[] | undefined = data.rows;
    if (rows !== undefined) {
      for (const row of rows) {
        if (row.JXBID === undefined) {
          continue;
        }
        const course: SelectionCourse = new SelectionCourse();
        course.jxbId = row.JXBID;
        course.secretVal = row.secretVal ?? '';
        course.courseCode = row.KCH ?? '';
        course.courseName = row.KCM ?? '';
        course.classNo = row.KXH ?? '';
        course.teacher = row.SKJS ?? '';
        course.credit = `${row.XF ?? ''}`;
        course.capacity = row.KRL ?? 0;
        course.selectedCount = row.YXRS ?? 0;
        course.timeText = SelectionRepository.buildTimeText(row.SKSJ);
        result.courses.push(course);
      }
    }
    AppLog.info(DOMAIN, TAG, 'courses: page %{public}s total %{public}s rows %{public}s',
      `${pageNumber}`, `${result.total}`, `${result.courses.length}`);
    return result;
  }

  /** 已选课程（data 为数组），提交选课后须回查此接口确认结果 */
  static async loadSelected(): Promise<SelectedCourse[]> {
    const text: string = await SelectionRepository.post(XK_SELECT, '{}', JSON_CONTENT_TYPE, true);
    const rows: SelectedRowRaw[] =
      SelectionRepository.checkCode<SelectedRowRaw[]>(SelectionRepository.parseEnvelope<SelectedRowRaw[]>(text, 'select'), 'select');
    const list: SelectedCourse[] = [];
    for (const row of rows) {
      if (row.JXBID === undefined) {
        continue;
      }
      const item: SelectedCourse = new SelectedCourse();
      item.jxbId = row.JXBID;
      item.courseName = row.KCM ?? '';
      item.teacher = row.SKJS ?? '';
      item.credit = `${row.XF ?? ''}`;
      item.selectStatus = row.selectStatus ?? 0;
      item.operateTime = row.CZSJ ?? '';
      list.push(item);
    }
    AppLog.info(DOMAIN, TAG, 'selected: %{public}s', `${list.length}`);
    return list;
  }

  /**
   * 提交选课（表单体）：异步入队，返回 200 仅代表已进入选课队列；
   * 只提交一次、绝不重试（网络异常时结果未知，由界面引导用户回查已选列表）。
   */
  static async submitCourse(course: SelectionCourse, batchId: string): Promise<SelectionOutcome> {
    const body: string = 'clazzType=' + encodeURIComponent('XGKC')
      + '&clazzId=' + encodeURIComponent(course.jxbId)
      + '&secretVal=' + encodeURIComponent(course.secretVal)
      + '&batchId=' + encodeURIComponent(batchId);
    const text: string = await SelectionRepository.post(XK_CLAZZ_ADD, body, FORM_CONTENT_TYPE, true);
    const raw: XkResponseRaw<XkAddDataRaw> = SelectionRepository.parseEnvelope<XkAddDataRaw>(text, 'clazzAdd');
    const outcome: SelectionOutcome = new SelectionOutcome();
    if (raw.code === 200) {
      outcome.success = true;
      outcome.message = raw.msg !== undefined && raw.msg.length > 0 ? raw.msg : '已进入选课队列，请稍后刷新已选列表确认结果';
    } else {
      outcome.success = false;
      outcome.message = raw.msg !== undefined && raw.msg.length > 0 ? raw.msg : '选课失败（code ' + `${raw.code ?? -1}` + '）';
    }
    AppLog.info(DOMAIN, TAG, 'submit %{public}s: success=%{public}s msg=%{public}s',
      course.jxbId, `${outcome.success}`, outcome.message);
    return outcome;
  }

  /** 登出：通知服务端后清除本地会话；服务端失败也照常清除 */
  static async logout(): Promise<void> {
    if (SelectionRepository.token.length === 0) {
      return;
    }
    try {
      await SelectionRepository.post(XK_LOGOUT, '{}', JSON_CONTENT_TYPE, true);
    } catch (error) {
      AppLog.warn(DOMAIN, TAG, 'logout request failed: %{public}s', `${error}`);
    }
    SelectionRepository.clearSession();
    AppLog.info(DOMAIN, TAG, 'logout ok');
  }

  /** 拼接上课时间地点文本：`周次/星期/起止节次/地点`，多时段以「；」分隔 */
  private static buildTimeText(items?: SkSjRaw[]): string {
    if (items === undefined || items.length === 0) {
      return '';
    }
    const parts: string[] = [];
    for (const item of items) {
      const segments: string[] = [];
      if (item.SKZCMC !== undefined && item.SKZCMC.length > 0) {
        segments.push(item.SKZCMC);
      }
      const weekday: string = SelectionRepository.weekdayText(item.SKXQ);
      if (weekday.length > 0) {
        segments.push(weekday);
      }
      if (item.KSJC !== undefined && item.KSJC !== '' && item.JSJC !== undefined && item.JSJC !== '') {
        segments.push(`${item.KSJC}` + '-' + `${item.JSJC}` + '节');
      } else if (item.KSJC !== undefined && item.KSJC !== '') {
        segments.push(`${item.KSJC}` + '节');
      }
      if (item.YPSJDD !== undefined && item.YPSJDD.length > 0) {
        segments.push(item.YPSJDD);
      }
      if (segments.length > 0) {
        parts.push(segments.join('/'));
      }
    }
    return parts.join('；');
  }

  /** SKXQ（1=一 … 7=日）转「星期X」，异常值返回空串 */
  private static weekdayText(wd?: string | number): string {
    if (wd === undefined || wd === '') {
      return '';
    }
    const value: number = Number.parseInt(`${wd}`);
    if (value >= 1 && value <= 7) {
      const names: string[] = ['一', '二', '三', '四', '五', '六', '日'];
      return '星期' + names[value - 1];
    }
    return '';
  }
}
