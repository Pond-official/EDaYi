# e大医 · eDaiYi

大连医科大学教务系统的 HarmonyOS 客户端，使用 ArkTS / ArkUI 开发。

> 非官方应用，仅供个人学习与自用。

## 功能

- **教务登录**：内置 WebView 打开学校统一入口，账号密码只在学校的登录页面输入，应用不接触。
- **课表**：按教学周展示课程，支持查看今日课程。
- **成绩**：查询并展示各学期成绩。
- **选课**：查看选课信息。
- **期末考试**：录入考试时间后按远近排列倒计时。
- **上课提醒**：上课前通过系统通知提醒，提醒时间可自定义（后台代理提醒，应用退出后仍会送达）。
- **桌面卡片**：「今日课程」与「期末倒计时」两种服务卡片，课程卡片支持 2×4 与 4×4 两种尺寸。
- **隐私模式**：标准 / 限制 / 严格三档，控制本地缓存范围与退出行为。
- **缓存管理**：查看缓存占用、一键清理，不影响登录状态与桌面卡片。
- **数据备份**：支持系统备份扩展。

## 技术栈

| 项目     | 说明                                                                                                                                   |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 语言     | ArkTS                                                                                                                                |
| UI     | ArkUI 声明式开发，HdsNavigation / HdsTabs 悬浮导航栏                                                                                            |
| SDK    | HarmonyOS 6.1.1（API 24）                                                                                                              |
| 构建     | hvigor                                                                                                                               |
| 包管理    | ohpm                                                                                                                                 |
| 主要 Kit | AbilityKit、ArkWeb、NetworkKit、NotificationKit、BackgroundTasksKit（reminderAgentManager）、CalendarKit、UIDesignKit、PerformanceAnalysisKit |
| 数据来源   | 学校教务系统 `jwxt.dmu.edu.cn`（WebView 登录 + Cookie 会话 + HTTP 请求）                                                                           |
| 本地存储   | 应用沙箱 preferences 与 cache 目录                                                                                                          |

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
│           │   ├── pages/           Index（首页/成绩/选课/设置）、LoginIndex（登录）
│           │   ├── view/            HomeView、GradeView、SelectionView、ScheduleBoard、SettingsView
│           │   ├── data/            JwxtRepository（教务数据）、ReminderScheduler（提醒）、CacheManager、CardDataStore
│           │   ├── model/           数据模型
│           │   ├── widget/pages/    卡片 UI：ScheduleCard、ScheduleCardLarge、ExamCountdownCard
│           │   ├── scheduleformability/  「今日课程」卡片 FormAbility
│           │   ├── examformability/      「期末倒计时」卡片 FormAbility
│           │   ├── pondability/          主 Ability
│           │   ├── pondbackupability/    备份扩展
│           │   └── utils/                考试日期计算等工具
│           └── resources/           字符串、颜色、卡片配置
├── oh-package.json5                 依赖声明
└── hvigorfile.ts                    构建脚本
```

## 环境要求

- DevEco Studio（支持 API 24 的版本）
- HarmonyOS SDK 6.1.1（API 24）
- 真机或模拟器

## 构建与运行

1. 克隆仓库，用 DevEco Studio 打开项目根目录。
2. 等待 Sync 完成，按提示执行 `ohpm install` 拉取依赖。
3. 配置签名：`File → Project Structure → Signing Configs`，勾选自动生成调试签名。
4. 选择设备后运行 `Pond` 模块即可。

> 仓库未包含根目录的 `build-profile.json5`（含本机签名证书路径与密钥，不适合公开）。首次打开若提示缺少该文件，在 DevEco Studio 中完成签名配置后会自动生成，不影响源码使用。

## 权限说明

| 权限                                                 | 用途                      |
| -------------------------------------------------- | ----------------------- |
| `ohos.permission.INTERNET`                         | 访问教务系统                  |
| `ohos.permission.PUBLISH_AGENT_REMINDER`           | 发布后台代理提醒（上课提醒）          |
| `ohos.permission.READ_CALENDAR` / `WRITE_CALENDAR` | 清理旧版日历方案遗留的日历账户，不再写入新日程 |
| `ohos.permission.HDR_BRIGHTNESS`                   | 导航栏光感效果                 |

## 隐私说明

- **账号密码不经过应用**：登录在 WebView 内完成，由学校页面直接提交，应用只读取登录后的会话 Cookie。
- **数据只存在本机**：会话 Cookie、课表、成绩等均保存在应用沙箱，不上传任何第三方服务器。
- **三档隐私模式**：
  - 标准：缓存课表、成绩等全部信息（默认）。
  - 限制：仅缓存课表以支持桌面卡片，其余数据不落盘。
  - 严格：不缓存任何信息；应用退到后台或退出时自动清理缓存并退出登录，桌面卡片不可用。
- **随时可清除**：设置页可查看缓存占用并一键清理。

## 版本

当前版本 **1.6.0**（versionCode 1060000）。

- 1.6.0：新增期末倒计时卡片、隐私模式、前后台切换处理；移除示例模块，工程精简为 `Pond` + `common`。
- 1.5.0：新增上课提醒（后台代理提醒）、设置页、离线缓存。
- 1.2.0：初始版本，包含登录、课表、成绩、选课页面。

## 免责声明

- 本项目为非官方客户端，与大连医科大学无隶属关系。
- 教务系统接口可能随学校升级而变化，届时部分功能可能失效。
- 使用本应用产生的任何后果由使用者自行承担，请遵守学校相关管理规定。

## 许可

本仓库未声明开源许可证。如需转载或二次分发，请联系作者。
