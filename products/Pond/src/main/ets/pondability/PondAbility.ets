import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { AppLog } from '../data/AppLog';
import { window } from '@kit.ArkUI';
import { JwxtRepository } from '../data/JwxtRepository';
import { ZcpRepository } from '../data/ZcpRepository';

const DOMAIN = 0x0000;

export default class PondAbility extends UIAbility {
  onCreate(): void {
    JwxtRepository.attachContext(this.context);
    ZcpRepository.attachContext(this.context);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      AppLog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    JwxtRepository.handleAppHide();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.recordSafeTop(windowStage);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        AppLog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      AppLog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  /**
   * 记录状态栏避让区高度（px）到 AppStorage，
   * 供顶部材质条（FrostBand）计算覆盖状态栏所需的总高度；
   * loadContent 前写入，避免首帧高度跳变。
   */
  private recordSafeTop(windowStage: window.WindowStage): void {
    let safeTopPx: number = 0;
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      const avoidArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      safeTopPx = avoidArea.topRect.height;
    } catch (err) {
      AppLog.error(DOMAIN, 'testTag', 'Failed to get system avoid area. Cause: %{public}s', JSON.stringify(err));
    }
    AppStorage.setOrCreate('jwSafeTopPx', safeTopPx);
    AppLog.info(DOMAIN, 'testTag', 'safe top px: %{public}d', safeTopPx);
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    JwxtRepository.notifyForeground();
  }

  onBackground(): void {
    // Ability has back to background
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    JwxtRepository.handleAppHide();
  }
}