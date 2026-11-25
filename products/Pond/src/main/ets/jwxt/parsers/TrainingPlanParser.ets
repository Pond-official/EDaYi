import { GradeEntry, PlanCategory, PlanCourse } from '../../model/JwModels';
import { FanCategoryRaw, FanTreeRaw, GradeItemRaw, StudentFaRaw } from '../../model/JwRawModels';
import { rawNumber } from './GradeParser';

export function extractPyfadm(faArr?: StudentFaRaw[]): string {
  if (faArr === undefined || faArr.length === 0) {
    return '';
  }
  for (const fa of faArr) {
    if (fa.PYFADM !== undefined && fa.PYFADM.length > 0) {
      return fa.PYFADM;
    }
  }
  return '';
}

/**
 * 课程名精确匹配取最新学期成绩（重修双行取后修成绩，同学期取后出现行）。
 */
function latestScoreOf(grades: GradeEntry[], courseName: string): string {
  let best: GradeEntry | null = null;
  for (const grade of grades) {
    if (grade.courseName !== courseName || grade.scoreView.length === 0) {
      continue;
    }
    if (best === null || grade.termCode >= best.termCode) {
      best = grade;
    }
  }
  return best === null ? '' : best.scoreView;
}

/**
 * 培养计划（方案内全部课程，含未修读）：
 * 分组与顺序保持服务端返回（专业基础课/专业课/公共课/实习），
 * 开课学期取 JHXNXQDM，已修读课程带成绩展示值；空分组保留（界面空态）。
 * 教务升级后 fanbx 行 CJ 恒为 null，已修成绩以 grades（成绩综合查询全集）按课程名回填。
 */
export function parseTrainingPlan(fan?: FanTreeRaw | null, grades?: GradeEntry[] | null): PlanCategory[] {
  const list: PlanCategory[] = [];
  const children: FanCategoryRaw[] | undefined = fan?.children ?? undefined;
  if (children === undefined) {
    return list;
  }
  for (const child of children) {
    let name: string = child.name ?? '';
    if (name.length === 0) {
      name = child.courseCategoryName ?? '';
    }
    if (name.length === 0) {
      continue;
    }
    const category: PlanCategory = new PlanCategory();
    category.name = name;
    const rows: GradeItemRaw[] | null | undefined = child.data ?? child.checkCourseVOS;
    if (rows !== undefined && rows !== null) {
      for (const row of rows) {
        let courseName: string = row.KCM ?? '';
        if (courseName.length === 0) {
          courseName = row.courseName ?? '';
        }
        if (courseName.length === 0) {
          continue;
        }
        const course: PlanCourse = new PlanCourse();
        course.courseName = courseName;
        course.credit = rawNumber(row.XF ?? row.credit);
        course.natureText = row.KCXZDM_DISPLAY ?? '';
        if (course.natureText.length === 0 && row.courseNature !== undefined) {
          course.natureText = row.courseNature === '01' ? '必修' : '选修';
        }
        course.examTypeText = row.KSLXDM_DISPLAY ?? '';
        course.plannedTerm = row.JHXNXQDM ?? '';
        course.scoreView = row.CJ ?? row.scoreView ?? '';
        if (course.scoreView.length === 0 && grades !== undefined && grades !== null) {
          course.scoreView = latestScoreOf(grades, courseName);
        }
        category.courses.push(course);
      }
    }
    list.push(category);
  }
  return list;
}
