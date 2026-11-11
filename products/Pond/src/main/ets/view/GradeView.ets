import { display, window } from '@kit.ArkUI';
import { GradeCategory, GradeEntry } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';
import { FrostBand, FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';

const TERM_ALL: string = '全部';

/** 成绩分组渲染数据（筛选后的快照，随学期筛选与数据变化重算） */
interface GradeSectionData {
  title: string;
  grades: GradeEntry[];
}

/**
 * 成绩页：学分绩点汇总卡 + 学期筛选 + 培养方案分类成绩
 * （专业基础课/专业课/公共课/实习 + 其他成绩，原生 Row/Column 布局）。
 * 平板/电脑横屏（lg/xl 且横屏方向）双列布局：培养计划入口及以上
 * （离线横幅、汇总卡、培养计划入口）在左列固定不随滚动，
 * 学期筛选与分类成绩在右列独立滚动，与综评页保持一致。
 * 无成绩（未出分）与成绩为 0 的科目在数据层已自动隐藏。
 */
@Component
export struct GradeView {
  @StorageProp('jwGrades') @Watch('onGradesChanged') grades: GradeEntry[] = [];
  @StorageProp('jwGradeCategories') @Watch('onGradesChanged') gradeCategories: GradeCategory[] = [];
  @StorageProp('jwDataMode') dataMode: string = 'preview';
  @StorageLink('mainBreakpoint') currentBreakpoint: string = 'md';
  @State selectedTerm: string = TERM_ALL;
  @State termChips: string[] = [TERM_ALL];
  /** 按当前学期筛选后的分组快照（@Builder 按值传参不随状态刷新，故经 @State 驱动重建） */
  @State visibleSections: GradeSectionData[] = [];
  @State isRefreshing: boolean = false;
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** Refresh 布局高度：初始取屏幕高度，旋转后由窗口尺寸事件刷新（display 快照在旋转瞬间滞后） */
  @State refreshHeight: Length = '100%';
  /** 窗口宽高（px）：横竖屏方向判定；启动时取 display 快照，旋转后由窗口尺寸事件刷新 */
  @State winWidthPx: number = 0;
  @State winHeightPx: number = 0;
  /** 离线横幅实测组件高（vp）：宽屏双列行高按横幅块高扣减用 */
  @State bannerHeightVp: number = 0;
  /** 窗口尺寸变化回调：持有引用便于精准解绑，避免 off 误伤其他视图的监听 */
  private readonly onWinSizeChanged = (size: window.Size): void => {
    // 旋转：状态更新包进 animateTo，驱动单列/双列分支 geometryTransition 飞行与高度渐变
    this.getUIContext().animateTo({ duration: 420, curve: Curve.Friction }, () => {
      this.applyWindowSize(size.width, size.height);
    });
  };

  aboutToAppear(): void {
    this.initWindowDims();
    this.refreshHeight = this.refreshHeightVp();
    this.bindWindowHeight();
    JwxtRepository.ensureLoaded();
    this.rebuildChips();
  }

  aboutToDisappear(): void {
    this.unbindWindowHeight();
  }

  onGradesChanged(): void {
    this.rebuildChips();
  }

  private allGrades(): GradeEntry[] {
    const all: GradeEntry[] = [];
    for (const category of this.gradeCategories) {
      for (const grade of category.grades) {
        all.push(grade);
      }
    }
    for (const grade of this.grades) {
      all.push(grade);
    }
    return all;
  }

  private rebuildChips(): void {
    const terms: string[] = [];
    for (const grade of this.allGrades()) {
      if (grade.termCode.length > 0 && terms.indexOf(grade.termCode) < 0) {
        terms.push(grade.termCode);
      }
    }
    // 学期倒序：最新学期排在最前
    terms.sort((a: string, b: string): number => a < b ? 1 : (a > b ? -1 : 0));
    this.termChips = [TERM_ALL].concat(terms);
    if (this.selectedTerm !== TERM_ALL && terms.indexOf(this.selectedTerm) < 0) {
      this.selectedTerm = TERM_ALL;
    }
    this.rebuildSections();
  }

  /** 重算筛选后的分组快照：分类成绩 + 其他成绩，空分组剔除 */
  private rebuildSections(): void {
    const sections: GradeSectionData[] = [];
    for (const category of this.gradeCategories) {
      const filtered: GradeEntry[] = this.filteredGrades(category.grades);
      if (filtered.length > 0) {
        sections.push({ title: category.name, grades: filtered });
      }
    }
    const others: GradeEntry[] = this.filteredGrades(this.grades);
    if (others.length > 0) {
      sections.push({ title: '其他成绩', grades: others });
    }
    this.visibleSections = sections;
  }

  /** 分组内容指纹：课程名+性质+考核+成绩拼接，内容变化时 ForEach key 变化以重建分组 */
  private sectionFingerprint(items: GradeEntry[]): string {
    let fp: string = String(items.length);
    for (const grade of items) {
      fp += '|' + grade.courseName + grade.natureText + grade.examTypeText + grade.scoreView;
    }
    return fp;
  }

  /** 学期码转显示文案："2025-2026-1" → "2025-2026学年1学期"，非该格式原样返回 */
  private formatTermLabel(termCode: string): string {
    const parts: string[] = termCode.split('-');
    if (parts.length === 3) {
      return parts[0] + '-' + parts[1] + '学年' + parts[2] + '学期';
    }
    return termCode;
  }

  /** 学期下拉按键选项列表（全部 + 学期倒序） */
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

  private matchTerm(grade: GradeEntry): boolean {
    return this.selectedTerm === TERM_ALL || grade.termCode === this.selectedTerm;
  }

  private filteredGrades(items: GradeEntry[]): GradeEntry[] {
    return items.filter((grade: GradeEntry): boolean => this.matchTerm(grade));
  }

  private totalCredit(): number {
    let sum: number = 0;
    for (const grade of this.allGrades()) {
      if (grade.passed) {
        sum += grade.credit;
      }
    }
    return sum;
  }

  private averageGpa(): number {
    let weighted: number = 0;
    let credits: number = 0;
    for (const grade of this.allGrades()) {
      if (grade.passed) {
        weighted += grade.gpaPoint * grade.credit;
        credits += grade.credit;
      }
    }
    if (credits === 0) {
      return 0;
    }
    return Math.round(weighted / credits * 100) / 100;
  }

  private scoreColor(score: string): string {
    if (score === '优秀') {
      return '#2E7D32';
    }
    if (score === '良好') {
      return '#1565C0';
    }
    if (score === '中等') {
      return '#B26A00';
    }
    return '#616161';
  }

  private scoreBackground(score: string): string {
    if (score === '优秀') {
      return '#E8F5E9';
    }
    if (score === '良好') {
      return '#E3F2FD';
    }
    if (score === '中等') {
      return '#FFF3E0';
    }
    return '#EEEEEE';
  }

  /** 课程性质标签色（必修蓝/限选橙/选修及其他灰，兼容“必修课”等带后缀文案） */
  private natureTagColor(nature: string): string {
    if (nature.startsWith('必修')) {
      return '#1565C0';
    }
    if (nature.startsWith('限选')) {
      return '#B26A00';
    }
    return '#616161';
  }

  private natureTagBackground(nature: string): string {
    if (nature.startsWith('必修')) {
      return '#E3F2FD';
    }
    if (nature.startsWith('限选')) {
      return '#FFF3E0';
    }
    return '#F5F5F5';
  }

  /** 考核方式标签色（考试绿/考查紫/其他灰） */
  private examTagColor(examType: string): string {
    if (examType === '考试') {
      return '#2E7D32';
    }
    if (examType === '考查') {
      return '#6A1B9A';
    }
    return '#616161';
  }

  private examTagBackground(examType: string): string {
    if (examType === '考试') {
      return '#E8F5E9';
    }
    if (examType === '考查') {
      return '#F3E5F5';
    }
    return '#F5F5F5';
  }

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 600;
    }
    if (this.isWide()) {
      return 1200;
    }
    return 1000;
  }

  private bottomInset(): number {
    return 88;
  }

  /** 平板/电脑横屏（lg/xl 且窗口为横屏方向）双列布局，切换逻辑与综评页保持一致 */
  private isWide(): boolean {
    if (this.currentBreakpoint !== 'lg' && this.currentBreakpoint !== 'xl') {
      return false;
    }
    // 大屏平板竖屏宽度也可能达到 lg（如 13 寸平板竖屏 960vp）：处于竖屏（宽 ≤ 高）时仍用单列纵向排版
    if (this.winWidthPx > 0 && this.winHeightPx > 0 && this.winWidthPx <= this.winHeightPx) {
      return false;
    }
    return true;
  }

  /** 离线横幅块高（实测组件高 + 底边距）：宽屏双列时横幅横跨双列上方，行高按其扣减使外层恰好不滚 */
  private bannerBlockVp(): number {
    if (this.dataMode !== 'offlineCache') {
      return 0;
    }
    return this.bannerHeightVp > 0 ? this.bannerHeightVp + 12 : 0;
  }

  /**
   * 横屏双列行高：外层滚动视口高 − 顶带让位高 − 离线横幅块高，使外层 Scroll 恰好不滚
   * （左列固定不动、右列独立滚动）；窗口高度未知时回退 100%。
   */
  private wideRowHeight(): Length {
    if (this.winHeightPx <= 0) {
      return '100%';
    }
    const viewportVp: number = this.getUIContext().px2vp(this.winHeightPx);
    const insetVp: number = frostTopInsetVp(this.safeTopPx, this.getUIContext());
    return Math.max(viewportVp - insetVp - this.bannerBlockVp(), 0);
  }

  /**
   * Refresh 组件会接管子组件几何并吞掉其 expandSafeArea，导致内部 Scroll 的
   * 滚动视口无法扩展进安全避让区（内容永远裁剪在避让区上方）。
   * 因此不给 Refresh 走 expandSafeArea，而是显式把它的布局高度设为整屏高度
   * （窗口沉浸式全屏，布局从屏幕顶部开始），使 Refresh 与内部 Scroll
   * 的布局本身覆盖状态栏与底部手势区，滚动视口随布局自然延伸。
   */
  private refreshHeightVp(): Length {
    let screenHeightPx: number = 0;
    try {
      screenHeightPx = display.getDefaultDisplaySync().height;
    } catch (err) {
      screenHeightPx = 0;
    }
    if (screenHeightPx <= 0) {
      return '100%';
    }
    return this.getUIContext().px2vp(screenHeightPx);
  }

  /** 启动时同步读取 display 宽高：用于初始横竖屏方向判定（启动时 display 快照是准确的） */
  private initWindowDims(): void {
    try {
      const disp: display.Display = display.getDefaultDisplaySync();
      this.winWidthPx = disp.width;
      this.winHeightPx = disp.height;
    } catch (err) {
      // 读取失败保持 0，留给窗口尺寸事件回填
    }
  }

  /** 按窗口尺寸（px）刷新 Refresh 布局高度与横竖屏方向判定数据 */
  private applyWindowSize(widthPx: number, heightPx: number): void {
    if (widthPx > 0 && heightPx > 0) {
      this.winWidthPx = widthPx;
      this.winHeightPx = heightPx;
      this.refreshHeight = this.getUIContext().px2vp(heightPx);
    }
  }

  /** 绑定主窗口尺寸变化：旋转后以窗口事件数据刷新 Refresh 高度与方向判定（display 快照可能滞后） */
  private bindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      const rect: window.Rect = win.getWindowProperties().windowRect;
      this.applyWindowSize(rect.width, rect.height);
      win.on('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  /** 解绑窗口尺寸变化监听 */
  private unbindWindowHeight(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.off('windowSizeChange', this.onWinSizeChanged);
    }).catch(() => {
    });
  }

  @Builder
  summaryCell(label: string, value: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
      Text(label)
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  summaryCard() {
    Row() {
      this.summaryCell('平均绩点', String(this.averageGpa()))
      Column()
        .width(1)
        .height(32)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      this.summaryCell('通过学分', String(this.totalCredit()))
      Column()
        .width(1)
        .height(32)
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      this.summaryCell('课程门数', String(this.allGrades().length))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .alignItems(VerticalAlign.Center)
    .padding({ top: 16, bottom: 16 })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .geometryTransition('grade-summary')
    .transition(TransitionEffect.OPACITY)
  }

  /** 培养计划入口（位于成绩汇总卡下方） */
  @Builder
  trainingPlanEntry() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('培养计划')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('方案内课程、学分与开课学期')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
    .geometryTransition('grade-plan')
    .transition(TransitionEffect.OPACITY)
    .onClick(() => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/TrainingPlanIndex' });
    })
  }

  @Builder
  gradeRow(grade: GradeEntry) {
    Row() {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(grade.courseName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1)
          if (grade.natureText.length > 0) {
            Text(grade.natureText)
              .fontSize(10)
              .fontColor(this.natureTagColor(grade.natureText))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.natureTagBackground(grade.natureText))
          }
          if (grade.examTypeText.length > 0) {
            Text(grade.examTypeText)
              .fontSize(10)
              .fontColor(this.examTagColor(grade.examTypeText))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor(this.examTagBackground(grade.examTypeText))
          }
        }
        .width('100%')
        Text(grade.credit + '学分 · 绩点' + grade.gpaPoint)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(grade.scoreView)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.scoreColor(grade.scoreView))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .borderRadius(12)
        .backgroundColor(this.scoreBackground(grade.scoreView))
        .margin({ left: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  gradeSection(title: string, items: GradeEntry[]) {
    if (items.length > 0) {
      Column() {
        Row() {
          Text(title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Blank()
          Text(items.length + '门')
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .width('100%')
        .padding({ bottom: 4 })
        ForEach(items, (grade: GradeEntry) => {
          this.gradeRow(grade)
        }, (grade: GradeEntry) => grade.termCode + grade.courseName + grade.natureText + grade.examTypeText + grade.scoreView)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 12 })
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
      .geometryTransition('grade-sec-' + title)
      .transition(TransitionEffect.OPACITY)
    }
  }

  private goLogin(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LoginIndex' });
  }

  /** 下拉刷新：已连接教务系统时在线刷新；未登录时提示先登录并立即收起刷新动画 */
  private doRefresh(): void {
    if (this.dataMode !== 'online') {
      this.isRefreshing = false;
      try {
        this.getUIContext().getPromptAction()
          .showToast({ message: '请先登录教务系统后再刷新', duration: 1500 });
      } catch (error) {
      }
      return;
    }
    JwxtRepository.reload().then((ok: boolean) => {
      this.isRefreshing = false;
      if (!ok) {
        try {
          this.getUIContext().getPromptAction()
            .showToast({ message: '刷新失败，请稍后重试', duration: 1500 });
        } catch (error) {
        }
      }
    });
  }

  /** 离线数据提示条：使用本地缓存成绩时置顶提示，点击“去登录”重新在线获取 */
  @Builder
  offlineBanner() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(20)
        .fontColor([$r('sys.color.ohos_id_color_warning')])
      Column({ space: 2 }) {
        Text('正在使用离线数据')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('当前展示本地缓存，重新登录后自动更新')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('去登录')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .borderRadius(12)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .margin({ bottom: 12 })
    .geometryTransition('grade-banner')
    .transition(TransitionEffect.OPACITY)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.bannerHeightVp = typeof newArea.height === 'number' ? newArea.height : 0;
    })
    .onClick(() => {
      this.goLogin();
    })
  }

  /** 学期筛选行：学期下拉选择（横屏双列时位于右列顶部） */
  @Builder
  termFilterRow() {
    Row({ space: 10 }) {
      Text('学期')
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
    .width('100%')
    .margin({ top: 16, bottom: 4 })
    .alignItems(VerticalAlign.Center)
    .geometryTransition('grade-term')
    .transition(TransitionEffect.OPACITY)
  }

  /** 无成绩空态提示（登录态/离线态/未登录文案不同） */
  @Builder
  emptyGradesText() {
    Text(this.dataMode === 'online' ? '暂无成绩数据' :
      (this.dataMode === 'offlineCache' ? '暂无缓存成绩' : '登录教务系统后可查看成绩'))
      .fontSize(12)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .padding({ top: 24, bottom: 24 })
      .geometryTransition('grade-empty')
      .transition(TransitionEffect.OPACITY)
  }

  /**
   * 平板横屏双列布局：汇总卡与培养计划入口在左列固定不随滚动，
   * 学期筛选与分类成绩在右列独立滚动；离线横幅不在此处渲染，
   * 由外层内容顶部横跨双列全宽展示。
   * 双列行高按外层滚动视口与横幅块高精确计算，使外层 Scroll 恰好不滚（左列保持不动），
   * 内层滚动经 SELF_FIRST 延伸到外层，下拉刷新仍然可用，与综评页保持一致。
   */
  @Builder
  wideContent() {
    Row() {
      Scroll() {
        Column() {
          this.summaryCard()
          this.trainingPlanEntry()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 16 })
      }
      .width(360)
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })

      Scroll() {
        Column() {
          this.termFilterRow()
          ForEach(this.visibleSections, (section: GradeSectionData) => {
            this.gradeSection(section.title, section.grades)
          }, (section: GradeSectionData) => section.title + '|' + this.sectionFingerprint(section.grades))
          if (this.allGrades().length === 0) {
            this.emptyGradesText()
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: this.bottomInset() })
      }
      .layoutWeight(1)
      .height('100%')
      .align(Alignment.Top)
      .padding({ left: 16 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }
    .width('100%')
    .height(this.wideRowHeight())
    .alignItems(VerticalAlign.Top)
    .constraintSize({ maxWidth: 1200 })
    .alignSelf(ItemAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
      Scroll() {
        Column() {
          // 离线横幅恒在外层内容顶部：单列全宽，双列横跨左右两列上方全宽；
          // 宽屏行高按实测横幅块高扣减（wideRowHeight），外层 Scroll 仍恰好不滚
          if (this.dataMode === 'offlineCache') {
            this.offlineBanner()
          }
          if (this.isWide()) {
            this.wideContent()
          } else {
            this.summaryCard()
            this.trainingPlanEntry()
            this.termFilterRow()
            ForEach(this.visibleSections, (section: GradeSectionData) => {
              this.gradeSection(section.title, section.grades)
            }, (section: GradeSectionData) => section.title + '|' + this.sectionFingerprint(section.grades))
            if (this.allGrades().length === 0) {
              this.emptyGradesText()
            }
          }
        }
        .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: this.isWide() ? 0 : this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      }
      .onRefreshing(() => {
        this.doRefresh();
      })
      .width('100%')
      .height(this.refreshHeight)

      FrostBand() {
        Row({ space: 8 }) {
          Text('成绩')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
        }
        .width('100%')
        .height(FROST_BAND_HEIGHT)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
