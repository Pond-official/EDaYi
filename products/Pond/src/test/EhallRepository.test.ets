import { describe, it, expect } from '@ohos/hypium';
import { EhallRepository } from '../main/ets/data/EhallRepository';

export default function ehallRepositoryTest() {
  describe('EhallRepository', () => {
    it('parseValueText_balance_sample', 0, () => {
      expect(EhallRepository.parseValueText('余额：10.38')).assertEqual('10.38');
    });
    it('parseValueText_borrow_sample', 0, () => {
      expect(EhallRepository.parseValueText('借阅数量：0')).assertEqual('0');
    });
    it('parseValueText_no_colon_returns_trimmed', 0, () => {
      expect(EhallRepository.parseValueText(' 10.38 ')).assertEqual('10.38');
    });
    it('parseValueText_empty', 0, () => {
      expect(EhallRepository.parseValueText('')).assertEqual('');
    });
    it('parseCount_zero', 0, () => {
      expect(EhallRepository.parseCount('借阅数量：0')).assertEqual(0);
    });
    it('parseCount_number', 0, () => {
      expect(EhallRepository.parseCount('借阅数量：12')).assertEqual(12);
    });
    it('parseCount_invalid_text', 0, () => {
      expect(EhallRepository.parseCount('借阅数量：abc')).assertEqual(-1);
    });
    it('parseCount_empty', 0, () => {
      expect(EhallRepository.parseCount('')).assertEqual(-1);
    });
  });
}
