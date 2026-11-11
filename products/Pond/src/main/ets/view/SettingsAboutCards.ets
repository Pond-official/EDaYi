/** GitHub 开源地址（自 SettingsView 拆出） */
export const GITHUB_URL: string = 'https://github.com/Pond-official/EDaYi';

/** 开发者选项入口（自 SettingsView 拆出；onEnter 进入开发者选项二级页） */
@Builder
export function SettingsDeveloperEntry(onEnter: () => void) {
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
    onEnter();
  })
}

/** 关于应用入口（自 SettingsView 拆出；onEnter 进入关于应用二级页） */
@Builder
export function SettingsAboutEntry(onEnter: () => void) {
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
    onEnter();
  })
}

/** 开发者模式开关卡入参（单参对象字面量按引用传递，开关随开发者模式状态刷新） */
export interface SettingsDeveloperModeCardParams {
  developerMode: boolean;
  onModeToggle: (isOn: boolean) => void;
}

/** 开发者模式开关卡（自 SettingsView 拆出；onModeToggle 切换开发者模式，关闭即回主页） */
@Builder
export function SettingsDeveloperModeCard(params: SettingsDeveloperModeCardParams) {
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

    Toggle({ type: ToggleType.Switch, isOn: params.developerMode })
      .onChange((isOn: boolean) => {
        params.onModeToggle(isOn);
      })
  }
  .width('100%')
  .alignItems(VerticalAlign.Center)
  .padding(16)
  .borderRadius(16)
  .backgroundColor($r('app.color.card_background'))
}

/** 调试工具卡（自 SettingsView 拆出；onSendTest 发送测试通知） */
@Builder
export function SettingsDeveloperCard(onSendTest: () => void) {
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
        onSendTest();
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

/** 版本号卡入参（单参对象字面量按引用传递，versionText 异步读取后随状态刷新） */
export interface SettingsVersionCardParams {
  versionText: string;
  onVersionTap: () => void;
}

/** 版本号卡（自 SettingsView 拆出；onVersionTap 连续点击 5 次可开启开发者选项） */
@Builder
export function SettingsVersionCard(params: SettingsVersionCardParams) {
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

    Text(params.versionText)
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
    params.onVersionTap();
  })
}

/** 开源地址卡（自 SettingsView 拆出；onOpen 弹窗确认后打开地址，onCopy 复制地址） */
@Builder
export function SettingsOpenSourceCard(onOpen: () => void, onCopy: () => void) {
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
        onOpen();
      })

    Button('复制地址')
      .fontSize(14)
      .height(36)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        onCopy();
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

/** 特别鸣谢卡（自 SettingsView 拆出） */
@Builder
export function SettingsAcknowledgementCard() {
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
