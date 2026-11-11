import { PlanCategory, PlanCourse } from '../../model/JwModels';
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
 * 培养计划（方案内全部课程，含未修读）：
 * 分组与顺序保持服务端返回（专业基础课/专业课/公共课/实习），
 * 开课学期取 JHXNXQDM，已修读课程带成绩展示值；空分组保留（界面空态）。
 */
export function parseTrainingPlan(fan?: FanTreeRaw | null): PlanCategory[] {
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
        category.courses.push(course);
      }
    }
    list.push(category);
  }
  return list;
}
