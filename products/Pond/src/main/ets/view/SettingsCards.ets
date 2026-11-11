/** 提前提醒时间快捷选项（分钟），另提供 1-120 分钟自定义输入（自 SettingsView 拆出） */
const ADVANCE_PRESETS: number[] = [5, 10, 15, 20, 30];

/** 当前提前时间是否为自定义值（不在快捷选项内）（自 SettingsView 拆出） */
function isCustomAdvance(reminderAdvance: number): boolean {
  return ADVANCE_PRESETS.indexOf(reminderAdvance) < 0;
}

/** 自定义提前时间 chip 文案：已选自定义值时显示具体分钟数（自 SettingsView 拆出） */
function customAdvanceLabel(reminderAdvance: number): string {
  return isCustomAdvance(reminderAdvance) ? `${reminderAdvance}分钟` : '自定义';
}

/** 区块标题（自 SettingsView 拆出） */
@Builder
export function SettingsSectionTitle(title: string) {
  Text(title)
    .fontSize(16)
    .fontWeight(FontWeight.Bold)
    .fontColor($r('sys.color.ohos_id_color_text_primary'))
    .padding({ top: 16, bottom: 8 })
}

/** 上课提醒卡入参（单参对象字面量按引用传递，开关/提前分钟/代理开关随设置刷新；
 * 自定义输入弹层由 SettingsView 持有（bindSheet 挂在页面根节点），本卡仅回调打开） */
export interface SettingsReminderCardParams {
  reminderEnabled: boolean;
  nextReminder: string;
  reminderAdvance: number;
  reminderAgentEnabled: boolean;
  onToggleReminder: (isOn: boolean) => void;
  onSelectAdvance: (minutes: number) => void;
  onOpenAdvanceSheet: () => void;
  onToggleAgent: (isOn: boolean) => void;
}

/** 上课提醒卡（自 SettingsView 拆出；onToggleReminder 切换开关，onSelectAdvance 选择提前分钟数，
 * onOpenAdvanceSheet 打开自定义输入弹层，onToggleAgent 切换代理提醒） */
@Builder
export function SettingsReminderCard(params: SettingsReminderCardParams) {
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

      Toggle({ type: ToggleType.Switch, isOn: params.reminderEnabled })
        .onChange((isOn: boolean) => {
          params.onToggleReminder(isOn);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    if (params.reminderEnabled) {
      Text(params.nextReminder.length > 0 ?
        '下次提醒：' + params.nextReminder : '暂无即将到来的课程提醒')
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
            .fontWeight(params.reminderAdvance === minutes ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(params.reminderAdvance === minutes ? Color.White :
              $r('sys.color.ohos_id_color_text_primary_activated'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(params.reminderAdvance === minutes ?
              $r('sys.color.ohos_id_color_text_primary_activated') :
              $r('sys.color.ohos_id_color_button_normal'))
            .onClick(() => {
              params.onSelectAdvance(minutes);
            })
        }, (minutes: number) => 'advance' + minutes
          + (params.reminderAdvance === minutes ? ':on' : ':off'))
        Text(customAdvanceLabel(params.reminderAdvance))
          .fontSize(13)
          .fontWeight(isCustomAdvance(params.reminderAdvance) ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(isCustomAdvance(params.reminderAdvance) ? Color.White :
            $r('sys.color.ohos_id_color_text_primary_activated'))
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .margin({ right: 8, bottom: 8 })
          .borderRadius(16)
          .backgroundColor(isCustomAdvance(params.reminderAdvance) ?
            $r('sys.color.ohos_id_color_text_primary_activated') :
            $r('sys.color.ohos_id_color_button_normal'))
          .onClick(() => {
            params.onOpenAdvanceSheet();
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
        Toggle({ type: ToggleType.Switch, isOn: params.reminderAgentEnabled })
          .onChange((isOn: boolean) => {
            params.onToggleAgent(isOn);
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
}

/** 隐私模式卡入参（单参对象字面量按引用传递，选中 Radio 随隐私模式刷新） */
export interface SettingsPrivacyCardParams {
  privacyMode: string;
  onSelect: (value: string) => void;
}

/** 隐私模式卡（自 SettingsView 拆出；onSelect 选择模式；三行选项内联直读 params，选中态随绑定刷新） */
@Builder
export function SettingsPrivacyCard(params: SettingsPrivacyCardParams) {
  Column() {
    Text('隐私')
      .fontSize(13)
      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      .width('100%')

    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('标准')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('缓存个人成绩、课表等所有信息（默认）')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: 'standard', group: 'privacyMode' })
        .checked(params.privacyMode === 'standard')
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      params.onSelect('standard');
    })

    Divider()
      .color($r('sys.color.ohos_id_color_list_separator'))

    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('限制')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('仅缓存课表供桌面卡片使用，其他数据都不会缓存')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: 'restricted', group: 'privacyMode' })
        .checked(params.privacyMode === 'restricted')
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      params.onSelect('restricted');
    })

    Divider()
      .color($r('sys.color.ohos_id_color_list_separator'))

    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text('严格')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Text('不缓存任何信息；进入后台或退出后清理缓存并退出登录，桌面卡片不可用')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: 'strict', group: 'privacyMode' })
        .checked(params.privacyMode === 'strict')
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      params.onSelect('strict');
    })
  }
  .width('100%')
  .alignItems(HorizontalAlign.Start)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 存储管理卡入参（单参对象字面量按引用传递，清理后缓存大小随刷新更新） */
export interface SettingsCacheCardParams {
  cacheSizeText: string;
  onClearCache: () => void;
}

/** 存储管理卡（自 SettingsView 拆出；onClearCache 弹窗确认后清理） */
@Builder
export function SettingsCacheCard(params: SettingsCacheCardParams) {
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

      Text(params.cacheSizeText)
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
        params.onClearCache();
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
