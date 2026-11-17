import { describe, it, expect } from '@ohos/hypium';
import { ExamShareText } from '../main/ets/utils/ExamShareText';
import { FinalExamEntry } from '../main/ets/model/JwModels';

function shareEntryOf(course: string, date: string): FinalExamEntry {
  const entry: FinalExamEntry = new FinalExamEntry();
  entry.courseName = course;
  entry.examDate = date;
  return entry;
}

export default function examShareTextTest() {
  describe('ExamShareText', () => {
    it('buildShareText_wraps_header_and_footer', 0, () => {
      const text: string = ExamShareText.buildShareText([shareEntryOf('生理学', '2026-06-20 09:00')]);
      expect(text.startsWith('【期末倒计时】')).assertTrue();
      expect(text.includes('—— 来自 EDaYi（E大医）')).assertTrue();
      expect(text.includes('生理学：2026-06-20 09:00')).assertTrue();
    });
    it('parse_roundtrips_built_text', 0, () => {
      const text: string = ExamShareText.buildShareText([
        shareEntryOf('生理学', '2026-06-20 09:00'),
        shareEntryOf('生物化学', '2026-06-23 14:30')
      ]);
      const parsed: FinalExamEntry[] = ExamShareText.parse(text);
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].courseName).assertEqual('生理学');
      expect(parsed[0].examDate).assertEqual('2026-06-20 09:00');
      expect(parsed[1].courseName).assertEqual('生物化学');
      expect(parsed[1].examDate).assertEqual('2026-06-23 14:30');
    });
    it('parse_skips_header_footer_and_invalid_lines', 0, () => {
      const text: string = [
        '【期末倒计时】',
        '随便一行文字',
        '时间： 2026-13-99 10:00',
        '生理学：2026-06-20 09:00（还有3天）',
        '—— 来自 EDaYi（E大医）'
      ].join('\n');
      const parsed: FinalExamEntry[] = ExamShareText.parse(text);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].courseName).assertEqual('生理学');
      expect(parsed[0].examDate).assertEqual('2026-06-20 09:00');
    });
    it('parse_keeps_last_entry_for_duplicate_course', 0, () => {
      const text: string = [
        '生理学：2026-06-20 09:00（还有3天）',
        '生理学：2026-06-21 15:00（还有4天）'
      ].join('\n');
      const parsed: FinalExamEntry[] = ExamShareText.parse(text);
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].examDate).assertEqual('2026-06-21 15:00');
    });
    it('parse_accepts_legacy_date_without_time', 0, () => {
      const parsed: FinalExamEntry[] = ExamShareText.parse('病理学：2026-06-25');
      expect(parsed.length).assertEqual(1);
      expect(parsed[0].courseName).assertEqual('病理学');
      expect(parsed[0].examDate).assertEqual('2026-06-25');
    });
    it('parse_returns_empty_for_plain_text', 0, () => {
      expect(ExamShareText.parse('你好，世界').length).assertEqual(0);
      expect(ExamShareText.parse('').length).assertEqual(0);
    });
  });
}
