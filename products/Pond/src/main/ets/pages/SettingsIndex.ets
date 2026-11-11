import { router } from '@kit.ArkUI';
import { AppLog } from '../data/AppLog';
import { SettingsView, SettingsSubPage, PAGE_PUSH_DURATION } from '../view/SettingsView';
import { FrostBand, FROST_BAND_HEIGHT } from '../view/FrostBand';
import { BackButton } from '../view/BackButton';

const TAG: string = 'SettingsIndex';
const DOMAIN: number = 0x0000;
/** 页面顶栏高度（vp） */
const HEADER_HEIGHT: number = FROST_BAND_HEIGHT;

/**
 * 设置页（独立路由页）：由各页面右上角设置入口（SettingsEntryButton）进入。
 * 顶带提供唯一返回键（二级页打开时先弹回设置主页，主页时返回上一页）；
 * 设置主体复用 SettingsView（含开发者选项/关于应用二级页，二级页标题不带返回键）。
 * 设备返回（侧滑/返回键）：与顶带返回键行为一致。
 */
@Entry
@Component
struct SettingsIndex {
  /** 当前设置二级页（与 SettingsView 经 AppStorage 共享） */
  @StorageLink('jwSettingsSubPage') subPage: SettingsSubPage = SettingsSubPage.Main;

  aboutToAppear(): void {
    AppLog.info(DOMAIN, TAG, 'aboutToAppear');
    // 每次进入都从设置主页开始（上次会话可能停留在二级页）
    this.subPage = SettingsSubPage.Main;
  }

  /** 设备返回：二级页打开时先弹回设置主页 */
  onBackPress(): boolean {
    if (this.subPage !== SettingsSubPage.Main) {
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.Main;
      });
      return true;
    }
    return false;
  }

  /** 返回上一页 */
  private backToPrev(): void {
    try {
      const state: router.RouterState = this.getUIContext().getRouter().getState();
      AppLog.info(DOMAIN, TAG, 'back: index=%{public}d path=%{public}s', state.index, state.path);
      if (state.index > 1) {
        this.getUIContext().getRouter().back();
      }
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'router back failed: %{public}s', `${error}`);
    }
  }

  /** 顶带返回键：二级页打开时先弹回设置主页（与设备返回一致），否则返回上一页 */
  private backFromBand(): void {
    if (this.subPage !== SettingsSubPage.Main) {
      AppLog.info(DOMAIN, TAG, 'band back to settings main');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.Main;
      });
      return;
    }
    this.backToPrev();
  }

  /** 顶带标题：悬浮于返回键右侧，固定不随内容滚动 */
  @Builder
  bandTitle(title: string) {
    Text(title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .margin({ left: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      SettingsView()
        .width('100%')
        .height('100%')

      FrostBand() {
        Row() {
          BackButton({
            onBack: () => {
              this.backFromBand();
            }
          })
          if (this.subPage === SettingsSubPage.Developer) {
            this.bandTitle('开发者选项')
          } else if (this.subPage === SettingsSubPage.About) {
            this.bandTitle('关于应用')
          } else {
            this.bandTitle('设置')
          }
        }
        .width('100%')
        .height(HEADER_HEIGHT)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
