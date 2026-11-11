import { PlanCategory, PlanCourse } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from '../view/FrostBand';
import { BackButton } from '../view/BackButton';
import { GRADE_DEFAULT_BG, GRADE_DEFAULT_TEXT, GRADE_EXCELLENT_TEXT, GRADE_GOOD_BG,
  GRADE_GOOD_TEXT, GRADE_INSPECT_BG, GRADE_INSPECT_TEXT, GRADE_MEDIUM_TEXT, PASS_BG,
  REVIEW_BG, TAG_DEFAULT_BG } from '../theme/AppColors';

const TERM_ALL: string = '全部';
/** 开课学期未指定的课程归入此筛选项（排在最后） */
const TERM_UNSET: string = '未指定';
/** 课程性质/考核方式筛选的「全部」项 */
const FILTER_ALL: string = '全部';

/** 培养计划分组渲染数据（筛选后的快照，随筛选与数据变化重算） */
interface PlanSectionData {
  name: string;
  courses: PlanCourse[];
}

/**
 * 培养计划页：展示个人学业监测报告中的方案内课程
 * （专业基础课/专业课/公共课/实习，保持服务端分组与顺序），
 * 含学分、课程性质、计划开课学期与已修读成绩；
 * 支持按计划开课学期筛选（升序，未指定排最后）。
 * 数据与成绩同源（queryXyzhbx 一次请求），离线缓存回显。
 */
@Entry
@Component
struct TrainingPlanIndex {
  @StorageProp('jwTrainingPlan') @Watch('onPlanChanged') plan: PlanCategory[] = [];
  @StorageProp('jwDataMode') dataMode: string = 'preview';
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  @State selectedTerm: string = TERM_ALL;
  @State termChips: string[] = [TERM_ALL];
  /** 课程性质筛选（必修/限选/选修…按数据出现顺序去重） */
  @State selectedNature: string = FILTER_ALL;
  @State natureChips: string[] = [FILTER_ALL];
  /** 考核方式筛选（考试/考查…按数据出现顺序去重） */
  @State selectedExamType: string = FILTER_ALL;
  @State examChips: string[] = [FILTER_ALL];
  /** 按三项筛选后的分组快照（@Builder 按值传参不随状态刷新，故经 @State 驱动重建） */
  @State visibleSections: PlanSectionData[] = [];
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;

  aboutToAppear(): void {
    JwxtRepository.ensureLoaded();
    this.rebuildChips();
  }

  onPlanChanged(): void {
    this.rebuildChips();
  }

  private rebuildChips(): void {
    const terms: string[] = [];
    const natures: string[] = [];
    const examTypes: string[] = [];
    let hasUnset: boolean = false;
    for (const category of this.plan) {
      for (const course of category.courses) {
        if (course.plannedTerm.length === 0) {
          hasUnset = true;
        } else if (terms.indexOf(course.plannedTerm) < 0) {
          terms.push(course.plannedTerm);
        }
        if (course.natureText.length > 0 && natures.indexOf(course.natureText) < 0) {
          natures.push(course.natureText);
        }
        if (course.examTypeText.length > 0 && examTypes.indexOf(course.examTypeText) < 0) {
          examTypes.push(course.examTypeText);
        }
      }
    }
    // 开课学期升序，未指定排最后
    terms.sort((a: string, b: string): number => a < b ? -1 : (a > b ? 1 : 0));
    const chips: string[] = [TERM_ALL].concat(terms);
    if (hasUnset) {
      chips.push(TERM_UNSET);
    }
    this.termChips = chips;
    this.natureChips = [FILTER_ALL].concat(natures);
    this.examChips = [FILTER_ALL].concat(examTypes);
    if (this.selectedTerm !== TERM_ALL && chips.indexOf(this.selectedTerm) < 0) {
      this.selectedTerm = TERM_ALL;
    }
    if (this.selectedNature !== FILTER_ALL && this.natureChips.indexOf(this.selectedNature) < 0) {
      this.selectedNature = FILTER_ALL;
    }
    if (this.selectedExamType !== FILTER_ALL && this.examChips.indexOf(this.selectedExamType) < 0) {
      this.selectedExamType = FILTER_ALL;
    }
    this.rebuildSections();
  }

  /** 重算三项筛选后的分组快照，空分组剔除 */
  private rebuildSections(): void {
    const sections: PlanSectionData[] = [];
    for (const category of this.plan) {
      const filtered: PlanCourse[] = this.filteredCourses(category.courses);
      if (filtered.length > 0) {
        sections.push({ name: category.name, courses: filtered });
      }
    }
    this.visibleSections = sections;
  }

  /** 分组内容指纹：课程名+性质+考核+学期+成绩拼接，内容变化时 ForEach key 变化以重建分组 */
  private sectionFingerprint(items: PlanCourse[]): string {
    let fp: string = String(items.length);
    for (const course of items) {
      fp += '|' + course.courseName + course.natureText + course.examTypeText + course.plannedTerm + course.scoreView;
    }
    return fp;
  }

  private matchTerm(course: PlanCourse): boolean {
    if (this.selectedTerm === TERM_ALL) {
      return true;
    }
    const term: string = course.plannedTerm.length > 0 ? course.plannedTerm : TERM_UNSET;
    return term === this.selectedTerm;
  }

  /** 课程性质（必修/限选/选修…）与考核方式（考试/考查…）筛选 */
  private matchCourse(course: PlanCourse): boolean {
    if (!this.matchTerm(course)) {
      return false;
    }
    if (this.selectedNature !== FILTER_ALL && course.natureText !== this.selectedNature) {
      return false;
    }
    if (this.selectedExamType !== FILTER_ALL && course.examTypeText !== this.selectedExamType) {
      return false;
    }
    return true;
  }

  private filteredCourses(courses: PlanCourse[]): PlanCourse[] {
    return courses.filter((course: PlanCourse): boolean => this.matchCourse(course));
  }

  private creditsOf(courses: PlanCourse[]): number {
    let sum: number = 0;
    for (const course of courses) {
      sum += course.credit;
    }
    return sum;
  }

  private totalCourses(): number {
    let count: number = 0;
    for (const category of this.plan) {
      count += category.courses.length;
    }
    return count;
  }

  /** 学期码转显示文案："2025-2026-1" → "2025-2026学年1学期"，非该格式原样返回 */
  private formatTermLabel(termCode: string): string {
    const parts: string[] = termCode.split('-');
    if (parts.length === 3) {
      return parts[0] + '-' + parts[1] + '学年' + parts[2] + '学期';
    }
    return termCode;
  }

  /** 学期下拉按键选项列表（全部 + 开课学期升序 + 未指定） */
  private termOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const chip of this.termChips) {
      options.push({ value: this.formatTermLabel(chip) });
    }
    return options;
  }

  /** 当前选中学期在下拉列表中的索引 */
  private selectedTermIndex(): number {
    const index: number = this.termChips.indexOf(this.selectedTerm);
    return index < 0 ? 0 : index;
  }

  /** 当前选中学期显示文案 */
  private selectedTermLabel(): string {
    return this.formatTermLabel(this.selectedTerm);
  }

  /** 课程性质下拉选项（全部 + 数据出现顺序去重） */
  private natureOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const chip of this.natureChips) {
      options.push({ value: chip });
    }
    return options;
  }

  /** 当前选中课程性质在下拉列表中的索引 */
  private selectedNatureIndex(): number {
    const index: number = this.natureChips.indexOf(this.selectedNature);
    return index < 0 ? 0 : index;
  }

  /** 考核方式下拉选项（全部 + 数据出现顺序去重） */
  private examTypeOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const chip of this.examChips) {
      options.push({ value: chip });
    }
    return options;
  }

  /** 当前选中考核方式在下拉列表中的索引 */
  private selectedExamTypeIndex(): number {
    const index: number = this.examChips.indexOf(this.selectedExamType);
    return index < 0 ? 0 : index;
  }

  /** 课程副标题：学分与计划开课学期（性质/考核方式以标签展示在课程名后） */
  private courseSubtitle(course: PlanCourse): string {
    const parts: string[] = [];
    parts.push(course.credit + '学分');
    if (course.plannedTerm.length > 0) {
      parts.push('开课 ' + this.formatTermLabel(course.plannedTerm));
    }
    return parts.join(' · ');
  }

  private scoreColor(score: string): string {
    if (score === '优秀') {
      return GRADE_EXCELLENT_TEXT;
    }
    if (score === '良好') {
      return GRADE_GOOD_TEXT;
    }
    if (score === '中等') {
      return GRADE_MEDIUM_TEXT;
    }
    return GRADE_DEFAULT_TEXT;
  }

  private scoreBackground(score: string): string {
    if (score === '优秀') {
      return PASS_BG;
    }
    if (score === '良好') {
      return GRADE_GOOD_BG;
    }
    if (score === '中等') {
      return REVIEW_BG;
    }
    return GRADE_DEFAULT_BG;
  }

  /** 课程性质标签色（必修蓝/限选橙/选修及其他灰，兼容“必修课”等带后缀文案） */
  private natureTagColor(nature: string): string {
    if (nature.startsWith('必修')) {
      return GRADE_GOOD_TEXT;
    }
    if (nature.startsWith('限选')) {
      return GRADE_MEDIUM_TEXT;
    }
    return GRADE_DEFAULT_TEXT;
  }

  private natureTagBackground(nature: string): string {
    if (nature.startsWith('必修')) {
      return GRADE_GOOD_BG;
    }
    if (nature.startsWith('限选')) {
      return REVIEW_BG;
    }
    return TAG_DEFAULT_BG;
  }

  /** 考核方式标签色（考试绿/考查紫/其他灰） */
  private examTagColor(examType: string): string {
    if (examType === '考试') {
      return GRADE_EXCELLENT_TEXT;
    }
    if (examType === '考查') {
      return GRADE_INSPECT_TEXT;
    }
    return GRADE_DEFAULT_TEXT;
  }

  private examTagBackground(examType: string): string {
    if (examType === '考试') {
      return PASS_BG;
    }
    if (examType === '考查') {
      return GRADE_INSPECT_BG;
    }
    return TAG_DEFAULT_BG;
  }

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 600;
    }
    return 1000;
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  planRow(course: PlanCourse) {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(course.courseName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (course.natureText.length > 0) {
            Text(course.natureText)
              .fontSize(10)
              .fontColor(this.natureTagColor(course.natureText))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.natureTagBackground(course.natureText))
          }
          if (course.examTypeText.length > 0) {
            Text(course.examTypeText)
              .fontSize(10)
              .fontColor(this.examTagColor(course.examTypeText))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.examTagBackground(course.examTypeText))
          }
        }
        .width('100%')
        Text(this.courseSubtitle(course))
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (course.scoreView.length > 0) {
        Text(course.scoreView)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.scoreColor(course.scoreView))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(12)
          .backgroundColor(this.scoreBackground(course.scoreView))
          .margin({ left: 12 })
      } else {
        Text('未修')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  planSection(section: PlanSectionData) {
    Column() {
      Row() {
        Text(section.name)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Text(section.courses.length + '门 · ' + this.creditsOf(section.courses) + '学分')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      .padding({ bottom: 4 })
      ForEach(section.courses, (course: PlanCourse) => {
        this.planRow(course)
      }, (course: PlanCourse) => course.courseName + course.natureText + course.examTypeText + course.plannedTerm + course.scoreView)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 12 })
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column() {
          if (this.totalCourses() > 0) {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Row({ space: 6 }) {
                Text('开课学期')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                Select(this.termOptions())
                  .selected(this.selectedTermIndex())
                  .value(this.selectedTermLabel())
                  .font({ size: 13 })
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .optionFont({ size: 13 })
                  .optionFontColor($r('sys.color.ohos_id_color_text_primary'))
                  .selectedOptionFontColor($r('sys.color.ohos_id_color_text_primary_activated'))
                  .selectedOptionBgColor($r('sys.color.ohos_id_color_button_normal'))
                  .optionWidth(232)
                  .onSelect((index: number) => {
                    if (index >= 0 && index < this.termChips.length) {
                      this.selectedTerm = this.termChips[index];
                      this.rebuildSections();
                    }
                  })
              }
              .alignItems(VerticalAlign.Center)
              .margin({ right: 12, bottom: 4 })
              Row({ space: 6 }) {
                Text('课程性质')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                Select(this.natureOptions())
                  .selected(this.selectedNatureIndex())
                  .value(this.selectedNature)
                  .font({ size: 13 })
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .optionFont({ size: 13 })
                  .optionFontColor($r('sys.color.ohos_id_color_text_primary'))
                  .selectedOptionFontColor($r('sys.color.ohos_id_color_text_primary_activated'))
                  .selectedOptionBgColor($r('sys.color.ohos_id_color_button_normal'))
                  .optionWidth(232)
                  .onSelect((index: number) => {
                    if (index >= 0 && index < this.natureChips.length) {
                      this.selectedNature = this.natureChips[index];
                      this.rebuildSections();
                    }
                  })
              }
              .alignItems(VerticalAlign.Center)
              .margin({ right: 12, bottom: 4 })
              Row({ space: 6 }) {
                Text('考核方式')
                  .fontSize(13)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                Select(this.examTypeOptions())
                  .selected(this.selectedExamTypeIndex())
                  .value(this.selectedExamType)
                  .font({ size: 13 })
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .optionFont({ size: 13 })
                  .optionFontColor($r('sys.color.ohos_id_color_text_primary'))
                  .selectedOptionFontColor($r('sys.color.ohos_id_color_text_primary_activated'))
                  .selectedOptionBgColor($r('sys.color.ohos_id_color_button_normal'))
                  .optionWidth(232)
                  .onSelect((index: number) => {
                    if (index >= 0 && index < this.examChips.length) {
                      this.selectedExamType = this.examChips[index];
                      this.rebuildSections();
                    }
                  })
              }
              .alignItems(VerticalAlign.Center)
              .margin({ bottom: 4 })
            }
            .width('100%')
            .margin({ bottom: 4 })
          }
          ForEach(this.visibleSections, (section: PlanSectionData) => {
            this.planSection(section)
          }, (section: PlanSectionData) => section.name + '|' + this.sectionFingerprint(section.courses))
          if (this.totalCourses() === 0) {
            Text(this.dataMode === 'online' ? '暂无培养计划数据' :
              (this.dataMode === 'offlineCache' ? '暂无缓存培养计划' : '登录教务系统后可查看培养计划'))
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .padding({ top: 24, bottom: 24 })
          }
        }
        .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off)

      FrostBand() {
        Row() {
          BackButton({
            onBack: () => {
              this.goBack();
            }
          })
          Text('培养计划')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .padding({ left: 8, right: 16 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
