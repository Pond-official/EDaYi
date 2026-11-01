# e大医 · eDaiYi

大连医科大学教务系统的 HarmonyOS 客户端，使用 ArkTS / ArkUI 开发。

> 非官方应用，仅供个人学习与自用。

## 功能

- **教务登录**：内置 WebView 打开学校统一入口，账号密码只在学校的登录页面输入，应用不接触。
- **课表**：按教学周展示课程，支持查看今日课程。
- **成绩**：查询并展示各学期成绩。
- **选课**：选课系统原生登录（图形验证码），支持按课程名或教师检索、分页浏览、提交选课、查看已选结果；登录凭据可由用户选择保存到系统关键资产存储。
- **期末考试**：录入考试时间后按远近排列倒计时。
- **上课提醒**：上课前通过系统通知提醒，提醒时间可自定义（后台代理提醒，应用退出后仍会送达）。
- **桌面卡片**：「今日课程」与「期末倒计时」两种服务卡片，课程卡片支持 2×4 与 4×4 两种尺寸。
- **隐私模式**：标准 / 限制 / 严格三档，控制本地缓存范围与退出行为。
- **缓存管理**：查看缓存占用、一键清理，不影响登录状态与桌面卡片。
- **设置页**：从各页面右上角入口进入独立设置页，集中管理提醒、隐私、缓存与版本信息。
- **数据备份**：支持系统备份扩展。

## 技术栈

| 项目 | 说明 |
| --- | --- |
| 语言 | ArkTS |
| UI | ArkUI 声明式开发，HdsNavigation / HdsTabs 悬浮导航栏，顶部沉浸材质条 |
| SDK | HarmonyOS 7.0.0（API 26） |
| 构建 | hvigor |
| 包管理 | ohpm |
| 主要 Kit | AbilityKit、ArkWeb、NetworkKit、NotificationKit、BackgroundTasksKit（reminderAgentManager）、CalendarKit、CryptoArchitectureKit（AES 加密密码）、AssetStoreKit（凭据存储）、UIDesignKit、PerformanceAnalysisKit |
| 数据来源 | 教务 `jwxt.dmu.edu.cn`（WebView 登录 + Cookie 会话）；选课 `jwxk.dmu.edu.cn/xsxk`（原生 HTTP 接口） |
| 本地存储 | 应用沙箱 preferences 与 cache 目录；选课登录凭据存于系统关键资产存储 |

## 工程结构

```
eDaiYi_Next/
├── AppScope/                        应用级配置与资源（包名、版本、图标）
├── common/                          公共模块 @ohos/common
│   └── src/main/ets/                常量与工具
├── products/
│   └── Pond/                        入口模块（entry）
│       └── src/main/
│           ├── ets/
│           │   ├── pages/           Index（首页/成绩/选课）、LoginIndex（教务登录）、SettingsIndex（设置）
│           │   ├── view/            HomeView、GradeView、SelectionView、ScheduleBoard、SettingsView、FrostBand、SettingsEntryButton
│           │   ├── data/            JwxtRepository（教务数据）、SelectionRepository（选课系统）、ReminderScheduler（提醒）、CacheManager、CardDataStore
│           │   ├── model/           JwModels、SelectionModels
│           │   ├── widget/pages/    卡片 UI：ScheduleCard、ScheduleCardLarge、ExamCountdownCard
│           │   ├── scheduleformability/  「今日课程」卡片 FormAbility
│           │   ├── examformability/      「期末倒计时」卡片 FormAbility
│           │   ├── pondability/          主 Ability
│           │   ├── pondbackupability/    备份扩展
│           │   └── utils/                ExamDateUtils（考试日期计算）、MaterialUtils（沉浸材质）
│           └── resources/           字符串、颜色、卡片配置
├── oh-package.json5                 依赖声明
└── hvigorfile.ts                    构建脚本
```

## 环境要求

- DevEco Studio（支持 API 26 的版本）
- HarmonyOS SDK 7.0.0（API 26）
- 真机或模拟器（HarmonyOS 7.0.0 及以上）

## 构建与运行

1. 克隆仓库，用 DevEco Studio 打开项目根目录。
2. 等待 Sync 完成，按提示执行 `ohpm install` 拉取依赖。
3. 配置签名：`File → Project Structure → Signing Configs`，勾选自动生成调试签名。
4. 选择设备后运行 `Pond` 模块即可。

> 仓库未包含根目录的 `build-profile.json5`（含本机签名证书路径与密钥，不适合公开）。首次打开若提示缺少该文件，在 DevEco Studio 中完成签名配置后会自动生成，不影响源码使用。

## 权限说明

| 权限 | 用途 |
| --- | --- |
| `ohos.permission.INTERNET` | 访问教务与选课系统 |
| `ohos.permission.PUBLISH_AGENT_REMINDER` | 发布后台代理提醒（上课提醒） |
| `ohos.permission.READ_CALENDAR` / `WRITE_CALENDAR` | 清理旧版日历方案遗留的日历账户，不再写入新日程 |
| `ohos.permission.HDR_BRIGHTNESS` | 导航栏光感效果 |

## 隐私说明

- **教务登录不经过应用**：登录在 WebView 内完成，由学校页面直接提交，应用只读取登录后的会话 Cookie。
- **选课登录为原生提交**：密码使用学校登录页同款的前端 AES 密钥加密后发送，不以明文传输；仅在用户主动勾选时保存凭据，存放于系统关键资产存储（系统级加密、仅本机可读），可随时在设置页清除。
- **数据只存在本机**：会话 Cookie、课表、成绩、选课信息均保存在应用沙箱，不上传任何第三方服务器。
- **三档隐私模式**：
  - 标准：缓存课表、成绩等全部信息（默认）。
  - 限制：仅缓存课表以支持桌面卡片，其余数据不落盘。
  - 严格：不缓存任何信息；应用退到后台或退出时自动清理缓存并退出登录，桌面卡片不可用。
- **随时可清除**：设置页可查看缓存占用并一键清理。

## 版本

当前版本 **2.0.0**（versionCode 2000000）。

- 2.0.0：选课系统改为原生登录（AES 加密密码 + 图形验证码），凭据存入系统关键资产存储；选课页重写，支持检索、分页与已选查询；设置改为独立页面，新增顶部材质条与设置入口按钮；更新深浅色配色。
- 1.6.0：新增期末倒计时卡片、隐私模式、前后台切换处理；移除示例模块，工程精简为 `Pond` + `common`。
- 1.5.0：新增上课提醒（后台代理提醒）、设置页、离线缓存。
- 1.2.0：初始版本，包含登录、课表、成绩、选课页面。

## 免责声明

- 本项目为非官方客户端，与大连医科大学无隶属关系。
- 教务与选课系统接口可能随学校升级而变化，届时部分功能可能失效。
- 使用本应用产生的任何后果由使用者自行承担，请遵守学校相关管理规定。

## 许可

本项目基于 [MIT License](LICENSE) 开源，Copyright (c) 2026 Pond-official。

你可以自由使用、修改、分发本项目的代码，包括商业用途，只需保留版权声明与许可证文本。

欢迎提交 Issue 与 Pull Request。

> 说明：`common` 模块的包描述文件标注的许可证为 Apache-2.0（继承自工程模板），本仓库整体以 MIT 发布。
