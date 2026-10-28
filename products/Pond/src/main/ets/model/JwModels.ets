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
}

export class GradeEntry {
  courseName: string = '';
  scoreView: string = '';
  gpaPoint: number = 0;
  credit: number = 0;
  termCode: string = '';
  natureText: string = '';
  passed: boolean = true;
}

export class GradeCategory {
  name: string = '';
  grades: GradeEntry[] = [];
}

export class ElectiveCourseInfo {
  courseId: string = '';
  name: string = '';
  teacher: string = '';
  credit: number = 1;
  timeText: string = '';
  place: string = '';
  capacity: number = 60;
  selectedCount: number = 0;
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

/** 课程期末考试日期设置（按课程名，用户在课表课程详情中设定） */
export class FinalExamEntry {
  courseName: string = '';
  /** 期末考试日期（'YYYY-MM-DD'） */
  examDate: string = '';
}
