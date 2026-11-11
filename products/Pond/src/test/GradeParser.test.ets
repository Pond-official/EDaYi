import { describe, it, expect } from '@ohos/hypium';
import { parseGrades, parseGradeRow, parseGradeCategories, isPassedScore, rawNumber, stripCourseCodeSuffix } from '../main/ets/jwxt/parsers/GradeParser';
import { GradeEntry } from '../main/ets/model/JwModels';
import { FanTreeRaw, GradeItemRaw } from '../main/ets/model/JwRawModels';

export default function gradeParserTest() {
  describe('GradeParser', () => {
    it('rawNumber_passes_number_through', 0, () => {
      expect(rawNumber(3.5)).assertEqual(3.5);
    });
    it('rawNumber_parses_numeric_string', 0, () => {
      expect(rawNumber('2.5')).assertEqual(2.5);
    });
    it('rawNumber_zero_for_empty_or_invalid', 0, () => {
      expect(rawNumber('')).assertEqual(0);
      expect(rawNumber('abc')).assertEqual(0);
      expect(rawNumber(undefined)).assertEqual(0);
    });
    it('isPassedScore_numeric_threshold', 0, () => {
      expect(isPassedScore('88')).assertTrue();
      expect(isPassedScore('60')).assertTrue();
      expect(isPassedScore('59')).assertFalse();
    });
    it('isPassedScore_text_levels', 0, () => {
      expect(isPassedScore('优秀')).assertTrue();
      expect(isPassedScore('合格')).assertTrue();
      expect(isPassedScore('不及格')).assertFalse();
      expect(isPassedScore('不合格')).assertFalse();
      expect(isPassedScore('未通过')).assertFalse();
    });
    it('isPassedScore_empty_is_fail', 0, () => {
      expect(isPassedScore('')).assertFalse();
    });
    it('parseGradeRow_null_when_no_course_name', 0, () => {
      const item: GradeItemRaw = { CJ: '88' };
      const result: GradeEntry | null = parseGradeRow(item);
      expect(result === null).assertTrue();
    });
    it('parseGradeRow_null_when_score_empty_or_zero', 0, () => {
      const emptyScore: GradeItemRaw = { KCM: '高等数学', CJ: '' };
      const zeroScore: GradeItemRaw = { KCM: '高等数学', CJ: '0' };
      expect(parseGradeRow(emptyScore) === null).assertTrue();
      expect(parseGradeRow(zeroScore) === null).assertTrue();
    });
    it('parseGradeRow_40_field_view', 0, () => {
      const item: GradeItemRaw = {
        KCM: '高等数学A(一)',
        CJ: '92',
        JD: '4.0',
        XF: '5',
        XKXNXQDM: '2025-2026-1',
        KCXZDM_DISPLAY: '必修',
        KSLXDM_DISPLAY: '考试'
      };
      const grade: GradeEntry | null = parseGradeRow(item);
      expect(grade === null).assertFalse();
      if (grade !== null) {
        expect(grade.courseName).assertEqual('高等数学A(一)');
        expect(grade.scoreView).assertEqual('92');
        expect(grade.gpaPoint).assertEqual(4.0);
        expect(grade.credit).assertEqual(5);
        expect(grade.termCode).assertEqual('2025-2026-1');
        expect(grade.natureText).assertEqual('必修');
        expect(grade.examTypeText).assertEqual('考试');
        expect(grade.passed).assertTrue();
      }
    });
    it('parseGradeRow_camel_view_fallback', 0, () => {
      const item: GradeItemRaw = {
        courseName: '大学物理',
        scoreView: '免修',
        gpa: 3.6,
        credit: 4,
        courseSelectionSchoolYearTermCode: '2025-2026-2',
        courseNature: '02'
      };
      const grade: GradeEntry | null = parseGradeRow(item);
      expect(grade === null).assertFalse();
      if (grade !== null) {
        expect(grade.courseName).assertEqual('大学物理');
        expect(grade.scoreView).assertEqual('免修');
        expect(grade.gpaPoint).assertEqual(3.6);
        expect(grade.credit).assertEqual(4);
        expect(grade.termCode).assertEqual('2025-2026-2');
        expect(grade.natureText).assertEqual('选修');
        expect(grade.passed).assertTrue();
      }
    });
    it('parseGradeRow_40_view_priority_over_camel', 0, () => {
      const item: GradeItemRaw = { KCM: '库视图课', CJ: '80', courseName: '驼峰视图课', scoreView: '90' };
      const grade: GradeEntry | null = parseGradeRow(item);
      expect(grade === null).assertFalse();
      if (grade !== null) {
        expect(grade.courseName).assertEqual('库视图课');
        expect(grade.scoreView).assertEqual('80');
      }
    });
    it('stripCourseCodeSuffix_removes_trailing_code', 0, () => {
      expect(stripCourseCodeSuffix('医用高等数学[w1800033]')).assertEqual('医用高等数学');
      expect(stripCourseCodeSuffix('医学导论（限）[w3210652]')).assertEqual('医学导论（限）');
      expect(stripCourseCodeSuffix('无括号课程')).assertEqual('无括号课程');
      expect(stripCourseCodeSuffix('[w1800033]')).assertEqual('[w1800033]');
      expect(stripCourseCodeSuffix('')).assertEqual('');
    });
    it('parseGradeRow_tdkcm_fallback_when_kcm_null', 0, () => {
      const item: GradeItemRaw = {
        TDKCM: '人体系统解剖学[w1100051]',
        CJ: '61.6',
        JD: 1.16,
        XF: 4,
        XKXNXQDM: '2025-2026-1',
        KCXZDM_DISPLAY: '必修课',
        KSLXDM_DISPLAY: '考试'
      };
      const grade: GradeEntry | null = parseGradeRow(item);
      expect(grade === null).assertFalse();
      if (grade !== null) {
        expect(grade.courseName).assertEqual('人体系统解剖学');
        expect(grade.scoreView).assertEqual('61.6');
        expect(grade.credit).assertEqual(4);
        expect(grade.termCode).assertEqual('2025-2026-1');
        expect(grade.passed).assertTrue();
      }
    });
    it('parseGradeRow_kcm_priority_over_tdkcm', 0, () => {
      const item: GradeItemRaw = { KCM: '库视图课', TDKCM: '替代课[w1]', CJ: '80' };
      const grade: GradeEntry | null = parseGradeRow(item);
      expect(grade === null).assertFalse();
      if (grade !== null) {
        expect(grade.courseName).assertEqual('库视图课');
      }
    });
    it('parseGrades_substitution_rows_parsed', 0, () => {
      const items: GradeItemRaw[] = [
        { TDKCM: '医用高等数学[w1800033]', CJ: '不及格', XKXNXQDM: '2025-2026-1' },
        { TDKCM: '大学英语Ⅱ[w4410221]', CJ: '77', XKXNXQDM: '2025-2026-2' }
      ];
      const result: GradeEntry[] = parseGrades(items);
      expect(result.length).assertEqual(2);
      expect(result[0].courseName).assertEqual('医用高等数学');
      expect(result[0].passed).assertFalse();
      expect(result[1].courseName).assertEqual('大学英语Ⅱ');
      expect(result[1].scoreView).assertEqual('77');
    });
    it('parseGrades_empty_for_null_or_undefined', 0, () => {
      expect(parseGrades(undefined).length).assertEqual(0);
      expect(parseGrades(null).length).assertEqual(0);
    });
    it('parseGrades_filters_invalid_rows', 0, () => {
      const items: GradeItemRaw[] = [
        { KCM: '线性代数', CJ: '85' },
        { CJ: '99' },
        { KCM: '未出分课', CJ: '' }
      ];
      const result: GradeEntry[] = parseGrades(items);
      expect(result.length).assertEqual(1);
      expect(result[0].courseName).assertEqual('线性代数');
    });
    it('parseGradeCategories_empty_for_null', 0, () => {
      expect(parseGradeCategories(null).length).assertEqual(0);
      expect(parseGradeCategories(undefined).length).assertEqual(0);
    });
    it('parseGradeCategories_groups_and_drops_empty', 0, () => {
      const fan: FanTreeRaw = {
        children: [
          {
            name: '专业基础课',
            data: [
              { KCM: '高等数学A(一)', CJ: '92', XF: '5', JD: '4.0' },
              { KCM: '未出分', CJ: '' }
            ]
          },
          { name: '公共课', data: [{ KCM: '大学英语', CJ: '' }] },
          { courseCategoryName: '驼峰分组', checkCourseVOS: [{ courseName: '体育', scoreView: '95' }] }
        ]
      };
      const result = parseGradeCategories(fan);
      expect(result.length).assertEqual(2);
      expect(result[0].name).assertEqual('专业基础课');
      expect(result[0].grades.length).assertEqual(1);
      expect(result[1].name).assertEqual('驼峰分组');
      expect(result[1].grades[0].courseName).assertEqual('体育');
    });
  });
}
