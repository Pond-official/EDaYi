let examStorage = new LocalStorage();

class ExamEntry {
  n: string = '';
  d: string = '';
  t: string = '';
  x: number = 0;
}

interface ExamEntryRaw {
  n?: string;
  d?: string;
  t?: string;
  x?: number;
}

/**
 * 期末倒计时服务卡片（2*4）：按考试时间从近到远展示期末考试倒计时。
 * 数据由 ExamFormAbility 通过 formBindingData 注入 LocalStorage，
 * 必须以 @Entry(examStorage) 接收；条目含课程名（n）、
 * 日期文本（d）、倒计时文本（t）与距考天数（x，驱动徽标配色）。
 * examsJson 变化时通过 @Watch 重新解析（updateForm 刷新路径）。
 */
@Entry(examStorage)
@Component
struct ExamCountdownCard {
  @LocalStorageProp('examsJson') @Watch('onDataChanged') examsJson: string = '[]';
  @LocalStorageProp('totalText') totalText: string = '';
  @LocalStorageProp('emptyText') emptyText: string = '';
  /** 隐私模式下非空：卡片不可用提示 */
  @LocalStorageProp('privacyDisabledText') privacyDisabledText: string = '';
  @State exams: ExamEntry[] = [];

  aboutToAppear(): void {
    this.parseExams();
  }

  onDataChanged(): void {
    this.parseExams();
  }

  private parseExams(): void {
    let parsed: ExamEntry[] = [];
    try {
      const raw: ExamEntryRaw[] = JSON.parse(this.examsJson) as ExamEntryRaw[];
      for (const item of raw) {
        const entry: ExamEntry = new ExamEntry();
        entry.n = typeof item.n === 'string' ? item.n : '';
        entry.d = typeof item.d === 'string' ? item.d : '';
        entry.t = typeof item.t === 'string' ? item.t : '';
        entry.x = typeof item.x === 'number' ? item.x : -1;
        if (entry.n.length > 0) {
          parsed.push(entry);
        }
      }
    } catch (error) {
      parsed = [];
    }
    this.exams = parsed;
  }

  build() {
    Column() {
      Row() {
        Text('期末倒计时')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
        if (this.totalText.length > 0) {
          Text(this.totalText)
            .fontSize(10)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
      }
      .width('100%')
      if (this.privacyDisabledText.length > 0) {
        Column() {
          Text(this.privacyDisabledText)
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.exams.length === 0) {
        Column() {
          Text(this.emptyText.length > 0 ? this.emptyText : '在课表课程详情中设置期末时间')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 6 }) {
          ForEach(this.exams, (entry: ExamEntry) => {
            Row() {
              Text(entry.t)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(entry.x === 0 ?
                  $r('sys.color.ohos_id_color_warning') : Color.White)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .backgroundColor(entry.x === 0 ?
                  $r('sys.color.ohos_id_color_button_normal') :
                  $r('sys.color.ohos_id_color_text_primary_activated'))
              Column() {
                Text(entry.n)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.ohos_id_color_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(entry.d)
                  .fontSize(9)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }, (entry: ExamEntry, index: number) => 'exam' + index + entry.n + entry.t)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .alignItems(HorizontalAlign.Start)
  }
}
