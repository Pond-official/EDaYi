import { describe, it, expect } from '@ohos/hypium';
import { firstSegment, weeksPart, teacherPart } from '../main/ets/jwxt/parsers/TextSplit';

export default function textSplitTest() {
  describe('TextSplit', () => {
    it('firstSegment_extracts_first_part', 0, () => {
      expect(firstSegment('教一楼101;教二楼202', ';')).assertEqual('教一楼101');
    });
    it('firstSegment_returns_whole_when_no_separator', 0, () => {
      expect(firstSegment('教一楼101', ';')).assertEqual('教一楼101');
    });
    it('firstSegment_trims_result', 0, () => {
      expect(firstSegment('  教一楼101 ;其他', ';')).assertEqual('教一楼101');
    });
    it('firstSegment_empty_text', 0, () => {
      expect(firstSegment('', ';')).assertEqual('');
    });
    it('weeksPart_cuts_before_teach_marker', 0, () => {
      expect(weeksPart('1-16周[讲授]/张三[主讲]')).assertEqual('1-16周');
    });
    it('weeksPart_keeps_whole_when_no_marker', 0, () => {
      expect(weeksPart('1-16周')).assertEqual('1-16周');
    });
    it('weeksPart_empty_text', 0, () => {
      expect(weeksPart('')).assertEqual('');
    });
    it('teacherPart_extracts_teacher', 0, () => {
      expect(teacherPart('1-16周[讲授]/张三[主讲]')).assertEqual('张三');
    });
    it('teacherPart_cuts_at_semicolon', 0, () => {
      expect(teacherPart('1-16周[讲授]/张三;李四[主讲]')).assertEqual('张三');
    });
    it('teacherPart_empty_when_no_slash', 0, () => {
      expect(teacherPart('1-16周[讲授]')).assertEqual('');
    });
  });
}
