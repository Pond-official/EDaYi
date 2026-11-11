import { JwxtRepository } from '../data/JwxtRepository';
import { CacheManager } from '../data/CacheManager';
import { AppLog } from '../data/AppLog';
import { ReminderScheduler } from '../data/ReminderScheduler';
import { getContext } from '../net/JwTransport';
import { AppLogCard } from './AppLogCard';
import { FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { SettingsCacheCard, SettingsPrivacyCard, SettingsReminderCard, SettingsSectionTitle } from './SettingsCards';
import { GITHUB_URL, SettingsAboutEntry, SettingsAcknowledgementCard, SettingsDeveloperCard,
  SettingsDeveloperEntry, SettingsDeveloperModeCard, SettingsOpenSourceCard, SettingsVersionCard } from './SettingsAboutCards';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

const SETTING_DOMAIN: number = 0x0000;
const SETTING_TAG: string = 'SettingsView';
/** 二级页推入/弹出转场时长（毫秒） */
export const PAGE_PUSH_DURATION: number = 380;

/** 设置二级页：主页 / 开发者选项 / 关于应用 */
export enum SettingsSubPage {
  Main,
  Developer,
  About
}

/**
 * 设置页：上课提醒开关、隐私模式与存储管理（一级菜单），
 * 开发者选项（关于应用内连续点击版本号 5 次后显示）与关于应用（二级菜单）。
 * 提醒以系统通知（Notification Kit）发送，修改即时生效并持久化到 preferences。
 */
@Component
export struct SettingsView {
  @StorageLink('jwReminderEnabled') reminderEnabled: boolean = true;
  @StorageLink('jwReminderAdvance') reminderAdvance: number = 10;
  @StorageLink('jwReminderAgentEnabled') reminderAgentEnabled: boolean = true;
  @StorageProp('jwNextReminder') nextReminder: string = '';
  /** 当前二级页（经 AppStorage 与 Index 共享，Index onBackPress 处理设备侧滑/返回键时据此弹回主页） */
  @StorageLink('jwSettingsSubPage') subPage: SettingsSubPage = SettingsSubPage.Main;
  /** 当前本地缓存大小文本 */
  @State cacheSizeText: string = '计算中…';
  /** 应用版本号 */
  @State versionText: string = '…';
  /** 隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  @StorageLink('jwPrivacyMode') privacyMode: string = 'standard';
  /** 状态栏避让区高度（px）：沉浸式全屏下内容顶部让位计算用 */
  @StorageProp('jwSafeTopPx') safeTopPx: number = 0;
  /** 开发者选项是否已开启（关于应用内连续点击版本号 5 次后开启） */
  @StorageLink('jwDeveloperMode') developerMode: boolean = false;
  /** 版本号连续点击计数（开发者选项解锁用） */
  @State versionTapCount: number = 0;
  /** 自定义提前提醒时间输入弹层显隐 */
  @State showAdvanceSheet: boolean = false;
  /** 自定义提前分钟数输入内容（弹层内 TextInput） */
  @State advanceInputText: string = '';
  /** 上次点击版本号的时间戳（毫秒），超过 3 秒视为不连续 */
  private lastVersionTapMs: number = 0;
  /** 解锁开发者选项需连续点击版本号的次数 */
  private static readonly DEVELOPER_UNLOCK_TAPS: number = 5;

  aboutToAppear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToAppear');
    JwxtRepository.ensureLoaded();
    this.loadVersionName();
    this.refreshCacheSize();
  }

  aboutToDisappear(): void {
    AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToDisappear');
  }

  private applySettings(enabled: boolean, advanceMinutes: number, agentEnabled: boolean): void {
    JwxtRepository.updateReminderSettings(enabled, advanceMinutes, agentEnabled);
  }

  /** 打开自定义提前时间输入弹层，预填当前值 */
  private openAdvanceSheet(): void {
    this.advanceInputText = `${this.reminderAdvance}`;
    this.showAdvanceSheet = true;
  }

  /** 校验并应用自定义提前提醒分钟数（1-120 的整数） */
  private confirmAdvanceInput(): void {
    const minutes: number = Number(this.advanceInputText.trim());
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 120) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 1-120 之间的整数分钟数' });
      return;
    }
    this.applySettings(this.reminderEnabled, minutes, this.reminderAgentEnabled);
    this.showAdvanceSheet = false;
  }

  /** 重新统计本地缓存大小并刷新显示 */
  private refreshCacheSize(): void {
    this.cacheSizeText = CacheManager.formatSize(JwxtRepository.getCacheSizeBytes());
  }

  /** 弹窗确认后清理本地缓存 */
  private confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      title: '清理缓存',
      message: '将清理本地缓存数据（网页缓存与课表、成绩等离线缓存），不影响已添加的桌面卡片和登录状态。确定清理吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清理',
        fontColor: Color.Red,
        action: () => {
          JwxtRepository.clearLocalCaches();
          this.refreshCacheSize();
        }
      }
    });
  }

  /** 读取本应用版本号 */
  private loadVersionName(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => {
        this.versionText = info.versionName;
      })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'getBundleInfo failed: %{public}s', JSON.stringify(error));
        this.versionText = '未知';
      });
  }

  /** 版本号点击：未开启时连续点击 5 次开启开发者选项；已开启时连续点击提示已开启（均防误触） */
  private onVersionTap(): void {
    const now: number = Date.now();
    if (now - this.lastVersionTapMs > 3000) {
      this.versionTapCount = 0;
    }
    this.lastVersionTapMs = now;
    this.versionTapCount += 1;
    if (this.developerMode) {
      // 已开启：首次点击不提示，防止误触；第二次起提示已开启
      if (this.versionTapCount >= 2) {
        this.getUIContext().getPromptAction().showToast({ message: '开发者选项已开启' });
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode already enabled');
      }
      return;
    }
    if (this.versionTapCount >= SettingsView.DEVELOPER_UNLOCK_TAPS) {
      this.versionTapCount = 0;
      JwxtRepository.updateDeveloperMode(true);
      this.getUIContext().getPromptAction().showToast({ message: '开发者选项已开启' });
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode unlocked');
      return;
    }
    if (this.versionTapCount >= 2) {
      // 首次点击不提示，防止误触；第二次起提示剩余次数
      const remain: number = SettingsView.DEVELOPER_UNLOCK_TAPS - this.versionTapCount;
      this.getUIContext().getPromptAction().showToast({ message: `再按 ${remain} 次开启开发者选项` });
    }
  }

  /** 复制 GitHub 开源地址 */
  private copyGithubUrl(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GITHUB_URL);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
      })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'copy url failed: %{public}s', JSON.stringify(error));
      });
  }

  /** 点击开源地址：先弹窗确认，确认后使用默认浏览器打开 */
  private openGithubUrl(): void {
    this.getUIContext().showAlertDialog({
      title: '访问开源地址',
      message: '即将打开浏览器访问\n' + GITHUB_URL + '\n是否继续？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '访问',
        action: () => {
          this.jumpToGithub();
        }
      }
    });
  }

  /** 使用默认浏览器打开 GitHub 开源地址 */
  private jumpToGithub(): void {
    const context: common.UIAbilityContext | null = JwxtRepository.getUiAbilityContext();
    if (context === null) {
      return;
    }
    context.openLink(GITHUB_URL, { appLinkingOnly: false })
      .catch((error: BusinessError) => {
        AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'open url failed: %{public}s', JSON.stringify(error));
        this.getUIContext().getPromptAction().showToast({ message: '打开链接失败' });
      });
  }

  /** 选择隐私模式：严格模式弹窗警告，确认后才生效 */
  private selectPrivacyMode(mode: string): void {
    if (mode === this.privacyMode) {
      return;
    }
    if (mode === 'strict') {
      this.getUIContext().showAlertDialog({
        title: '严格隐私模式',
        message: '开启后将不会缓存任何教务信息，桌面卡片将无法使用；应用进入后台运行或退出后，将自动清理缓存并退出登录，下次使用需重新登录。确定开启吗？',
        primaryButton: {
          value: '取消',
          action: () => {
          }
        },
        secondaryButton: {
          value: '开启',
          fontColor: $r('sys.color.ohos_id_color_warning'),
          action: () => {
            JwxtRepository.updatePrivacyMode('strict');
          }
        }
      });
      return;
    }
    JwxtRepository.updatePrivacyMode(mode);
  }

  build() {
    Column() {
      if (this.subPage === SettingsSubPage.Developer) {
        // 「开发者选项」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column({ space: 16 }) {
            SettingsDeveloperModeCard(this.developerMode, (isOn: boolean) => {
              if (isOn === this.developerMode) {
                return;
              }
              AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'developer mode toggled: %{public}s', `${isOn}`);
              JwxtRepository.updateDeveloperMode(isOn);
              if (!isOn) {
                this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                  this.subPage = SettingsSubPage.Main;
                });
              }
            })
            SettingsDeveloperCard(() => {
              ReminderScheduler.publishTest(getContext());
            })
            AppLogCard()
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.subPageEnter())
      } else if (this.subPage === SettingsSubPage.About) {
        // 「关于应用」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column() {
            SettingsVersionCard(this.versionText, () => {
              this.onVersionTap();
            })
            SettingsOpenSourceCard(() => {
              this.openGithubUrl();
            }, () => {
              this.copyGithubUrl();
            })
            SettingsAcknowledgementCard()
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.subPageEnter())
      } else {
        Scroll() {
          Column() {
            // 「设置」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
            SettingsReminderCard(this.reminderEnabled, this.nextReminder, this.reminderAdvance,
              this.reminderAgentEnabled, this.advanceInputText, this.showAdvanceSheet,
              (isOn: boolean) => {
                this.applySettings(isOn, this.reminderAdvance, this.reminderAgentEnabled);
              }, (minutes: number) => {
                if (this.reminderAdvance !== minutes) {
                  this.applySettings(this.reminderEnabled, minutes, this.reminderAgentEnabled);
                }
              }, () => {
                this.openAdvanceSheet();
              }, (isOn: boolean) => {
                this.applySettings(this.reminderEnabled, this.reminderAdvance, isOn);
              }, (value: string) => {
                this.advanceInputText = value;
              }, () => {
                this.confirmAdvanceInput();
              }, () => {
                this.showAdvanceSheet = false;
              }, () => {
                this.showAdvanceSheet = false;
              })
            SettingsSectionTitle('隐私')
            SettingsPrivacyCard(this.privacyMode, (value: string) => {
              this.selectPrivacyMode(value);
            })
            SettingsSectionTitle('存储')
            SettingsCacheCard(this.cacheSizeText, () => {
              this.confirmClearCache();
            })
            if (this.developerMode) {
              SettingsSectionTitle('开发者选项')
              SettingsDeveloperEntry(() => {
                AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterDeveloperPage clicked');
                this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                  this.subPage = SettingsSubPage.Developer;
                });
              })
            }
            SettingsSectionTitle('关于')
            SettingsAboutEntry(() => {
              AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterAboutPage clicked');
              this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
                this.subPage = SettingsSubPage.About;
              })
            })
          }
          .padding({ left: 16, right: 16, top: frostTopInsetVp(this.safeTopPx, this.getUIContext()), bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .transition(this.mainPageEnter())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }

  /** 二级页转场：从右侧滑入，退出时滑回右侧 */
  private subPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '100%' }));
  }

  /** 主页转场：从左侧滑回，退出时向左滑出让位 */
  private mainPageEnter(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '-25%' }));
  }
}
