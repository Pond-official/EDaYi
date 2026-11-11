import { describe, it, expect } from '@ohos/hypium';
import { parseTrainingPlan, extractPyfadm } from '../main/ets/jwxt/parsers/TrainingPlanParser';
import { PlanCategory } from '../main/ets/model/JwModels';
import { FanTreeRaw, StudentFaRaw } from '../main/ets/model/JwRawModels';

export default function trainingPlanParserTest() {
  describe('TrainingPlanParser', () => {
    it('extractPyfadm_empty_for_missing_input', 0, () => {
      expect(extractPyfadm(undefined)).assertEqual('');
      expect(extractPyfadm([])).assertEqual('');
    });
    it('extractPyfadm_returns_first_non_empty', 0, () => {
      const faArr: StudentFaRaw[] = [
        { PYFADM: '', PYFAMC: '空方案' },
        { PYFADM: 'FA2023CLSX001', PYFAMC: '临床医学' }
      ];
      expect(extractPyfadm(faArr)).assertEqual('FA2023CLSX001');
    });
    it('extractPyfadm_empty_when_all_missing', 0, () => {
      const faArr: StudentFaRaw[] = [{ PYFAMC: '无名方案' }];
      expect(extractPyfadm(faArr)).assertEqual('');
    });
    it('parseTrainingPlan_empty_for_null', 0, () => {
      expect(parseTrainingPlan(null).length).assertEqual(0);
      expect(parseTrainingPlan(undefined).length).assertEqual(0);
    });
    it('parseTrainingPlan_keeps_groups_and_courses', 0, () => {
      const fan: FanTreeRaw = {
        children: [
          {
            name: '专业基础课',
            data: [
              {
                KCM: '系统解剖学',
                XF: '5',
                KCXZDM_DISPLAY: '必修',
                KSLXDM_DISPLAY: '考试',
                JHXNXQDM: '2025-2026-1',
                CJ: '88'
              },
              { KCM: '生物化学', XF: '4.5', courseNature: '01', JHXNXQDM: '2025-2026-2' }
            ]
          },
          {
            courseCategoryName: '公共课',
            checkCourseVOS: [
              { courseName: '医学英语', credit: 2, courseNature: '02', JHXNXQDM: '2026-2027-1' }
            ]
          }
        ]
      };
      const result: PlanCategory[] = parseTrainingPlan(fan);
      expect(result.length).assertEqual(2);
      expect(result[0].name).assertEqual('专业基础课');
      expect(result[0].courses.length).assertEqual(2);
      expect(result[0].courses[0].courseName).assertEqual('系统解剖学');
      expect(result[0].courses[0].credit).assertEqual(5);
      expect(result[0].courses[0].plannedTerm).assertEqual('2025-2026-1');
      expect(result[0].courses[0].scoreView).assertEqual('88');
      expect(result[0].courses[1].natureText).assertEqual('必修');
      expect(result[1].name).assertEqual('公共课');
      expect(result[1].courses[0].natureText).assertEqual('选修');
    });
    it('parseTrainingPlan_keeps_empty_group', 0, () => {
      const fan: FanTreeRaw = {
        children: [
          { name: '实习', data: [] }
        ]
      };
      const result: PlanCategory[] = parseTrainingPlan(fan);
      expect(result.length).assertEqual(1);
      expect(result[0].name).assertEqual('实习');
      expect(result[0].courses.length).assertEqual(0);
    });
    it('parseTrainingPlan_skips_unnamed_group', 0, () => {
      const fan: FanTreeRaw = {
        children: [
          { data: [] },
          { name: '专业课', data: [{ KCM: '病理学', XF: '4' }] }
        ]
      };
      const result: PlanCategory[] = parseTrainingPlan(fan);
      expect(result.length).assertEqual(1);
      expect(result[0].name).assertEqual('专业课');
    });
  });
}
