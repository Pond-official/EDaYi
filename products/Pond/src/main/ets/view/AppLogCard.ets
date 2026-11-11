import { AppLog, LogEntry } from '../data/AppLog';
import { pasteboard } from '@kit.BasicServicesKit';

/** 日志视图最多展示条数（缓冲上限 1000，超出仅截断显示） */
const LOG_VIEW_MAX: number = 200;

/**
 * 开发者选项：应用日志卡片。
 * 实时展示内存环形缓冲中的应用日志（新→旧），
 * 支持复制全部导出与清空。
 */
@Component
export struct AppLogCard {
  /** 日志缓冲版本号（AppLog 写入时递增），变化时刷新日志列表 */
  @StorageProp('appLogRevision') appLogRevision: number = 0;

  /** 复制全部日志到剪贴板 */
  private copyLogs(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, AppLog.recentText());
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '日志已复制' });
      })
      .catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
      });
  }

  build() {
    Column({ space: 12 }) {
      Text('应用日志')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Button('复制全部')
          .fontSize(13)
          .height(32)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.copyLogs();
          })
        Button('清空')
          .fontSize(13)
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            AppLog.clear();
          })
        Blank()
        // 显式引用 appLogRevision 建立状态依赖，写入/清空后计数随版本号刷新
        Text(`共 ${this.appLogRevision >= 0 ? AppLog.count() : 0} 条`)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          ForEach(AppLog.recent(LOG_VIEW_MAX), (entry: LogEntry) => {
            Text(`${entry.timeText} ${entry.level}/${entry.tag}: ${entry.message}`)
              .fontSize(11)
              .fontColor(entry.level === 'E' ? $r('sys.color.ohos_id_color_warning') :
                (entry.level === 'W' ? $r('sys.color.ohos_id_color_text_secondary') :
                  $r('sys.color.ohos_id_color_text_primary')))
              .width('100%')
              .textAlign(TextAlign.Start)
          }, (entry: LogEntry, index: number) => `${this.appLogRevision}-${index}-${entry.timeText}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(280)
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .padding(8)
      .borderRadius(12)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}
