import { GradeCategory, GradeEntry } from '../model/JwModels';
import { JwxtRepository } from '../data/JwxtRepository';

const TERM_ALL: string = '全部';

/**
 * 成绩页：学分绩点汇总卡 + 学期筛选 + 培养方案分类成绩
 * （专业基础课/专业课/公共课/实习 + 其他成绩，原生 Row/Column 布局）。
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

  aboutToAppear(): void {
    JwxtRepository.ensureLoaded();
    this.rebuildChips();
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
    const chips: string[] = [TERM_ALL];
    for (const grade of this.allGrades()) {
      if (chips.indexOf(grade.termCode) < 0) {
        chips.push(grade.termCode);
      }
    }
    this.termChips = chips;
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

  private contentMaxWidth(): number {
    if (this.currentBreakpoint === 'sm') {
      return 600;
    }
    return 1000;
  }

  private bottomInset(): number {
    return 88;
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
  }

  @Builder
  termChip(chip: string) {
    Text(chip)
      .fontSize(12)
      .fontColor(this.selectedTerm === chip ?
        Color.White : $r('sys.color.ohos_id_color_text_primary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.selectedTerm === chip ?
        $r('sys.color.ohos_id_color_text_primary_activated') : $r('sys.color.ohos_id_color_button_normal'))
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.selectedTerm = chip;
      })
  }

  @Builder
  gradeRow(grade: GradeEntry) {
    Row() {
      Column({ space: 3 }) {
        Text(grade.courseName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(grade.natureText + ' · ' + grade.credit + '学分 · 绩点' + grade.gpaPoint)
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
        }, (grade: GradeEntry) => grade.termCode + grade.courseName + grade.scoreView)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 12 })
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .borderRadius(16)
      .backgroundColor($r('app.color.card_background'))
    }
  }

  build() {
    Column() {
      if (this.dataMode !== 'online') {
        Text(this.dataMode === 'offlineCache' ?
          '离线数据 · 请重新登录' : '未登录教务系统，登录后在线获取成绩')
          .fontSize(11)
          .fontColor(this.dataMode === 'offlineCache' ?
            $r('sys.color.ohos_id_color_warning') :
            $r('sys.color.ohos_id_color_text_secondary'))
          .padding({ top: 8 })
      }
      Scroll() {
        Column() {
          this.summaryCard()
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap
          }) {
            ForEach(this.termChips, (chip: string) => {
              this.termChip(chip)
            }, (chip: string) => chip)
          }
          .width('100%')
          .margin({ top: 16, bottom: 4 })
          ForEach(this.gradeCategories, (category: GradeCategory) => {
            this.gradeSection(category.name, this.filteredGrades(category.grades))
          }, (category: GradeCategory) => category.name)
          this.gradeSection('其他成绩', this.filteredGrades(this.grades))
          if (this.allGrades().length === 0) {
            Text(this.dataMode === 'online' ? '暂无成绩数据' :
              (this.dataMode === 'offlineCache' ? '暂无缓存成绩' : '登录教务系统后可查看成绩'))
              .fontSize(12)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .padding({ top: 24, bottom: 24 })
          }
        }
        .padding({ left: 16, right: 16, bottom: this.bottomInset() })
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minWidth: '100%', maxWidth: this.contentMaxWidth() })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
