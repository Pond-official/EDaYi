import { JwxtRepository } from '../data/JwxtRepository';
import { CacheManager } from '../data/CacheManager';
import { AppLog } from '../data/AppLog';
import { ReminderScheduler } from '../data/ReminderScheduler';
import { getContext } from '../net/JwTransport';
import { AppLogCard } from './AppLogCard';
import { FROST_BAND_HEIGHT, frostTopInsetVp } from './FrostBand';
import { bundleManager, common } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

const SETTING_DOMAIN: number = 0x0000;
const SETTING_TAG: string = 'SettingsView';
const GITHUB_URL: string = 'https://github.com/Pond-official/EDaYi';
/** 二级页推入/弹出转场时长（毫秒） */
export const PAGE_PUSH_DURATION: number = 380;
/** 提前提醒时间快捷选项（分钟），另提供 1-120 分钟自定义输入 */
const ADVANCE_PRESETS: number[] = [5, 10, 15, 20, 30];

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

  /** 当前提前时间是否为自定义值（不在快捷选项内） */
  private isCustomAdvance(): boolean {
    return ADVANCE_PRESETS.indexOf(this.reminderAdvance) < 0;
  }

  /** 自定义提前时间 chip 文案：已选自定义值时显示具体分钟数 */
  private customAdvanceLabel(): string {
    return this.isCustomAdvance() ? `${this.reminderAdvance}分钟` : '自定义';
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

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .padding({ top: 16, bottom: 8 })
  }

  /** 自定义提前提醒时间输入弹层内容 */
  @Builder
  advanceSheet() {
    Column({ space: 16 }) {
      Text('自定义提前提醒时间')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Text('输入上课前多少分钟提醒，可设 1-120 分钟')
        .fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
      TextInput({ text: this.advanceInputText, placeholder: '1-120' })
        .type(InputType.Number)
        .fontSize(16)
        .maxLength(3)
        .width('100%')
        .onChange((value: string) => {
          this.advanceInputText = value;
        })
        .enterKeyType(EnterKeyType.Done)
        .onSubmit(() => {
          this.confirmAdvanceInput();
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.showAdvanceSheet = false;
          })
        Button('确定')
          .layoutWeight(1)
          .onClick(() => {
            this.confirmAdvanceInput();
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 28, right: 28, top: 12, bottom: 36 })
  }

  @Builder
  reminderCard() {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 2 }) {
          Text('上课提醒')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text('上课前通过系统通知提醒你')
            .fontSize(12)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.reminderEnabled })
          .onChange((isOn: boolean) => {
            this.applySettings(isOn, this.reminderAdvance, this.reminderAgentEnabled);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.reminderEnabled) {
        Text(this.nextReminder.length > 0 ?
          '下次提醒：' + this.nextReminder : '暂无即将到来的课程提醒')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')

        Divider()
          .color($r('sys.color.ohos_id_color_list_separator'))

        Text('提前提醒时间')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, alignContent: FlexAlign.Center }) {
          ForEach(ADVANCE_PRESETS, (minutes: number) => {
            Text(`${minutes}分钟`)
              .fontSize(13)
              .fontWeight(this.reminderAdvance === minutes ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.reminderAdvance === minutes ? Color.White :
                $r('sys.color.ohos_id_color_text_primary_activated'))
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .margin({ right: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.reminderAdvance === minutes ?
                $r('sys.color.ohos_id_color_text_primary_activated') :
                $r('sys.color.ohos_id_color_button_normal'))
              .onClick(() => {
                if (this.reminderAdvance !== minutes) {
                  this.applySettings(this.reminderEnabled, minutes, this.reminderAgentEnabled);
                }
              })
          }, (minutes: number) => 'advance' + minutes)
          Text(this.customAdvanceLabel())
            .fontSize(13)
            .fontWeight(this.isCustomAdvance() ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.isCustomAdvance() ? Color.White :
              $r('sys.color.ohos_id_color_text_primary_activated'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(this.isCustomAdvance() ?
              $r('sys.color.ohos_id_color_text_primary_activated') :
              $r('sys.color.ohos_id_color_button_normal'))
            .onClick(() => {
              this.openAdvanceSheet();
            })
        }
        .width('100%')

        Divider()
          .color($r('sys.color.ohos_id_color_list_separator'))

        Row() {
          Text('代理提醒')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.reminderAgentEnabled })
            .onChange((isOn: boolean) => {
              this.applySettings(this.reminderEnabled, this.reminderAdvance, isOn);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text('开启后提醒交由系统后台代理发布，应用退出或被清理后仍会准时送达；关闭后仅应用运行期间提醒。')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }

      Text('提醒通过系统通知发送，需授予通知权限。')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .bindSheet($$this.showAdvanceSheet, this.advanceSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    })
  }

  /** 开发者选项入口（点击进入二级菜单） */
  @Builder
  developerEntry() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('开发者选项')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('调试与测试工具')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterDeveloperPage clicked');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.Developer;
      });
    })
  }

  /** 关于应用入口（点击进入二级菜单） */
  @Builder
  aboutEntry() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('关于应用')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('版本号与开源信息')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      AppLog.info(SETTING_DOMAIN, SETTING_TAG, 'enterAboutPage clicked');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.About;
      });
    })
  }

  /** 开发者选项：开发者模式开关（关闭即隐藏开发者选项，再次开启需重新点击版本号解锁） */
  @Builder
  developerModeCard() {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('开发者模式')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('关闭后将隐藏开发者选项，再次开启需在关于应用中连续点击版本号 5 次')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.developerMode })
        .onChange((isOn: boolean) => {
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
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  /** 开发者选项：调试用工具 */
  @Builder
  developerCard() {
    Column({ space: 12 }) {
      Text('通知')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Button('发送测试通知')
        .fontSize(14)
        .height(36)
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          ReminderScheduler.publishTest(getContext());
        })

      Text('立即发送一条测试通知，并在60秒后送达一条代理提醒，验证通知与后台代理链路。')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  /** 一级菜单：隐私模式（标准/限制/严格） */
  @Builder
  privacyOptionRow(value: string, title: string, description: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text(description)
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: value, group: 'privacyMode' })
        .checked(this.privacyMode === value)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.selectPrivacyMode(value);
    })
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

  /** 一级菜单：隐私模式卡片 */
  @Builder
  privacyCard() {
    Column() {
      Text('隐私')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      this.privacyOptionRow('standard', '标准', '缓存个人成绩、课表等所有信息（默认）')
      Divider()
        .color($r('sys.color.ohos_id_color_list_separator'))
      this.privacyOptionRow('restricted', '限制', '仅缓存课表供桌面卡片使用，其他数据都不会缓存')
      Divider()
        .color($r('sys.color.ohos_id_color_list_separator'))
      this.privacyOptionRow('strict', '严格', '不缓存任何信息；进入后台或退出后清理缓存并退出登录，桌面卡片不可用')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  /** 一级菜单：缓存管理 */
  @Builder
  cacheCard() {
    Column({ space: 12 }) {
      Text('存储')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Row() {
        Column({ space: 2 }) {
          Text('缓存大小')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text('含网页缓存与课表、成绩等离线缓存')
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.cacheSizeText)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Button('清理缓存')
        .fontSize(14)
        .height(36)
        .width('100%')
        .onClick(() => {
          this.confirmClearCache();
        })

      Text('清理后成绩将清空，可通过主页"刷新"重新同步；不影响已添加的桌面卡片和登录状态。')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 16 })
  }

  /** 关于应用：版本号（连续点击 5 次可开启开发者选项） */
  @Builder
  versionCard() {
    Row() {
      Column({ space: 2 }) {
        Text('版本号')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('版本信息来自应用配置')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text(this.versionText)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      this.onVersionTap();
    })
  }

  /** 关于应用：开源地址 */
  @Builder
  openSourceCard() {
    Column({ space: 12 }) {
      Text('开源地址')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Text(GITHUB_URL)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .width('100%')
        .onClick(() => {
          this.openGithubUrl();
        })

      Button('复制地址')
        .fontSize(14)
        .height(36)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.copyGithubUrl();
        })

      Text('本项目已在 GitHub 开源，欢迎查看源码、提交 Issue 或参与贡献。')
        .fontSize(11)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 16 })
  }

  /** 关于应用：特别鸣谢 */
  @Builder
  acknowledgementCard() {
    Column({ space: 12 }) {
      Text('特别鸣谢')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_primary_activated'))
        .width('100%')

      Text('网站接口爬取及应用灵感提供')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Text('JackZhang')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')

      Divider()
        .color($r('sys.color.ohos_id_color_list_separator'))
        .margin({ top: 4, bottom: 4 })

      Text('应用新功能灵感提供')
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')

      Text('悟理')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 16 })
  }

  build() {
    Column() {
      if (this.subPage === SettingsSubPage.Developer) {
        // 「开发者选项」标题悬浮于顶带返回键旁（由 SettingsIndex 渲染），此处不重复
        Scroll() {
          Column({ space: 16 }) {
            this.developerModeCard()
            this.developerCard()
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
            this.versionCard()
            this.openSourceCard()
            this.acknowledgementCard()
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
            this.reminderCard()
            this.sectionTitle('隐私')
            this.privacyCard()
            this.sectionTitle('存储')
            this.cacheCard()
            if (this.developerMode) {
              this.sectionTitle('开发者选项')
              this.developerEntry()
            }
            this.sectionTitle('关于')
            this.aboutEntry()
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
