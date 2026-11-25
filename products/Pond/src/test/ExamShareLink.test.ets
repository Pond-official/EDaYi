import { describe, it, expect } from '@ohos/hypium';
import { ExamShareLink } from '../main/ets/utils/ExamShareLink';
import { ExamShareText } from '../main/ets/utils/ExamShareText';
import { FinalExamEntry } from '../main/ets/model/JwModels';

function shareEntryOf(course: string, date: string): FinalExamEntry {
  const entry: FinalExamEntry = new FinalExamEntry();
  entry.courseName = course;
  entry.examDate = date;
  return entry;
}

export default function examShareLinkTest() {
  describe('ExamShareLink', () => {
    it('isExamShareLink_matches_own_prefix_only', 0, () => {
      expect(ExamShareLink.isExamShareLink('edaiyi://examshare?d=YQ')).assertTrue();
      expect(ExamShareLink.isExamShareLink('https://example.com/edaiyi://examshare?d=YQ')).assertFalse();
      expect(ExamShareLink.isExamShareLink('edaiyi://other?d=YQ')).assertFalse();
      expect(ExamShareLink.isExamShareLink('')).assertFalse();
    });
    it('payloadLinesOf_roundtrips_through_ExamShareText_parse', 0, () => {
      const exams: FinalExamEntry[] = [
        shareEntryOf('生理学', '2026-06-20 09:00'),
        shareEntryOf('生物化学', '2026-06-23 14:30')
      ];
      const parsed: FinalExamEntry[] = ExamShareText.parse(ExamShareLink.payloadLinesOf(exams));
      expect(parsed.length).assertEqual(2);
      expect(parsed[0].courseName).assertEqual('生理学');
      expect(parsed[0].examDate).assertEqual('2026-06-20 09:00');
      expect(parsed[1].courseName).assertEqual('生物化学');
      expect(parsed[1].examDate).assertEqual('2026-06-23 14:30');
    });
    it('payloadLinesOf_empty_exams_is_empty', 0, () => {
      expect(ExamShareLink.payloadLinesOf([])).assertEqual('');
    });
    it('payloadOf_rejects_foreign_link', 0, () => {
      expect(ExamShareLink.payloadOf('https://example.com/?d=YQ')).assertEqual('');
    });
  });
}
