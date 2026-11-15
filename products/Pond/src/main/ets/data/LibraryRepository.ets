import { http } from '@kit.NetworkKit';
import { AppLog } from './AppLog';
import {
  LibEnvelopeRaw,
  LoanPage,
  LoanPageRaw,
  LoanRecord,
  LoanRecordRaw,
  RenewResult,
  RenewResultRaw
} from '../model/LibraryModels';
import {
  LibSpToken,
  LIBSP_SESSION_INVALID,
  isLibTokenExpired,
  libRequest,
  readLibTokenFromCookie
} from '../net/LibSpTransport';

const TAG: string = 'LibraryRepository';
const DOMAIN: number = 0x0000;
/** 列表单页拉取条数（借阅/历史各一页拉全，学生场景足够） */
const LIST_ROWS: number = 50;

/** 借阅列表请求体（loanList / loanHistoryList 共用） */
interface LoanQueryBody {
  page: number;
  rows: number;
  searchType: number;
  searchContent: string;
  sortType: number;
  startDate: string | null;
  endDate: string | null;
}

/**
 * 图书馆借阅数据仓库（finddmu.libsp.cn，汇文 LibSP）：
 * JWT 令牌由隐藏 Web 走 CAS→超星→LibSP 的 SSO 链落入 Cookie（jwt/jwtHeader 两键），
 * 本仓库只负责「有令牌之后怎么取数据」：
 *  · 令牌过期（24h 无 refresh）抛 LIBSP_SESSION_INVALID，由界面重新换票；
 *  · 数据仅内存态（借阅明细不做磁盘缓存），页面每次进入在线拉取；
 *  · loanNum 是剩余可借数而非已借数，已借数量看 numFound；
 *  · 续借传 loanId（不是 recordId）且必须是数组。
 */
export class LibraryRepository {
  private static token: LibSpToken | null = null;

  /** 是否已持有有效（未过期）令牌 */
  static hasToken(): boolean {
    return LibraryRepository.token !== null;
  }

  /**
   * 从 Cookie 绑定令牌：取到且未过期返回 true；
   * 无令牌/已过期返回 false（需重新走隐藏 Web 换票）。
   */
  static bindTokenFromCookie(): boolean {
    const token: LibSpToken | null = readLibTokenFromCookie();
    if (token === null) {
      return false;
    }
    if (isLibTokenExpired(token.jwt)) {
      AppLog.warn(DOMAIN, TAG, 'lib jwt expired, need re-bootstrap');
      return false;
    }
    LibraryRepository.token = token;
    return true;
  }

  /** 清除令牌（退出登录/会话失效时调用） */
  static clearToken(): void {
    LibraryRepository.token = null;
  }

  /** 当前在借列表（rows 条/页，单页拉全） */
  static async fetchLoans(): Promise<LoanPage> {
    const text: string = await libRequest(LibraryRepository.requireToken(), '/find/loanInfo/loanList',
      http.RequestMethod.POST, JSON.stringify(LibraryRepository.queryBody()));
    return LibraryRepository.parseLoanPage(text);
  }

  /** 借阅历史列表（rows 条/页，单页拉全） */
  static async fetchHistory(): Promise<LoanPage> {
    const text: string = await libRequest(LibraryRepository.requireToken(), '/find/loanInfo/loanHistoryList',
      http.RequestMethod.POST, JSON.stringify(LibraryRepository.queryBody()));
    return LibraryRepository.parseLoanPage(text);
  }

  /**
   * 续借：loanIds 取自 LoanRecord.loanId（不是 recordId），单本也传数组；
   * 失败原因在结果 failReasons（key 为「书名 作者」拼串）。
   */
  static async renewLoan(loanIds: number[]): Promise<RenewResult> {
    if (loanIds.length === 0) {
      throw new Error('未选择要续借的图书');
    }
    const body: Record<string, number[]> = { 'loanIds': loanIds };
    const text: string = await libRequest(LibraryRepository.requireToken(), '/find/lendbook/reNew',
      http.RequestMethod.POST, JSON.stringify(body));
    return LibraryRepository.parseRenewResult(text);
  }

  /** 列表请求体（三个借阅列表接口共用一套参数） */
  private static queryBody(): LoanQueryBody {
    const body: LoanQueryBody = {
      page: 1,
      rows: LIST_ROWS,
      searchType: 1,
      searchContent: '',
      sortType: 0,
      startDate: null,
      endDate: null
    };
    return body;
  }

  private static requireToken(): LibSpToken {
    const token: LibSpToken | null = LibraryRepository.token;
    if (token === null) {
      throw new Error(LIBSP_SESSION_INVALID);
    }
    return token;
  }

  /** 解析列表响应信封为域模型（单测覆盖：loan_list/loan_history_list 样本） */
  static parseLoanPage(text: string): LoanPage {
    const envelope: LibEnvelopeRaw<LoanPageRaw> = JSON.parse(text) as LibEnvelopeRaw<LoanPageRaw>;
    if (envelope.success !== true) {
      const message: string = envelope.message ?? '接口返回失败';
      if (message.indexOf('401') >= 0) {
        throw new Error(LIBSP_SESSION_INVALID);
      }
      throw new Error(message);
    }
    const page: LoanPage = new LoanPage();
    const raw: LoanPageRaw | undefined | null = envelope.data;
    if (raw === undefined || raw === null) {
      return page;
    }
    page.loanNum = raw.loanNum ?? 0;
    page.numFound = raw.numFound ?? 0;
    const rows: LoanRecordRaw[] | null | undefined = raw.searchResult;
    if (rows !== undefined && rows !== null) {
      for (const row of rows) {
        page.records.push(LibraryRepository.toRecord(row));
      }
    }
    return page;
  }

  /** 解析续借响应信封为域模型（单测覆盖：reNew 样本） */
  static parseRenewResult(text: string): RenewResult {
    const envelope: LibEnvelopeRaw<RenewResultRaw> = JSON.parse(text) as LibEnvelopeRaw<RenewResultRaw>;
    if (envelope.success !== true) {
      const message: string = envelope.message ?? '接口返回失败';
      if (message.indexOf('401') >= 0) {
        throw new Error(LIBSP_SESSION_INVALID);
      }
      throw new Error(message);
    }
    const result: RenewResult = new RenewResult();
    const raw: RenewResultRaw | undefined | null = envelope.data;
    if (raw === undefined || raw === null) {
      return result;
    }
    result.successCount = raw.success ?? 0;
    result.failCount = raw.fail ?? 0;
    const reasons: Record<string, string> | null | undefined = raw.result;
    if (reasons !== undefined && reasons !== null) {
      result.failReasons = reasons;
    }
    return result;
  }

  /** 单条借阅记录 Raw → 域模型（宽容拷贝，缺失字段按空/0 处理） */
  private static toRecord(row: LoanRecordRaw): LoanRecord {
    const record: LoanRecord = new LoanRecord();
    record.recordId = row.recordId ?? 0;
    record.loanId = row.loanId ?? 0;
    record.title = row.title ?? '';
    record.author = row.author ?? '';
    record.publisher = row.publisher ?? '';
    record.isbn = row.isbn ?? '';
    record.publishYear = row.publishYear ?? '';
    record.loanDate = row.loanDate ?? '';
    record.normReturnDate = row.normReturnDate ?? '';
    record.returnDate = row.returnDate ?? '';
    record.locationName = row.locationName ?? '';
    record.curLocationName = row.curLocationName ?? '';
    record.barcode = row.barcode ?? '';
    record.callNo = row.callNo ?? '';
    record.renewTimes = row.renewTimes ?? 0;
    record.overdueDays = row.overdueDays ?? 0;
    record.renewFlag = row.renewFlag ?? '';
    record.allowRenewFlag = row.allowRenewFlag ?? '';
    return record;
  }
}
