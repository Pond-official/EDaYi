import { uiMaterial } from '@kit.ArkUI';
import { MaterialUtils } from '../utils/MaterialUtils';

/**
 * 圆形沉浸光感材质返回键：THIN 沉浸式材质 + 交互形变 + 光感反馈。
 * 设备不支持沉浸光感（< API 26）时 material 为 undefined，条件渲染降级为半透明圆形底色按钮
 * （低版本设备调用高版本属性会抛异常，须条件渲染规避）。
 */
@Component
export struct BackButton {
  onBack: () => void = () => {};
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    this.material = MaterialUtils.circleButtonMaterial();
  }

  build() {
    if (this.material) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .systemMaterial(this.material)
      .onClick(() => {
        this.onBack();
      })
    } else {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        this.onBack();
      })
    }
  }
}

/**
 * 圆形沉浸光感材质关闭键：与 BackButton 同一材质规格（THIN 沉浸式 + 交互形变 + 光感反馈），
 * 用于弹层等场景的关闭操作；不支持沉浸光感时同 BackButton 降级。
 */
@Component
export struct CloseButton {
  onClose: () => void = () => {};
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    this.material = MaterialUtils.circleButtonMaterial();
  }

  build() {
    if (this.material) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .systemMaterial(this.material)
      .onClick(() => {
        this.onClose();
      })
    } else {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_primary')])
      }
      .width(40)
      .height(40)
      .backgroundColor($r('sys.color.comp_background_tertiary'))
      .onClick(() => {
        this.onClose();
      })
    }
  }
}
