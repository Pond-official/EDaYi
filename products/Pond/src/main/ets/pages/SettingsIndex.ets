import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsView, SettingsSubPage, PAGE_PUSH_DURATION } from '../view/SettingsView';
import { FrostBand, FROST_BAND_HEIGHT } from '../view/FrostBand';

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
    hilog.info(DOMAIN, TAG, 'aboutToAppear');
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
      const state: router.RouterState = router.getState();
      hilog.info(DOMAIN, TAG, 'back: index=%{public}d path=%{public}s', state.index, state.path);
      if (state.index > 1) {
        router.back();
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'router back failed: %{public}s', `${error}`);
    }
  }

  /** 顶带返回键：二级页打开时先弹回设置主页（与设备返回一致），否则返回上一页 */
  private backFromBand(): void {
    if (this.subPage !== SettingsSubPage.Main) {
      hilog.info(DOMAIN, TAG, 'band back to settings main');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.Main;
      });
      return;
    }
    this.backToPrev();
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      SettingsView()
        .width('100%')
        .height('100%')
        .padding({ top: FROST_BAND_HEIGHT })

      FrostBand() {
        Row() {
          Stack() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor([$r('sys.color.ohos_id_color_text_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            this.backFromBand();
          })
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
