import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../data/AppLog';
import { window } from '@kit.ArkUI';
import { JwxtRepository } from '../data/JwxtRepository';
import { ZcpRepository } from '../data/ZcpRepository';
import { FinalExamEntry } from '../model/JwModels';
import { ExamShareLink } from '../utils/ExamShareLink';
import { ExamShareText } from '../utils/ExamShareText';

const DOMAIN = 0x0000;

export default class PondAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    JwxtRepository.attachContext(this.context);
    ZcpRepository.attachContext(this.context);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      AppLog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.handleExamShareLink(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    this.handleExamShareLink(want);
  }

  /**
   * 深链接导入期末倒计时（华为分享碰一碰/隔空传送链接直达拉起）：
   * edaiyi://examshare 载荷解码解析后存入 AppStorage（examSharePendingImport），不直接导入——
   * 由主页面 onPageShow 弹确认框先展示收到的考试时间明细，用户确认后才合并到本机设置。
   */
  private handleExamShareLink(want: Want): void {
    const link: string = want.uri ?? '';
    if (!ExamShareLink.isExamShareLink(link)) {
      return;
    }
    const text: string = ExamShareLink.payloadOf(link);
    const entries: FinalExamEntry[] = ExamShareText.parse(text);
    if (entries.length === 0) {
      AppLog.error(DOMAIN, 'testTag', 'exam share link has no valid entries');
      AppStorage.setOrCreate('examShareImportHint', '分享内容中没有可导入的考试时间');
      return;
    }
    AppStorage.setOrCreate('examSharePendingImport', entries);
    AppLog.info(DOMAIN, 'testTag', 'exam share link pending, entries: %{public}d', `${entries.length}`);
  }

  onDestroy(): void {
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    JwxtRepository.handleAppHide();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    // 全屏设置与主页面加载并行发起：loadContent 不再等待 setWindowLayoutFullScreen
    // 的窗口管理器往返（冷启动关键路径缩短一次异步往返）
    this.enterImmersiveFullScreen(windowStage);
    this.recordSafeAreasAndLoad(windowStage);
  }

  /**
   * 沉浸式全屏：主窗口延伸进状态栏区域（应用自身绘制状态栏底衬，
   * 状态栏图标由系统叠加在最上层）；与 loadContent 并行执行，
   * 全屏生效后回读避让区高度刷新 AppStorage（@StorageProp 驱动 FrostBand 自动重渲染；
   * 全屏通常先于首帧完成，无可见跳变）。
   */
  private enterImmersiveFullScreen(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true)
        .then(() => {
          AppLog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in setting layout fullscreen.');
          this.recordSafeAreas(windowStage);
        })
        .catch((err: BusinessError) => {
          AppLog.error(DOMAIN, 'testTag', 'Failed to set fullscreen. Cause: %{public}s', JSON.stringify(err));
          this.recordSafeAreas(windowStage);
        });
    } catch (err) {
      AppLog.error(DOMAIN, 'testTag', 'Failed to set fullscreen (sync). Cause: %{public}s', JSON.stringify(err));
      this.recordSafeAreas(windowStage);
    }
  }

  /** 先记录避让区高度再加载主页面（onWindowStageCreate 内立即调用，与全屏设置并行） */
  private recordSafeAreasAndLoad(windowStage: window.WindowStage): void {
    this.recordSafeAreas(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        AppLog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      AppLog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  /**
   * 记录窗口避让区高度（px）到 AppStorage：
   * 顶部状态栏高度供顶部材质条（FrostBand）计算覆盖状态栏所需的总高度；
   * 底部导航条高度取 TYPE_SYSTEM（三键导航）与 TYPE_NAVIGATION_INDICATOR（手势条）底部较大值，
   * 供 API 23 以下常规底栏让位系统导航条（避免互相遮挡）；
   * loadContent 前先写入初始值，全屏生效后再回读校正，避免首帧高度跳变。
   */
  private recordSafeAreas(windowStage: window.WindowStage): void {
    let safeTopPx: number = 0;
    let safeBottomPx: number = 0;
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      safeTopPx = systemArea.topRect.height;
      safeBottomPx = systemArea.bottomRect.height;
      const indicatorArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      if (indicatorArea.bottomRect.height > safeBottomPx) {
        safeBottomPx = indicatorArea.bottomRect.height;
      }
    } catch (err) {
      AppLog.error(DOMAIN, 'testTag', 'Failed to get system avoid area. Cause: %{public}s', JSON.stringify(err));
    }
    AppStorage.setOrCreate('jwSafeTopPx', safeTopPx);
    AppStorage.setOrCreate('jwSafeBottomPx', safeBottomPx);
    AppLog.info(DOMAIN, 'testTag', 'safe top px: %{public}d', safeTopPx);
    AppLog.info(DOMAIN, 'testTag', 'safe bottom px: %{public}d', safeBottomPx);
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