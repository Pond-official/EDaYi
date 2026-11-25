import { UIExtensionContentSession, common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FinalExamEntry } from '../model/JwModels';
import { CardDataStore } from '../data/CardDataStore';
import { ExamDateUtils } from '../utils/ExamDateUtils';
import { AppLog } from '../data/AppLog';

const TAG: string = 'ExamShareImport';
const DOMAIN: number = 0x0000;

/**
 * 期末倒计时导入页（Share Kit 分享详情页内嵌页面，由 ExamShareAbility 加载）：
 * 接收到分享文本/文件后自动按课程名合并到本机设置并展示导入结果
 * （写入与主应用「设置考试时间」同一存储，主应用在运行则即时刷新），无需手动确认；
 * 自动导入失败（无上下文/存储异常）时回退为列表+按钮的手动导入。
 * 期末倒计时为用户自建数据，全部隐私模式均落盘导入；
 * 导入完成经 terminateSelfWithResult(CLOSE) 关闭分享面板。
 */
@Entry
@Component
struct ExamShareImport {
  storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage();
  private session: UIExtensionContentSession | undefined =
    this.storage?.get<UIExtensionContentSession>('session');
  private abilityContext: common.Context | undefined =
    this.storage?.get<common.Context>('context');
  /** 解析出的待导入条目 */
  @State entries: FinalExamEntry[] = [];
  /** 已导入条目数（-1 表示尚未导入） */
  @State importedCount: number = -1;

  aboutToAppear(): void {
    const stored: FinalExamEntry[] | undefined = this.storage?.get<FinalExamEntry[]>('exams');
    this.entries = stored ?? [];
    AppLog.info(DOMAIN, TAG, 'import page appear, entries: %{public}d', `${this.entries.length}`);
    if (this.entries.length > 0) {
      this.confirmImport();
    }
  }

  /** 导入：按课程名合并到本机期末倒计时（页面打开自动调用一次，失败可经按钮重试） */
  private confirmImport(): void {
    if (this.abilityContext === undefined) {
      AppLog.error(DOMAIN, TAG, 'import without context');
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请重试' });
      return;
    }
    try {
      this.importedCount = CardDataStore.importFinalExams(this.abilityContext, this.entries);
      AppLog.info(DOMAIN, TAG, 'import done, changed: %{public}d', `${this.importedCount}`);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'importFinalExams failed: %{public}s', `${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '导入失败，请重试' });
    }
  }

  /** 返回分享面板（不导入） */
  private backToPanel(): void {
    const session: UIExtensionContentSession | undefined = this.session;
    if (session !== undefined) {
      session.terminateSelf()
        .catch((error: BusinessError) => {
          AppLog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}s', JSON.stringify(error));
        });
    }
  }

  /** 关闭分享面板（导入完成/放弃） */
  private closePanel(): void {
    const session: UIExtensionContentSession | undefined = this.session;
    if (session !== undefined) {
      session.terminateSelfWithResult({
        resultCode: systemShare.ShareAbilityResultCode.CLOSE
      })
        .catch((error: BusinessError) => {
          AppLog.error(DOMAIN, TAG, 'terminateSelfWithResult failed: %{public}s', JSON.stringify(error));
        });
    }
  }

  /** 单条考试倒计时文本（时间非法按"已结束"展示） */
  private countdownOf(entry: FinalExamEntry): string {
    const parsed: Date | null = ExamDateUtils.parseExamDate(entry.examDate);
    return parsed !== null ? ExamDateUtils.countdownTextOf(parsed) : '时间无效';
  }

  build() {
    Column({ space: 16 }) {
      if (this.importedCount >= 0) {
        Text('已导入 ' + this.importedCount + ' 门考试时间')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
        Text('打开 EDaYi 在「设置 - 期末倒计时」中查看')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
        Button('完成')
          .width('100%')
          .onClick(() => {
            this.closePanel();
          })
      } else if (this.entries.length === 0) {
        Text('分享内容中没有可导入的期末倒计时')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
        Text('分享文本需包含「课程名：YYYY-MM-DD HH:mm」格式的考试时间')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
        Button('返回')
          .width('100%')
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.backToPanel();
          })
      } else {
        Text('导入期末倒计时')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
        Text('来自分享的考试时间，导入后按课程名合并到本机设置')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
        Scroll() {
          Column() {
            ForEach(this.entries, (entry: FinalExamEntry) => {
              Row() {
                Column({ space: 2 }) {
                  Text(entry.courseName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.ohos_id_color_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(ExamDateUtils.formatDisplay(entry.examDate))
                    .fontSize(11)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    .maxLines(1)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.countdownOf(entry))
                  .fontSize(12)
                  .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 10, bottom: 10 })
            }, (entry: FinalExamEntry) => 'import' + entry.courseName + ':' + entry.examDate)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .constraintSize({ maxHeight: 280 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .onClick(() => {
              this.backToPanel();
            })
          Button('导入')
            .layoutWeight(1)
            .onClick(() => {
              this.confirmImport();
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: 20, bottom: 24 })
  }
}
