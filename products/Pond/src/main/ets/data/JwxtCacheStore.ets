import { common } from '@kit.AbilityKit';
import { AppLog } from './AppLog';
import { CacheManager } from './CacheManager';
import { CardCellItem, CardDataStore } from './CardDataStore';
import { PrivacyController } from './PrivacyController';
import { ZcpRepository } from './ZcpRepository';
import { getContext } from '../net/JwTransport';
import { GradeCategory, GradeEntry, PlanCategory, PlanCourse, ScheduleCellInfo, SectionTimeInfo, StudentProfile, TermStatus } from '../model/JwModels';
import { AppCacheRaw, CategoryCacheRaw, CellCacheRaw, GradeCacheRaw, PlanCategoryCacheRaw, PlanCourseCacheRaw, SectionCacheRaw, StudentCacheRaw, TermCacheRaw } from '../model/JwRawModels';

const TAG: string = 'JwxtRepository';
const DOMAIN: number = 0x0000;

/**
 * 教务本地缓存仓库（自 JwxtRepository 拆出）：
 * 负责缓存体积统计、缓存清理、桌面卡片课表持久化、
 * 应用内离线缓存（JSON 序列化/反序列化）的读写与回放。
 */
export class JwxtCacheStore {
  /** 查询本地缓存大小（字节，应用级+模块级 cacheDir 与综评本地缓存文件），无上下文时返回 0 */
  static getCacheSizeBytes(): number {
    const context: common.UIAbilityContext | null = getContext();
    if (context === null) {
      return 0;
    }
    const appCacheDir: string = context.getApplicationContext().cacheDir;
    const abilityCacheDir: string = context.cacheDir;
    let bytes: number = CacheManager.dirSize(appCacheDir);
    if (abilityCacheDir !== appCacheDir) {
      bytes += CacheManager.dirSize(abilityCacheDir);
    }
    // 综评缓存存于 filesDir（不在 cacheDir 内），随"清理缓存"一并清除，统计时单独计入
    bytes += ZcpRepository.cacheSizeBytes();
    AppLog.info(DOMAIN, TAG, 'cacheDir=%{public}s abilityDir=%{public}s size=%{public}d',
      appCacheDir, abilityCacheDir, bytes);
    return bytes;
  }

  /** 清理本地缓存：应用级/模块级 cacheDir（网页内核缓存等）+ 离线数据缓存；
   * 同步清空内存中的成绩数据（成绩页立即回到空态，可经主页"刷新"重新在线同步）；
   * 卡片数据与 Cookie 不受影响 */
  static clearLocalCaches(): void {
    const context: common.UIAbilityContext | null = getContext();
    if (context === null) {
      return;
    }
    const appCacheDir: string = context.getApplicationContext().cacheDir;
    const abilityCacheDir: string = context.cacheDir;
    CacheManager.clearDir(appCacheDir);
    if (abilityCacheDir !== appCacheDir) {
      CacheManager.clearDir(abilityCacheDir);
    }
    CardDataStore.clearAppCache(context);
    AppStorage.setOrCreate<GradeEntry[]>('jwGrades', []);
    AppStorage.setOrCreate<GradeCategory[]>('jwGradeCategories', []);
    AppStorage.setOrCreate<PlanCategory[]>('jwTrainingPlan', []);
    // 综评数据与成绩同级：清缓存同时清空内存态与临时缓存（会话保留，重进页签可重新在线获取）
    ZcpRepository.clearMemory();
    ZcpRepository.clearCache();
  }

  /**
   * 把本周/下周课表持久化到应用级 preferences（单 key 覆盖旧数据），
   * 并刷新已添加的服务卡片。仅在同步成功后调用；
   * 退出登录或离线失败时不清除，卡片继续显示最近一次课表。
   */
  static persistCardData(): void {
    const context: common.Context | null = getContext();
    if (context === null) {
      return;
    }
    if (PrivacyController.privacyMode() === 'strict') {
      return;
    }
    const cells: ScheduleCellInfo[] =
      AppStorage.get<ScheduleCellInfo[]>('jwSchedule') ?? [];
    const term: TermStatus = AppStorage.get<TermStatus>('jwTerm') ?? new TermStatus();
    const payload: Record<string, Object> = {
      'week': term.currentWeek,
      'cells': JwxtCacheStore.toCardCells(cells)
    };
    CardDataStore.saveAndRefresh(context, JSON.stringify(payload));
  }

  private static toCardCells(cells: ScheduleCellInfo[]): CardCellItem[] {
    const list: CardCellItem[] = [];
    for (const cell of cells) {
      const item: CardCellItem = new CardCellItem();
      item.d = cell.dayOfWeek;
      item.s = cell.startSection;
      item.e = cell.endSection;
      item.n = cell.courseName;
      item.p = cell.location;
      item.t = cell.startTime;
      item.w = cell.weekBitmap;
      item.c = cell.colorHex;
      item.r = cell.teacher;
      list.push(item);
    }
    return list;
  }

  /**
   * 把最近一次同步的完整数据（学生/课表/成绩/节次/学期）持久化为应用内离线缓存，
   * 会话过期或冷启动同步失败时回显，界面提示"离线数据，请重新登录"。
   */
  static persistAppCache(): void {
    const context: common.Context | null = getContext();
    if (context === null) {
      return;
    }
    if (PrivacyController.privacyMode() !== 'standard') {
      return;
    }
    CardDataStore.saveAppCache(context, JwxtCacheStore.buildAppCacheJson());
    AppLog.info(DOMAIN, TAG, 'app cache persisted');
  }

  private static buildAppCacheJson(): string {
    const student: StudentProfile = AppStorage.get<StudentProfile>('jwStudent') ?? new StudentProfile();
    const cells: ScheduleCellInfo[] = AppStorage.get<ScheduleCellInfo[]>('jwSchedule') ?? [];
    const grades: GradeEntry[] = AppStorage.get<GradeEntry[]>('jwGrades') ?? [];
    const categories: GradeCategory[] = AppStorage.get<GradeCategory[]>('jwGradeCategories') ?? [];
    const trainingPlan: PlanCategory[] = AppStorage.get<PlanCategory[]>('jwTrainingPlan') ?? [];
    const sections: SectionTimeInfo[] = AppStorage.get<SectionTimeInfo[]>('jwSections') ?? [];
    const term: TermStatus = AppStorage.get<TermStatus>('jwTerm') ?? new TermStatus();
    const cellRaws: CellCacheRaw[] = [];
    for (const cell of cells) {
      cellRaws.push({
        courseName: cell.courseName,
        teacher: cell.teacher,
        location: cell.location,
        dayOfWeek: cell.dayOfWeek,
        startSection: cell.startSection,
        endSection: cell.endSection,
        weeksText: cell.weeksText,
        weekBitmap: cell.weekBitmap,
        startTime: cell.startTime,
        endTime: cell.endTime,
        colorHex: cell.colorHex,
        courseSerialNo: cell.courseSerialNo
      });
    }
    const gradeRaws: GradeCacheRaw[] = [];
    for (const grade of grades) {
      gradeRaws.push({
        courseName: grade.courseName,
        scoreView: grade.scoreView,
        gpaPoint: grade.gpaPoint,
        credit: grade.credit,
        termCode: grade.termCode,
        natureText: grade.natureText,
        examTypeText: grade.examTypeText,
        passed: grade.passed
      });
    }
    const categoryRaws: CategoryCacheRaw[] = [];
    for (const category of categories) {
      const categoryGrades: GradeCacheRaw[] = [];
      for (const grade of category.grades) {
        categoryGrades.push({
          courseName: grade.courseName,
          scoreView: grade.scoreView,
          gpaPoint: grade.gpaPoint,
          credit: grade.credit,
          termCode: grade.termCode,
          natureText: grade.natureText,
          examTypeText: grade.examTypeText,
          passed: grade.passed
        });
      }
      categoryRaws.push({ name: category.name, grades: categoryGrades });
    }
    const planRaws: PlanCategoryCacheRaw[] = [];
    for (const category of trainingPlan) {
      const courseRaws: PlanCourseCacheRaw[] = [];
      for (const course of category.courses) {
        courseRaws.push({
          courseName: course.courseName,
          credit: course.credit,
          natureText: course.natureText,
          examTypeText: course.examTypeText,
          plannedTerm: course.plannedTerm,
          scoreView: course.scoreView
        });
      }
      planRaws.push({ name: category.name, courses: courseRaws });
    }
    const sectionRaws: SectionCacheRaw[] = [];
    for (const section of sections) {
      sectionRaws.push({
        section: section.section,
        name: section.name,
        timeText: section.timeText
      });
    }
    const raw: AppCacheRaw = {
      student: {
        name: student.name,
        studentId: student.studentId,
        className: student.className,
        majorName: student.majorName,
        collegeName: student.collegeName,
        grade: student.grade
      },
      schedule: cellRaws,
      grades: gradeRaws,
      gradeCategories: categoryRaws,
      trainingPlan: planRaws,
      sections: sectionRaws,
      term: {
        termCode: term.termCode,
        termName: term.termName,
        currentWeek: term.currentWeek
      }
    };
    return JSON.stringify(raw);
  }

  /**
   * 同步失败时尝试回放离线缓存；无缓存或解析失败返回 false（调用方退回空态）。
   */
  static applyAppCache(): boolean {
    const context: common.Context | null = getContext();
    if (context === null) {
      return false;
    }
    const cacheJson: string = CardDataStore.loadAppCache(context);
    if (cacheJson.length === 0) {
      return false;
    }
    try {
      const raw: AppCacheRaw = JSON.parse(cacheJson) as AppCacheRaw;
      const student: StudentProfile = new StudentProfile();
      const studentRaw: StudentCacheRaw | undefined = raw.student;
      if (studentRaw !== undefined) {
        student.name = studentRaw.name ?? '';
        student.studentId = studentRaw.studentId ?? '';
        student.className = studentRaw.className ?? '';
        student.majorName = studentRaw.majorName ?? '';
        student.collegeName = studentRaw.collegeName ?? '';
        student.grade = studentRaw.grade ?? '';
      }
      const cells: ScheduleCellInfo[] = [];
      const cellRaws: CellCacheRaw[] | undefined = raw.schedule;
      if (cellRaws !== undefined) {
        for (const item of cellRaws) {
          if (item.courseName === undefined) {
            continue;
          }
          const cell: ScheduleCellInfo = new ScheduleCellInfo();
          cell.courseName = item.courseName;
          cell.teacher = item.teacher ?? '';
          cell.location = item.location ?? '';
          cell.dayOfWeek = item.dayOfWeek ?? 1;
          cell.startSection = item.startSection ?? 1;
          cell.endSection = item.endSection ?? item.startSection ?? 1;
          cell.weeksText = item.weeksText ?? '';
          cell.weekBitmap = item.weekBitmap ?? '';
          cell.startTime = item.startTime ?? '';
          cell.endTime = item.endTime ?? '';
          cell.colorHex = item.colorHex ?? '#E8F3DB';
          cell.courseSerialNo = item.courseSerialNo ?? '';
          cells.push(cell);
        }
      }
      const grades: GradeEntry[] = JwxtCacheStore.cacheGrades(raw.grades);
      const categories: GradeCategory[] = [];
      const categoryRaws: CategoryCacheRaw[] | undefined = raw.gradeCategories;
      if (categoryRaws !== undefined) {
        for (const item of categoryRaws) {
          const category: GradeCategory = new GradeCategory();
          category.name = item.name ?? '';
          category.grades = JwxtCacheStore.cacheGrades(item.grades);
          if (category.grades.length > 0) {
            categories.push(category);
          }
        }
      }
      const trainingPlan: PlanCategory[] = [];
      const planRaws: PlanCategoryCacheRaw[] | undefined = raw.trainingPlan;
      if (planRaws !== undefined) {
        for (const item of planRaws) {
          const category: PlanCategory = new PlanCategory();
          category.name = item.name ?? '';
          const courseRaws: PlanCourseCacheRaw[] | undefined = item.courses;
          if (courseRaws !== undefined) {
            for (const courseRaw of courseRaws) {
              const course: PlanCourse = new PlanCourse();
              course.courseName = courseRaw.courseName ?? '';
              course.credit = courseRaw.credit ?? 0;
              course.natureText = courseRaw.natureText ?? '';
              course.examTypeText = courseRaw.examTypeText ?? '';
              course.plannedTerm = courseRaw.plannedTerm ?? '';
              course.scoreView = courseRaw.scoreView ?? '';
              category.courses.push(course);
            }
          }
          trainingPlan.push(category);
        }
      }
      const sections: SectionTimeInfo[] = [];
      const sectionRaws: SectionCacheRaw[] | undefined = raw.sections;
      if (sectionRaws !== undefined) {
        for (const item of sectionRaws) {
          const section: SectionTimeInfo = new SectionTimeInfo();
          section.section = item.section ?? 0;
          section.name = item.name ?? '';
          section.timeText = item.timeText ?? '';
          sections.push(section);
        }
      }
      const term: TermStatus = new TermStatus();
      const termRaw: TermCacheRaw | undefined = raw.term;
      if (termRaw !== undefined) {
        term.termCode = termRaw.termCode ?? '';
        term.termName = termRaw.termName ?? '';
        term.currentWeek = termRaw.currentWeek ?? 0;
      }
      AppStorage.setOrCreate<StudentProfile>('jwStudent', student);
      AppStorage.setOrCreate<ScheduleCellInfo[]>('jwSchedule', cells);
      AppStorage.setOrCreate<GradeEntry[]>('jwGrades', grades);
      AppStorage.setOrCreate<GradeCategory[]>('jwGradeCategories', categories);
      AppStorage.setOrCreate<PlanCategory[]>('jwTrainingPlan', trainingPlan);
      AppStorage.setOrCreate<SectionTimeInfo[]>('jwSections', sections);
      AppStorage.setOrCreate<TermStatus>('jwTerm', term);
      AppStorage.setOrCreate<string>('jwDataMode', 'offlineCache');
      AppStorage.setOrCreate<boolean>('jwLoaded', true);
      AppLog.info(DOMAIN, TAG,
        'app cache applied: cells=%{public}s grades=%{public}s cats=%{public}s sections=%{public}s',
        `${cells.length}`, `${grades.length}`, `${categories.length}`, `${sections.length}`);
      return true;
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'app cache parse failed: %{public}s', `${error}`);
      return false;
    }
  }

  private static cacheGrades(items?: GradeCacheRaw[]): GradeEntry[] {
    const list: GradeEntry[] = [];
    if (items === undefined) {
      return list;
    }
    for (const item of items) {
      if (item.courseName === undefined) {
        continue;
      }
      const grade: GradeEntry = new GradeEntry();
      grade.courseName = item.courseName;
      grade.scoreView = item.scoreView ?? '';
      grade.gpaPoint = item.gpaPoint ?? 0;
      grade.credit = item.credit ?? 0;
      grade.termCode = item.termCode ?? '';
      grade.natureText = item.natureText ?? '';
      grade.examTypeText = item.examTypeText ?? '';
      grade.passed = item.passed ?? true;
      list.push(grade);
    }
    return list;
  }
}
