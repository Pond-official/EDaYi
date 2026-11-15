/**
 * 图书馆借阅模型（dmulib-api 接入）：
 * 域模型（class）+ 抓包原始结构（*Raw 接口）分离，
 * Raw 仅用于 JSON.parse 的一次性落点，字段全部可选、按宽容策略拷贝进域模型。
 * 关键约定（2026-11-15 抓包）：
 *  · loanNum = 剩余可借数（非已借数），已借看 numFound；
 *  · returnDate 为 null 表示尚未归还（在借）；
 *  · 续借传 loanId（不是 recordId），且必须是数组。
 */

/** 汇文 LibSP 统一响应包络（success/errCode/data） */
export interface LibEnvelopeRaw<T> {
  success?: boolean;
  message?: string;
  errCode?: number;
  errorCode?: string | null;
  data?: T;
}

/** 借阅记录（loanList / loanHistoryList 共用）原始结构 */
export interface LoanRecordRaw {
  recordId?: number;
  loanId?: number;
  title?: string;
  author?: string;
  publisher?: string;
  isbn?: string;
  publishYear?: string;
  loanDate?: string;
  normReturnDate?: string;
  returnDate?: string | null;
  locationName?: string;
  curLocationName?: string;
  phyLibName?: string;
  curLibName?: string;
  barcode?: string;
  propNo?: string;
  callNo?: string | null;
  renewTimes?: number | null;
  overdueDays?: number;
  renewFlag?: string;
  allowRenewFlag?: string;
}

/** 借阅列表响应（data 节点）原始结构 */
export interface LoanPageRaw {
  searchResult?: LoanRecordRaw[] | null;
  /** 剩余可借阅数（不是已借数） */
  loanNum?: number;
  numFound?: number;
}

/** 续借响应（data 节点）原始结构 */
export interface RenewResultRaw {
  success?: number;
  fail?: number;
  /** 失败原因：key 为「书名 作者」拼串，value 为原因文本 */
  result?: Record<string, string> | null;
}

/** 单条借阅记录（域模型） */
export class LoanRecord {
  recordId: number = 0;
  /** 续借用的 ID（非 recordId） */
  loanId: number = 0;
  title: string = '';
  author: string = '';
  publisher: string = '';
  isbn: string = '';
  publishYear: string = '';
  /** 借出日期 YYYY-MM-DD */
  loanDate: string = '';
  /** 应还日期 YYYY-MM-DD */
  normReturnDate: string = '';
  /** 实际归还日期；空串 = 在借 */
  returnDate: string = '';
  locationName: string = '';
  curLocationName: string = '';
  barcode: string = '';
  callNo: string = '';
  renewTimes: number = 0;
  overdueDays: number = 0;
  /** 行级续借标记（'1' 允许；接口未返回时不限制） */
  renewFlag: string = '';
  allowRenewFlag: string = '';

  /** 是否在借（未归还） */
  isOnLoan(): boolean {
    return this.returnDate.length === 0;
  }

  /** 是否逾期（在借且应还日期已过按服务端 overdueDays 判定） */
  isOverdue(): boolean {
    return this.isOnLoan() && this.overdueDays > 0;
  }
}

/** 借阅列表页（域模型） */
export class LoanPage {
  records: LoanRecord[] = [];
  /** 剩余可借阅数（不是已借数） */
  loanNum: number = 0;
  /** 已借（或历史命中）数量 */
  numFound: number = 0;
}

/** 续借结果（域模型） */
export class RenewResult {
  successCount: number = 0;
  failCount: number = 0;
  /** 失败原因列表（「书名 作者」→ 原因） */
  failReasons: Record<string, string> = {};
}
