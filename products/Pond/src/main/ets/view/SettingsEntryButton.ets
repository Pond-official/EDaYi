import { uiMaterial } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../data/AppLog';
import { MaterialUtils } from '../utils/MaterialUtils';

const TAG: string = 'SettingsEntryButton';
const DOMAIN: number = 0x0000;
/** 圆形按钮边长（vp） */
const BUTTON_SIZE: number = 44;

/**
 * 右上角设置入口：圆形按钮，点击进入设置页（pages/SettingsIndex）。
 * 内部填充：按钮专属半透明 settings_button_fill（base/dark 自适配），
 * 带下内容可透过，呈磨砂透过观感；叠加底栏同款材质代码
 * （MaterialUtils.barMaterial 统一构造的沉浸光感，真机呈材质磨砂），
 * 细描边勾出轮廓。
 */
@Component
export struct SettingsEntryButton {
  /** 沉浸光感材质（与底栏同款构造），设备不支持时为 undefined */
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    this.material = MaterialUtils.barMaterial();
  }

  /** 跳转设置页 */
  private openSettings(): void {
    AppLog.info(DOMAIN, TAG, 'open settings');
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsIndex' })
      .catch((error: BusinessError) => {
        AppLog.error(DOMAIN, TAG, 'push settings failed: %{public}s %{public}s',
          `${error.code}`, `${error.message}`);
      });
  }

  build() {
    Stack() {
      SymbolGlyph($r('sys.symbol.gearshape'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor([$r('sys.color.ohos_id_color_text_primary')])
    }
    .width(BUTTON_SIZE)
    .height(BUTTON_SIZE)
    .borderRadius(BUTTON_SIZE / 2)
    .clip(true)
    .backgroundColor($r('app.color.settings_button_fill'))
    .systemMaterial(this.material)
    .border({ width: 1, color: $r('sys.color.ohos_id_color_list_separator') })
    .onClick(() => {
      this.openSettings();
    })
  }
}
