import { uiMaterial } from '@kit.ArkUI';

/**
 * 圆形沉浸光感材质返回键：THIN 沉浸式材质 + 交互形变 + 光感反馈。
 * 设备不支持沉浸式材质时回退为半透明圆形底色。
 */
@Component
export struct BackButton {
  onBack: () => void = () => {};
  private material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: $r('sys.color.comp_background_tertiary'),
    interactive: true,
    lightEffect: { color: Color.White }
  });

  build() {
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
  }
}

/**
 * 圆形沉浸光感材质关闭键：与 BackButton 同一材质规格（THIN 沉浸式 + 交互形变 + 光感反馈），
 * 用于弹层等场景的关闭操作。
 */
@Component
export struct CloseButton {
  onClose: () => void = () => {};
  private material: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: $r('sys.color.comp_background_tertiary'),
    interactive: true,
    lightEffect: { color: Color.White }
  });

  build() {
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
  }
}
