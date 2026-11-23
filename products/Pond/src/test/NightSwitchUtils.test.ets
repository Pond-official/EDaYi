import { describe, it, expect } from '@ohos/hypium';
import { NightSwitchUtils } from '../main/ets/utils/NightSwitchUtils';

const MS_PER_MINUTE: number = 60000;
const MS_PER_HOUR: number = 3600000;
const MS_PER_DAY: number = 86400000;

export default function nightSwitchUtilsTest() {
  describe('NightSwitchUtils', () => {
    it('nextSwitchDelayMs_before_today_target_returns_gap', 0, () => {
      const now: Date = new Date(2026, 10, 23, 19, 0, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 1200)).assertEqual(MS_PER_HOUR);
    });
    it('nextSwitchDelayMs_small_gap_stays_positive_for_clamping', 0, () => {
      const now: Date = new Date(2026, 10, 23, 19, 56, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 1200)).assertEqual(4 * MS_PER_MINUTE);
    });
    it('nextSwitchDelayMs_at_target_schedules_tomorrow_same_time', 0, () => {
      const now: Date = new Date(2026, 10, 23, 20, 0, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 1200)).assertEqual(MS_PER_DAY);
    });
    it('nextSwitchDelayMs_after_target_schedules_tomorrow_same_time', 0, () => {
      const now: Date = new Date(2026, 10, 23, 21, 30, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 1200))
        .assertEqual(MS_PER_DAY - MS_PER_HOUR - 30 * MS_PER_MINUTE);
    });
    it('nextSwitchDelayMs_midnight_target_after_midnight_takes_next_day', 0, () => {
      const now: Date = new Date(2026, 10, 23, 0, 30, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 0)).assertEqual(23 * MS_PER_HOUR + 30 * MS_PER_MINUTE);
    });
    it('nextSwitchDelayMs_midnight_target_at_noon_takes_next_midnight', 0, () => {
      const now: Date = new Date(2026, 10, 23, 12, 0, 0);
      expect(NightSwitchUtils.nextSwitchDelayMs(now, 0)).assertEqual(12 * MS_PER_HOUR);
    });
    it('toScheduleMinutes_rounds_up_to_whole_minute', 0, () => {
      expect(NightSwitchUtils.toScheduleMinutes(5 * MS_PER_MINUTE + 1000)).assertEqual(6);
      expect(NightSwitchUtils.toScheduleMinutes(MS_PER_HOUR)).assertEqual(60);
    });
    it('toScheduleMinutes_enforces_five_minute_floor', 0, () => {
      expect(NightSwitchUtils.toScheduleMinutes(4 * MS_PER_MINUTE)).assertEqual(5);
      expect(NightSwitchUtils.toScheduleMinutes(0)).assertEqual(5);
    });
  });
}
