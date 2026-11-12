import { describe, it, expect } from '@ohos/hypium';
import { ExamDateUtils } from '../main/ets/utils/ExamDateUtils';

const MS_PER_MINUTE: number = 60000;
const MS_PER_HOUR: number = 3600000;
const MS_PER_DAY: number = 86400000;

export default function examDateUtilsTest() {
  describe('ExamDateUtils', () => {
    it('toMinuteText_pads_month_day_hour_minute', 0, () => {
      const date: Date = new Date(2026, 0, 10);
      expect(ExamDateUtils.toMinuteText(date, 9, 5)).assertEqual('2026-01-10 09:05');
      expect(ExamDateUtils.toMinuteText(date, 14, 30)).assertEqual('2026-01-10 14:30');
    });
    it('parseExamDate_parses_minute_text', 0, () => {
      const parsed: Date | null = ExamDateUtils.parseExamDate('2026-01-10 14:30');
      expect(parsed !== null).assertTrue();
      if (parsed !== null) {
        expect(parsed.getFullYear()).assertEqual(2026);
        expect(parsed.getMonth()).assertEqual(0);
        expect(parsed.getDate()).assertEqual(10);
        expect(parsed.getHours()).assertEqual(14);
        expect(parsed.getMinutes()).assertEqual(30);
      }
    });
    it('parseExamDate_legacy_date_maps_to_end_of_day', 0, () => {
      const parsed: Date | null = ExamDateUtils.parseExamDate('2026-01-10');
      expect(parsed !== null).assertTrue();
      if (parsed !== null) {
        expect(parsed.getHours()).assertEqual(23);
        expect(parsed.getMinutes()).assertEqual(59);
      }
    });
    it('parseExamDate_rejects_invalid_text', 0, () => {
      expect(ExamDateUtils.parseExamDate('2026-02-30 10:00') === null).assertTrue();
      expect(ExamDateUtils.parseExamDate('2026-01-10 25:00') === null).assertTrue();
      expect(ExamDateUtils.parseExamDate('2026-01-10 10:61') === null).assertTrue();
      expect(ExamDateUtils.parseExamDate('abc') === null).assertTrue();
      expect(ExamDateUtils.parseExamDate('') === null).assertTrue();
    });
    it('countdownTextOf_shows_days_when_over_one_day', 0, () => {
      const target: Date = new Date(Date.now() + 3 * MS_PER_DAY + 5 * MS_PER_MINUTE);
      expect(ExamDateUtils.countdownTextOf(target)).assertEqual('还有3天');
    });
    it('countdownTextOf_shows_hours_within_one_day', 0, () => {
      const target: Date = new Date(Date.now() + 2 * MS_PER_HOUR);
      expect(ExamDateUtils.countdownTextOf(target)).assertEqual('还有2小时');
    });
    it('countdownTextOf_finished_when_passed', 0, () => {
      const target: Date = new Date(Date.now() - MS_PER_MINUTE);
      expect(ExamDateUtils.countdownTextOf(target)).assertEqual('已结束');
    });
    it('formatDisplay_appends_time_for_minute_text', 0, () => {
      const text: string = ExamDateUtils.formatDisplay('2026-01-10 14:30');
      expect(text.includes('1月10日')).assertTrue();
      expect(text.includes('14:30')).assertTrue();
    });
    it('formatDisplay_keeps_legacy_date_without_time', 0, () => {
      const text: string = ExamDateUtils.formatDisplay('2026-01-10');
      expect(text.includes('1月10日')).assertTrue();
      expect(text.includes(':')).assertFalse();
    });
    it('calendarDaysFrom_today_is_zero', 0, () => {
      const today: Date = new Date();
      expect(ExamDateUtils.calendarDaysFrom(today)).assertEqual(0);
    });
  });
}
