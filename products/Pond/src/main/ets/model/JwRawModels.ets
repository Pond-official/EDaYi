/**
 * jwxt 教务系统接口原始返回结构（Raw 视图）：
 * 全部字段可选，按服务端两套视图（40 字段库视图 / 驼峰视图）原样建模，
 * 由解析层负责转换为领域模型。
 */

export interface CurrentUserRaw {
  code?: string;
  datas?: CurrentUserDataRaw;
}

export interface CurrentUserDataRaw {
  userName?: string;
  userId?: string;
  welcomeInfo?: WelcomeInfoRaw;
}

export interface WelcomeInfoRaw {
  classWeek?: number;
  xnxqdm?: string;
  xnxqmc?: string;
}

export interface TermQueryRaw {
  code?: string;
  datas?: TermQueryDataRaw;
}

export interface TermQueryDataRaw {
  cxmrxnxq?: TermCodeRaw;
}

export interface TermCodeRaw {
  rows?: TermRowRaw[];
}

export interface TermRowRaw {
  XNXQDM?: string;
  XNXQMC?: string;
}

export interface ScheduleEnvelopeRaw {
  code?: string;
  datas?: ScheduleDatasRaw;
}

export interface ScheduleDatasRaw {
  getMyScheduleDetail?: ScheduleDetailRaw;
  getMySectionList?: SectionItemRaw[];
}

export interface ScheduleDetailRaw {
  arrangedList?: ScheduleItemRaw[];
}

export interface ScheduleItemRaw {
  courseName?: string;
  dayOfWeek?: number;
  beginSection?: number;
  endSection?: number;
  week?: string;
  beginTime?: string;
  endTime?: string;
  placeName?: string;
  weeksAndTeachers?: string;
  color?: string;
  courseSerialNo?: string;
}

export interface SectionItemRaw {
  code?: number;
  name?: string;
}

export interface GradeEnvelopeRaw {
  code?: string;
  datas?: GradeDatasRaw;
}

export interface GradeDatasRaw {
  queryXyzhbx?: GradeReportRaw;
}

export interface GradeReportRaw {
  /** 方案外课程（驼峰视图，兼容旧结构） */
  fawbx?: GradeItemRaw[] | null;
  /** 方案外课程（40 字段库视图，权威数据源） */
  fawbxMap?: GradeItemRaw[] | null;
  fanbx?: FanTreeRaw | null;
  calculatedTime?: string;
}

export interface FanTreeRaw {
  children?: FanCategoryRaw[] | null;
}

export interface FanCategoryRaw {
  /** 分组名（40 字段视图：专业基础课/专业课/公共课/实习） */
  name?: string;
  /** 分组课程（40 字段库视图，权威数据源） */
  data?: GradeItemRaw[] | null;
  /** 分组名（驼峰视图，兼容旧结构） */
  courseCategoryName?: string;
  /** 分组课程（驼峰视图，兼容旧结构） */
  checkCourseVOS?: GradeItemRaw[] | null;
}

/**
 * 成绩/培养计划课程行，兼容两套视图：
 * - 40 字段库视图（fanbx.children[].data[] / fawbxMap[]）：KCM/XF/CJ/JD/XKXNXQDM 等，权威数据源；
 * - 驼峰视图（fawbx / checkCourseVOS）：courseName/scoreView 等，兼容旧结构兜底。
 */
export interface GradeItemRaw {
  KCH?: string;
  KCM?: string;
  XF?: string | number;
  CJ?: string;
  FSCJ?: string;
  JD?: string | number;
  KCXZDM_DISPLAY?: string;
  KSLXDM_DISPLAY?: string;
  KCLBDM_DISPLAY?: string;
  XKXNXQDM?: string;
  CJXNXQDM?: string;
  JHXNXQDM?: string;
  courseName?: string;
  scoreView?: string;
  gpa?: number;
  credit?: number;
  courseSelectionSchoolYearTermCode?: string;
  courseNature?: string;
  passed?: boolean;
}

export interface StudentEnvelopeRaw {
  code?: string;
  datas?: StudentDatasRaw;
}

export interface StudentDatasRaw {
  queryXsjbxx?: StudentDetailRaw;
}

export interface StudentDetailRaw {
  jbxx?: StudentBasicRaw;
  faArr?: StudentFaRaw[];
}

export interface StudentBasicRaw {
  XM?: string;
  XH?: string;
  BJDM_DISPLAY?: string;
  ZYDM_DISPLAY?: string;
  YXDM_DISPLAY?: string;
  XZNJ_DISPLAY?: string;
}

export interface StudentFaRaw {
  PYFADM?: string;
  PYFAMC?: string;
  XDLXDM?: string;
}

/** 应用内离线缓存（最近一次同步的完整数据，会话过期时回显） */
export interface AppCacheRaw {
  student?: StudentCacheRaw;
  schedule?: CellCacheRaw[];
  grades?: GradeCacheRaw[];
  gradeCategories?: CategoryCacheRaw[];
  trainingPlan?: PlanCategoryCacheRaw[];
  sections?: SectionCacheRaw[];
  term?: TermCacheRaw;
}

export interface StudentCacheRaw {
  name?: string;
  studentId?: string;
  className?: string;
  majorName?: string;
  collegeName?: string;
  grade?: string;
}

export interface CellCacheRaw {
  courseName?: string;
  teacher?: string;
  location?: string;
  dayOfWeek?: number;
  startSection?: number;
  endSection?: number;
  weeksText?: string;
  weekBitmap?: string;
  startTime?: string;
  endTime?: string;
  colorHex?: string;
  courseSerialNo?: string;
}

export interface GradeCacheRaw {
  courseName?: string;
  scoreView?: string;
  gpaPoint?: number;
  credit?: number;
  termCode?: string;
  natureText?: string;
  examTypeText?: string;
  passed?: boolean;
}

export interface CategoryCacheRaw {
  name?: string;
  grades?: GradeCacheRaw[];
}

export interface PlanCourseCacheRaw {
  courseName?: string;
  credit?: number;
  natureText?: string;
  examTypeText?: string;
  plannedTerm?: string;
  scoreView?: string;
}

export interface PlanCategoryCacheRaw {
  name?: string;
  courses?: PlanCourseCacheRaw[];
}

export interface SectionCacheRaw {
  section?: number;
  name?: string;
  timeText?: string;
}

export interface TermCacheRaw {
  termCode?: string;
  termName?: string;
  currentWeek?: number;
}
