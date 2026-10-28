import { JwxtRepository } from '../data/JwxtRepository';
import { CacheManager } from '../data/CacheManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { bundleManager } from '@kit.AbilityKit';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';

const SETTING_DOMAIN: number = 0x0000;
const SETTING_TAG: string = 'SettingsView';
const GITHUB_URL: string = 'https://github.com/Pond-official/EDaYi';
/** 二级页推入/弹出转场时长（毫秒） */
export const PAGE_PUSH_DURATION: number = 380;

/** 设置二级页：主页 / 开发者选项 / 关于应用 */
export enum SettingsSubPage {
  Main,
  Developer,
  About
}

/**
 * 设置页：上课提醒开关、提前提醒时间自定义、开发者选项与关于应用（二级菜单）。
 * 提醒以系统通知（Notification Kit）发送，修改即时生效并持久化到 preferences。
 */
@Component
export struct SettingsView {
  @StorageLink('jwReminderEnabled') reminderEnabled: boolean = true;
  @StorageLink('jwReminderAdvance') reminderAdvance: number = 10;
  @StorageProp('jwNextReminder') nextReminder: string = '';
  /** 当前二级页（经 AppStorage 与 Index 共享，Index onBackPress 处理设备侧滑/返回键时据此弹回主页） */
  @StorageLink('jwSettingsSubPage') subPage: SettingsSubPage = SettingsSubPage.Main;
  /** 当前本地缓存大小文本 */
  @State cacheSizeText: string = '计算中…';
  /** 应用版本号 */
  @State versionText: string = '…';
  /** 隐私模式：standard=缓存全部 / restricted=仅课表卡片 / strict=不缓存 */
  @StorageLink('jwPrivacyMode') privacyMode: string = 'standard';
  /** 返回键按压态：按压点（相对返回键左上角）驱动的高光圆 */
  @State backPressed: boolean = false;
  @State backPressX: number = 22;
  @State backPressY: number = 22;

  aboutToAppear(): void {
    hilog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToAppear');
    JwxtRepository.ensureLoaded();
    this.loadVersionName();
  }

  aboutToDisappear(): void {
    hilog.info(SETTING_DOMAIN, SETTING_TAG, 'aboutToDisappear');
  }

  private applySettings(enabled: boolean, advanceMinutes: number): void {
    JwxtRepository.updateReminderSettings(enabled, advanceMinutes);
  }

  /** 重新统计本地缓存大小并刷新显示 */
  private refreshCacheSize(): void {
    this.cacheSizeText = CacheManager.formatSize(JwxtRepository.getCacheSizeBytes());
  }

  /** 弹窗确认后清理本地缓存 */
  private confirmClearCache(): void {
    AlertDialog.show({
      title: '清理缓存',
      message: '将清理本地缓存数据（网页缓存与离线课表缓存），不影响已添加的桌面卡片和登录状态。确定清理吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清理',
        fontColor: $r('sys.color.ohos_id_color_text_primary_activated'),
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
        hilog.info(SETTING_DOMAIN, SETTING_TAG, 'getBundleInfo failed: %{public}s', JSON.stringify(error));
        this.versionText = '未知';
      });
  }

  /** 复制 GitHub 开源地址 */
  private copyGithubUrl(): void {
    const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GITHUB_URL);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => {
        this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
      })
      .catch((error: BusinessError) => {
        hilog.info(SETTING_DOMAIN, SETTING_TAG, 'copy url failed: %{public}s', JSON.stringify(error));
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
            this.applySettings(isOn, this.reminderAdvance);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.reminderEnabled) {
        Divider()
          .color($r('sys.color.ohos_id_color_list_separator'))

        Text('提前提醒时间')
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, alignContent: FlexAlign.Center }) {
          ForEach([5, 10, 15, 20, 30], (minutes: number) => {
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
                  this.applySettings(this.reminderEnabled, minutes);
                }
              })
          }, (minutes: number) => 'advance' + minutes)
        }
        .width('100%')

        Text(this.nextReminder.length > 0 ?
          '下次提醒：' + this.nextReminder : '暂无即将到来的课程提醒')
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }

      Text('提醒由系统后台代理发送，应用退出或被清理后仍会准时送达；需授予通知权限。')
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
      hilog.info(SETTING_DOMAIN, SETTING_TAG, 'enterDeveloperPage clicked');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.Developer;
      });
      this.refreshCacheSize();
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
      hilog.info(SETTING_DOMAIN, SETTING_TAG, 'enterAboutPage clicked');
      this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
        this.subPage = SettingsSubPage.About;
      });
    })
  }

  /** 二级菜单顶栏（固定于屏幕左上角的圆形返回键 + 标题） */
  @Builder
  subHeader(title: string) {
    Row() {
      Stack() {
        Circle({ width: 44, height: 44 })
          .fill($r('sys.color.ohos_id_color_click_effect'))
          .position({ x: this.backPressX - 22, y: this.backPressY - 22 })
          .opacity(this.backPressed ? 1 : 0)
          .animation({ duration: 150, curve: Curve.EaseOut })
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .clip(true)
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.backPressX = event.touches[0].x;
          this.backPressY = event.touches[0].y;
          this.backPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.backPressed = false;
        }
      })
      .onClick(() => {
        hilog.info(SETTING_DOMAIN, SETTING_TAG, 'backToMain clicked');
        this.getUIContext().animateTo({ duration: PAGE_PUSH_DURATION, curve: Curve.Friction }, () => {
          this.subPage = SettingsSubPage.Main;
        });
      })

      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .padding({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
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
          JwxtRepository.sendTestReminder();
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

  /** 开发者选项：隐私模式（标准/限制/严格） */
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
      AlertDialog.show({
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

  /** 开发者选项：隐私模式卡片 */
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
    .margin({ top: 16 })
  }

  /** 开发者选项：缓存管理 */
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
          Text('含网页缓存与离线课表缓存')
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
        .padding({ left: 16, right: 16 })
        .onClick(() => {
          this.confirmClearCache();
        })

      Text('清理后不影响已添加的桌面卡片和登录状态。')
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

  /** 关于应用：版本号 */
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

      Button('复制地址')
        .fontSize(14)
        .height(36)
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

  build() {
    Column() {
      if (this.subPage === SettingsSubPage.Developer) {
        Column() {
          this.subHeader('开发者选项')
          Scroll() {
            Column() {
              this.developerCard()
              this.privacyCard()
              this.cacheCard()
            }
            .padding({ left: 16, right: 16, bottom: 88 })
            .constraintSize({ minWidth: '100%', minHeight: '100%' })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .transition(this.subPageEnter())
      } else if (this.subPage === SettingsSubPage.About) {
        Column() {
          this.subHeader('关于应用')
          Scroll() {
            Column() {
              this.versionCard()
              this.openSourceCard()
            }
            .padding({ left: 16, right: 16, bottom: 88 })
            .constraintSize({ minWidth: '100%', minHeight: '100%' })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .transition(this.subPageEnter())
      } else {
        Scroll() {
          Column() {
            this.sectionTitle('设置')
            this.reminderCard()
            this.sectionTitle('开发者选项')
            this.developerEntry()
            this.sectionTitle('关于')
            this.aboutEntry()
          }
          .padding({ left: 16, right: 16, bottom: 88 })
          .constraintSize({ minWidth: '100%', minHeight: '100%' })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
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
