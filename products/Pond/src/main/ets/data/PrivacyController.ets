import { common } from '@kit.AbilityKit';
import { AppLog } from './AppLog';
import { CardDataStore } from './CardDataStore';
import { ReminderScheduler } from './ReminderScheduler';
import { SelectionRepository } from './SelectionRepository';
import { ZcpRepository } from './ZcpRepository';
import { getContext } from '../net/JwTransport';

const TAG: string = 'JwxtRepository';
const DOMAIN: number = 0x0000;

/**
 * 隐私模式控制器（自 JwxtRepository 拆出）：
 * 管理隐私模式（standard/restricted/strict）与开发者选项的状态切换、
 * 按模式分级清理持久化数据。
 */
export class PrivacyController {
  /** 当前隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  static privacyMode(): string {
    return AppStorage.get<string>('jwPrivacyMode') ?? 'standard';
  }

  /** 切换开发者选项开关：开启（关于应用内连续点击版本号 5 次）或关闭（开发者页开关），立即生效并持久化 */
  static updateDeveloperMode(enabled: boolean): void {
    AppStorage.setOrCreate('jwDeveloperMode', enabled);
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null) {
      CardDataStore.saveDeveloperMode(context, enabled);
    }
  }

  /**
   * 切换隐私模式：写入 AppStorage 并持久化；
   * 限制模式立即清除应用内离线缓存与期末日期、单课提醒名单、已保存选课凭据等课表以外的缓存
   * （限制模式仅允许缓存课表供桌面卡片），并刷新期末倒计时卡片为不可用提示；
   * 严格模式同时清除卡片课表等全部含课程信息的数据并刷新全部卡片。
   */
  static updatePrivacyMode(mode: string): void {
    AppStorage.setOrCreate('jwPrivacyMode', mode);
    const context: common.UIAbilityContext | null = getContext();
    if (context !== null) {
      CardDataStore.savePrivacyMode(context, mode);
    }
    if (mode === 'strict') {
      PrivacyController.clearStrictData();
    } else if (mode === 'restricted') {
      // 已保存的选课学号/密码不属于课表数据，受限模式同样清除
      SelectionRepository.clearSavedCredentials();
      // 综评数据不属于课表数据，受限模式连同临时缓存一并清除
      ZcpRepository.clearMemory();
      ZcpRepository.clearCache();
      if (context !== null) {
        CardDataStore.clearAppCache(context);
        CardDataStore.clearFinalExams(context);
        CardDataStore.clearDisabledSessions(context);
        CardDataStore.refreshExamCards(context);
      }
    }
  }

  /**
   * 严格隐私模式清理：清除所有含个人课程信息的持久化数据并刷新桌面卡片。
   * 内存态（AppStorage）与提醒取消不依赖 context，先执行再清理磁盘；
   * 同时清除选课系统登录凭证（仅内存态）与已保存的学号/密码（系统关键资产存储）。
   */
  static clearStrictData(): void {
    AppStorage.setOrCreate('jwFinalExams', []);
    AppStorage.setOrCreate('jwReminderDisabledSessions', []);
    AppStorage.setOrCreate('jwNextReminder', '');
    ReminderScheduler.cancelAll();
    SelectionRepository.clearSession();
    SelectionRepository.clearSavedCredentials();
    // 综评为个人测评数据，严格模式连同 xgfw 会话标记与临时缓存一并清除
    ZcpRepository.clearSession();
    ZcpRepository.clearCache();
    const context: common.UIAbilityContext | null = getContext();
    if (context === null) {
      return;
    }
    CardDataStore.clearAppCache(context);
    CardDataStore.clearCardPayload(context);
    CardDataStore.clearFinalExams(context);
    CardDataStore.clearDisabledSessions(context);
    CardDataStore.refreshAllCards(context);
    CardDataStore.refreshExamCards(context);
  }

  /**
   * 应用回前台（PondAbility onForeground）：更新前台时刻戳，
   * 驱动视图跨天刷新"今日课程"与课表"今天"高亮。
   */
  static notifyForeground(): void {
    AppStorage.setOrCreate('jwForegroundTick', Date.now());
  }
}
