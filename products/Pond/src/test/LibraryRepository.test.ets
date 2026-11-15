import { describe, it, expect } from '@ohos/hypium';
import { LibraryRepository } from '../main/ets/data/LibraryRepository';
import { LoanPage, LoanRecord } from '../main/ets/model/LibraryModels';
import { LIBSP_SESSION_INVALID } from '../main/ets/net/LibSpTransport';

const LOAN_LIST_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":{"searchResult":[],"loanNum":40,"numFound":0}}';

const LOAN_HISTORY_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":{"searchResult":['
  + '{"recordId":316904,"loanId":1962427,"title":"实用骨外固定学. 第2版","author":"主编夏和桃, 秦泗河, 张云峰",'
  + '"publisher":"人民卫生出版社","isbn":"978-7-117-36440-9","publishYear":"2024","loanDate":"2025-11-03",'
  + '"normReturnDate":"2025-12-03","returnDate":"2025-12-29","locationName":"三楼中文书阅览区",'
  + '"barcode":"010791325","curLocationName":"三楼中文书阅览区"},'
  + '{"recordId":315562,"loanId":1893843,"title":"应用颅脑解剖","author":"编著 (巴西) 吉列尔梅·C. 里巴斯",'
  + '"publisher":"天津科技翻译出版有限公司","loanDate":"2025-11-03","normReturnDate":"2025-12-03",'
  + '"returnDate":"2025-12-29","locationName":"三楼中文书阅览区","barcode":"010784888","curLocationName":"总借还书处"}'
  + '],"numFound":2}}';

const ON_LOAN_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":{"searchResult":['
  + '{"recordId":316905,"loanId":1962428,"title":"系统解剖学","author":"主编柏树令",'
  + '"loanDate":"2026-10-01","normReturnDate":"2026-11-01","returnDate":null,'
  + '"renewTimes":1,"overdueDays":3,"renewFlag":"1","allowRenewFlag":"1"}'
  + '],"loanNum":39,"numFound":1}}';

const ERROR_SAMPLE: string = '{"success":false,"message":"读者证状态异常","errCode":500}';
const UNAUTHORIZED_SAMPLE: string = '{"success":false,"message":"401 unauthorized","errCode":401}';

const RENEW_SUCCESS_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":{"success":2,"fail":0,"result":{}}}';

const RENEW_FAIL_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":{"success":0,"fail":1,"result":{"系统解剖学 主编柏树令":"已达最大续借次数"}}}';

const RENEW_NULL_DATA_SAMPLE: string = '{"success":true,"message":"操作成功","errCode":200,"errorCode":null,'
  + '"data":null}';

export default function libraryRepositoryTest() {
  describe('LibraryRepository', () => {
    it('parseLoanPage_loan_list_sample', 0, () => {
      const page: LoanPage = LibraryRepository.parseLoanPage(LOAN_LIST_SAMPLE);
      expect(page.loanNum).assertEqual(40);
      expect(page.numFound).assertEqual(0);
      expect(page.records.length).assertEqual(0);
    });
    it('parseLoanPage_history_sample', 0, () => {
      const page: LoanPage = LibraryRepository.parseLoanPage(LOAN_HISTORY_SAMPLE);
      expect(page.numFound).assertEqual(2);
      expect(page.records.length).assertEqual(2);
      const first: LoanRecord = page.records[0];
      expect(first.recordId).assertEqual(316904);
      expect(first.loanId).assertEqual(1962427);
      expect(first.title).assertEqual('实用骨外固定学. 第2版');
      expect(first.author).assertEqual('主编夏和桃, 秦泗河, 张云峰');
      expect(first.loanDate).assertEqual('2025-11-03');
      expect(first.normReturnDate).assertEqual('2025-12-03');
      expect(first.returnDate).assertEqual('2025-12-29');
      expect(first.isOnLoan()).assertFalse();
      expect(first.isOverdue()).assertFalse();
    });
    it('parseLoanPage_on_loan_overdue', 0, () => {
      const page: LoanPage = LibraryRepository.parseLoanPage(ON_LOAN_SAMPLE);
      expect(page.records.length).assertEqual(1);
      const record: LoanRecord = page.records[0];
      expect(record.returnDate).assertEqual('');
      expect(record.renewTimes).assertEqual(1);
      expect(record.overdueDays).assertEqual(3);
      expect(record.renewFlag).assertEqual('1');
      expect(record.isOnLoan()).assertTrue();
      expect(record.isOverdue()).assertTrue();
    });
    it('parseLoanPage_error_message', 0, () => {
      try {
        LibraryRepository.parseLoanPage(ERROR_SAMPLE);
        expect(false).assertTrue();
      } catch (error) {
        expect(`${error}`.indexOf('读者证状态异常') >= 0).assertTrue();
      }
    });
    it('parseLoanPage_401_throws_session_invalid', 0, () => {
      try {
        LibraryRepository.parseLoanPage(UNAUTHORIZED_SAMPLE);
        expect(false).assertTrue();
      } catch (error) {
        expect(`${error}`.indexOf(LIBSP_SESSION_INVALID) >= 0).assertTrue();
      }
    });
    it('parseRenewResult_success_sample', 0, () => {
      const result = LibraryRepository.parseRenewResult(RENEW_SUCCESS_SAMPLE);
      expect(result.successCount).assertEqual(2);
      expect(result.failCount).assertEqual(0);
      expect(Object.keys(result.failReasons).length).assertEqual(0);
    });
    it('parseRenewResult_fail_reasons', 0, () => {
      const result = LibraryRepository.parseRenewResult(RENEW_FAIL_SAMPLE);
      expect(result.successCount).assertEqual(0);
      expect(result.failCount).assertEqual(1);
      expect(result.failReasons['系统解剖学 主编柏树令']).assertEqual('已达最大续借次数');
    });
    it('parseRenewResult_null_data', 0, () => {
      const result = LibraryRepository.parseRenewResult(RENEW_NULL_DATA_SAMPLE);
      expect(result.successCount).assertEqual(0);
      expect(result.failCount).assertEqual(0);
    });
  });
}
