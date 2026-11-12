/**
 * 教务系统（jwxt.dmu.edu.cn）数据模型。
 * 字段依据 2026-10-18 对 jwxt 接口的实测抓包还原。
 */
export class StudentProfile {
  name: string = '';
  studentId: string = '';
  className: string = '';
  majorName: string = '';
  collegeName: string = '';
  grade: string = '';
}

export class ScheduleCellInfo {
  courseName: string = '';
  teacher: string = '';
  location: string = '';
  dayOfWeek: number = 1;
  startSection: number = 1;
  endSection: number = 1;
  weeksText: string = '';
  /** 周位图：第 i 位（从 1 起）为 '1' 表示第 i 周有此课，长度为学期教学周数 */
  weekBitmap: string = '';
  startTime: string = '';
  endTime: string = '';
  colorHex: string = '#E8F3DB';
  courseSerialNo: string = '';

  /**
   * 判断第 week 周是否有此课；周次未知（<=0）或位图缺失时保守视为有课。
   */
  activeInWeek(week: number): boolean {
    if (week <= 0) {
      return true;
    }
    if (this.weekBitmap.length === 0) {
      return true;
    }
    const idx: number = week - 1;
    if (idx >= this.weekBitmap.length) {
      return false;
    }
    return this.weekBitmap.charAt(idx) === '1';
  }

  /** 单课提醒开关键：课程名+星期+起始节次（内容寻址，跨周数据同步后保持一致） */
  reminderKey(): string {
    return this.courseName + '|' + this.dayOfWeek + '|' + this.startSection;
  }
}

export class GradeEntry {
  courseName: string = '';
  scoreView: string = '';
  gpaPoint: number = 0;
  credit: number = 0;
  termCode: string = '';
  natureText: string = '';
  /** 考核方式（考试/考查，KSLXDM_DISPLAY） */
  examTypeText: string = '';
  passed: boolean = true;
}

export class GradeCategory {
  name: string = '';
  grades: GradeEntry[] = [];
}

/** 培养计划课程（方案内，来自个人学业监测报告 40 字段库视图） */
export class PlanCourse {
  courseName: string = '';
  credit: number = 0;
  /** 课程性质（必修/选修/限选） */
  natureText: string = '';
  /** 考核方式（考试/考查，KSLXDM_DISPLAY） */
  examTypeText: string = '';
  /** 计划开课学期（JHXNXQDM，如 2025-2026-1，可能为空） */
  plannedTerm: string = '';
  /** 已修读成绩展示值（未出分为空） */
  scoreView: string = '';
}

/** 培养计划分组（专业基础课/专业课/公共课/实习，保持服务端顺序） */
export class PlanCategory {
  name: string = '';
  courses: PlanCourse[] = [];
}

export class SectionTimeInfo {
  section: number = 1;
  name: string = '';
  timeText: string = '';
}

export class TermStatus {
  termCode: string = '';
  termName: string = '';
  currentWeek: number = 0;
}

/** 课程期末考试时间设置（按课程名，用户在"设置-期末倒计时"中设定） */
export class FinalExamEntry {
  courseName: string = '';
  /** 期末考试时间（'YYYY-MM-DD HH:mm'，旧版 'YYYY-MM-DD' 数据视为当天 23:59） */
  examDate: string = '';
}
