import { describe, it, expect } from '@ohos/hypium';
import { TermWeekUtils } from '../main/ets/utils/TermWeekUtils';

export default function termWeekUtilsTest() {
  describe('TermWeekUtils', () => {
    it('mondayYmdOf_keeps_monday_itself', 0, () => {
      // 2026-11-16 是周一
      expect(TermWeekUtils.mondayYmdOf(new Date(2026, 10, 16))).assertEqual('2026-11-16');
    });
    it('mondayYmdOf_rolls_tuesday_to_sunday_back', 0, () => {
      // 2026-11-17 周二 / 2026-11-22 周日，所在周周一均为 11-16
      expect(TermWeekUtils.mondayYmdOf(new Date(2026, 10, 17))).assertEqual('2026-11-16');
      expect(TermWeekUtils.mondayYmdOf(new Date(2026, 10, 22))).assertEqual('2026-11-16');
    });
    it('mondayYmdOf_crosses_month_for_month_start_sunday', 0, () => {
      // 2026-11-01 是周日，所在周周一为 10-26（跨月）
      expect(TermWeekUtils.mondayYmdOf(new Date(2026, 10, 1))).assertEqual('2026-10-26');
    });
    it('weeksBetween_same_week_returns_zero', 0, () => {
      expect(TermWeekUtils.weeksBetween('2026-11-16', new Date(2026, 10, 17))).assertEqual(0);
      expect(TermWeekUtils.weeksBetween('2026-11-16', new Date(2026, 10, 22))).assertEqual(0);
    });
    it('weeksBetween_counts_whole_weeks', 0, () => {
      expect(TermWeekUtils.weeksBetween('2026-11-09', new Date(2026, 10, 17))).assertEqual(1);
      expect(TermWeekUtils.weeksBetween('2026-10-26', new Date(2026, 10, 17))).assertEqual(3);
    });
    it('weeksBetween_invalid_or_future_anchor_returns_null', 0, () => {
      expect(TermWeekUtils.weeksBetween('', new Date(2026, 10, 17))).assertNull();
      expect(TermWeekUtils.weeksBetween('bad', new Date(2026, 10, 17))).assertNull();
      expect(TermWeekUtils.weeksBetween('2026-11-23', new Date(2026, 10, 17))).assertNull();
    });
  });
}
