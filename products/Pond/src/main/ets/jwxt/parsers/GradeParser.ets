import { GradeCategory, GradeEntry } from '../../model/JwModels';
import { FanCategoryRaw, FanTreeRaw, GradeItemRaw } from '../../model/JwRawModels';

/** 库视图数值字段（XF/JD 可能是字符串或数字）转数字，非法返回 0 */
export function rawNumber(value: string | number | undefined): number {
  if (typeof value === 'number') {
    return value;
  }
  if (value === undefined || value.length === 0) {
    return 0;
  }
  const parsed: number = Number(value);
  return Number.isNaN(parsed) ? 0 : parsed;
}

/** 成绩展示值推断是否通过：等级制含"不及格/不合格/未通过"为未过；百分制 >=60 为过；其余等级默认通过 */
export function isPassedScore(scoreView: string): boolean {
  if (scoreView.length === 0) {
    return false;
  }
  if (scoreView.indexOf('不及格') >= 0 || scoreView.indexOf('不合格') >= 0
    || scoreView.indexOf('未通过') >= 0) {
    return false;
  }
  const numeric: number = Number(scoreView);
  if (!Number.isNaN(numeric)) {
    return numeric >= 60;
  }
  return true;
}

/**
 * 单行成绩解析，兼容两套视图：
 * - 40 字段库视图（KCM/CJ/JD/XF/XKXNXQDM/KCXZDM_DISPLAY）优先；
 * - 驼峰视图（courseName/scoreView/gpa/credit/courseSelectionSchoolYearTermCode）兜底。
 * 未出分（空）与成绩为 0 的行丢弃；行内无课程名返回 null。
 */
export function parseGradeRow(item: GradeItemRaw): GradeEntry | null {
  const name40: string = item.KCM ?? '';
  if (name40.length > 0) {
    const scoreView: string = item.CJ ?? '';
    if (scoreView.length === 0 || scoreView === '0') {
      return null;
    }
    const grade: GradeEntry = new GradeEntry();
    grade.courseName = name40;
    grade.scoreView = scoreView;
    grade.gpaPoint = rawNumber(item.JD);
    grade.credit = rawNumber(item.XF);
    let termCode: string = item.XKXNXQDM ?? '';
    if (termCode.length === 0) {
      termCode = item.CJXNXQDM ?? '';
    }
    grade.termCode = termCode;
    grade.natureText = item.KCXZDM_DISPLAY ?? '';
    grade.examTypeText = item.KSLXDM_DISPLAY ?? '';
    grade.passed = isPassedScore(scoreView);
    return grade;
  }
  const nameCc: string = item.courseName ?? '';
  if (nameCc.length === 0) {
    return null;
  }
  const scoreCc: string = item.scoreView ?? '';
  if (scoreCc.length === 0 || scoreCc === '0') {
    return null;
  }
  const grade: GradeEntry = new GradeEntry();
  grade.courseName = nameCc;
  grade.scoreView = scoreCc;
  grade.gpaPoint = item.gpa ?? 0;
  grade.credit = item.credit ?? 0;
  grade.termCode = item.courseSelectionSchoolYearTermCode ?? '';
  grade.natureText = item.courseNature === '01' ? '必修' : '选修';
  grade.passed = item.passed ?? true;
  return grade;
}

export function parseGrades(items?: GradeItemRaw[] | null): GradeEntry[] {
  const list: GradeEntry[] = [];
  if (items === undefined || items === null) {
    return list;
  }
  for (const item of items) {
    const grade: GradeEntry | null = parseGradeRow(item);
    if (grade !== null) {
      list.push(grade);
    }
  }
  return list;
}

/**
 * 培养方案分类成绩（专业基础课/专业课/公共课/实习等）：
 * 仅保留已有成绩的科目，未出分（空）与成绩为 0 的科目自动隐藏。
 */
export function parseGradeCategories(fan?: FanTreeRaw | null): GradeCategory[] {
  const list: GradeCategory[] = [];
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
    const category: GradeCategory = new GradeCategory();
    category.name = name;
    category.grades = parseGrades(child.data ?? child.checkCourseVOS);
    if (category.grades.length > 0) {
      list.push(category);
    }
  }
  return list;
}
