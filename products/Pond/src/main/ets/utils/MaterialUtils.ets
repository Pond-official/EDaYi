import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** 沉浸光感（uiMaterial/systemMaterial）所需系统版本：26.0.0 对应 distributionOSApiVersion 26*10000 */
const IMMERSIVE_OS_API_VERSION: number = 260000;

/**
 * 沉浸材质工具：统一构造与悬浮页签栏（底栏）同款的沉浸光感材质，
 * 供顶部材质条（FrostBand）、设置入口按钮、降级底栏等共用。
 */
export class MaterialUtils {
  /**
   * 底栏同款沉浸材质：算力弱（SMOOTH）档用 THIN 薄材质保证流畅，其余档位用 REGULAR 常规材质；
   * lightEffect 开启白色光感交互反馈；
   * 设备不支持沉浸光感（系统版本 < 26 或 isImmersiveMaterialSupported 为 false）时返回 undefined。
   */
  static barMaterial(): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.distributionOSApiVersion < IMMERSIVE_OS_API_VERSION) {
      return undefined;
    }
    try {
      if (!uiMaterial.isImmersiveMaterialSupported()) {
        return undefined;
      }
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      const style: uiMaterial.ImmersiveStyle = level === uiMaterial.MaterialLevel.SMOOTH
        ? uiMaterial.ImmersiveStyle.THIN
        : uiMaterial.ImmersiveStyle.REGULAR;
      const light: uiMaterial.LightEffectOptions = { color: Color.White };
      return new uiMaterial.ImmersiveMaterial({
        style: style,
        lightEffect: light
      });
    } catch (error) {
      return undefined;
    }
  }
}
