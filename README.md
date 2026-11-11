# EDaYi（E大医）

> 面向大连医科大学的 HarmonyOS 原生一站式校园助手。
> 课表、成绩、综合测评、选课、培养计划、期末倒计时、上课提醒、桌面卡片，一个应用全搞定。

当前版本：**3.0.0**（versionCode 3000000）

## 功能一览

| 模块 | 说明 |
|---|---|
| 首页 | 今日课程、周课表切换（左右滑动/周 chip）、学生信息、期末倒计时、应用日志（开发者选项） |
| 成绩 | 学分绩点汇总卡、学期筛选、分类成绩分组、培养计划入口、成绩替代行解析（TDKCM） |
| 综评 | 批次上下文卡、素质得分多维图（雷达图）、指标分级展开、附加分明细、平板横屏双列布局 |
| 选课 | 独立选课系统账号、轮次 chip 切换、课程检索、选退课、已选管理、凭据加密存储 |
| 设置 | 上课提醒（系统通知 + 日历代理可选）、隐私三档模式（标准/限制/严格）、缓存清理、关于 |
| 桌面卡片 | 课表卡片（今天/明天、单双日）、期末倒计时卡片，无需打开应用即可查看 |

## 技术栈

- **HarmonyOS** / ArkTS / ArkUI（Stage 模型）
- **hvigor** 构建体系，**hypium** 单元测试（52 用例）
- 原生能力：Asset 凭据存储、通知/代理提醒、日历读写、卡片 Form、Web 网页登录
- 适配手机 / 折叠屏 / 平板，横屏双列布局，深浅色主题跟随系统

## 项目结构

```
AppScope/                     应用级配置（版本号、图标）
products/Pond/                主应用模块
  src/main/ets/
    pages/                    页面入口（Navigation 宿主）
    view/                     视图层（View + Cards 拆分，单参对象 Builder）
    viewmodel/                目录视图模型
    data/                     数据层（Repository、缓存、提醒调度、隐私控制）
    jwxt/parsers/             教务系统 HTML 解析器（成绩/课表/学生/培养计划）
    net/                      网络层（教务/选课/学工跨域会话）
    model/                    数据模型
    widget/pages/             桌面卡片
    theme/                    具名颜色常量（视图层禁硬编码 hex）
    constants/                路由/常量/状态键登记
  src/test/                   单元测试（52 用例）
common/                       公共 HAR 模块（断点系统）
scripts/verify.ps1            提交前三关卡校验脚本
tools/check_storage_keys.mjs  状态键契约校验
docs/开发规范.md               开发规范（提交前必读）
```

## 快速开始

1. 安装 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/)（含 HarmonyOS SDK）。
2. 导入本仓库根目录，等待 hvigor 同步。
3. 连接模拟器或真机，点击运行；或使用命令行：

```powershell
# 构建
devecocli build

# 部署到已连接设备（跳过构建）
devecocli run --skip-build --device <deviceId>
```

首次使用需在应用内登录学校统一认证，之后凭据按隐私模式本地加密存储。

## 构建与测试（提交前三关卡）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify.ps1
```

按顺序执行三道关卡，任一失败即非 0 退出：

1. **状态键契约校验**：`@StorageProp` 等装饰器状态键必须先在 `constants/StorageKeys.ets` 登记；
2. **Code Linter**：Error 级问题拦截，Warning 仅报告；
3. **单元测试**：hypium 52 用例全过。

## 隐私与安全设计

- **隐私三档模式**：标准（全量离线缓存）/ 限制（仅课表缓存）/ 严格（不缓存任何信息，退出即清理并登出）；
- 选课凭据使用系统 **Asset** 加密存储，登录 token 仅保留在内存、永不持久化；
- 离线数据在页面上以醒目横幅提示，可一键重登或重试刷新；
- 应用内行为日志仅存内存环形缓冲，随进程销毁。

## 相关文档

- [docs/开发规范.md](docs/开发规范.md) —— 提交规范、@Builder 传参规则、颜色与状态键契约
- 仓库：<https://github.com/Pond-official/EDaYi>
