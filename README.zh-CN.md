# API Meter

> 原生 macOS 菜单栏 + 悬浮 Dashboard，用于查看 DeepSeek API 使用情况。

[English](README.md) | [简体中文](README.zh-CN.md)

![platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue) ![swift](https://img.shields.io/badge/Swift-6-orange) ![license](https://img.shields.io/badge/license-MIT-green) [![CI](https://github.com/GabrielMu2006/APIMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/GabrielMu2006/APIMeter/actions/workflows/ci.yml)

API Meter 是一个本地优先的 macOS 应用，把 DeepSeek 官方数据（余额 API + 用量导出）
组织成一个常驻桌面的原生仪表盘。所有数据只留在你的 Mac 上：不抓网页、不读 Cookie、
不做 MITM。

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [安装](#安装)
- [首次配置](#首次配置)
- [日常使用](#日常使用)
- [数字是怎么算出来的](#数字是怎么算出来的)
- [DeepSeekSync（可选自动导出）](#deepseeksync可选自动导出)
- [开发](#开发)
- [常见问题](#常见问题)
- [隐私与安全](#隐私与安全)
- [许可证](#许可证)

## 功能特性

- **菜单栏快捷面板**：余额、今日花费、7 天迷你趋势、Top API Keys，一键打开 Dashboard
- **悬浮 Dashboard**：指标卡（余额 / 今日 / 期间花费 / 请求数 / Tokens）、7 天 / 30 天 / 本月 / 自定义时间范围、柱状图（悬停显示当天按 Key 明细）、每日历史（点击看当天详情）、API Key 多选筛选
- **按 Key 成本**：由官方导出的 `price x amount` 推导，并与账单总额交叉核对；导入采用替换语义，重复导入绝不会重复计费
- **余额推算今日花费**：今日成本由余额快照推算（昨日基线 − 今日余额，自动识别并忽略充值）；已完成的天以官方导出为准
- **每日自动同步**：可选 DeepSeekSync 模块每天 00:30 自动下载官方导出（错过则启动/唤醒时补跑）并自动导入
- **其他**：余额阈值提醒（防轰炸）、开机启动、Dock 图标开关、全局快捷键（默认 ⌥Space）、Pin / Mini 模式、窗口状态记忆、深色/浅色模式、macOS 26 Liquid Glass

## 系统要求

- macOS 15 或更高
- 预编译 DMG 为 Apple Silicon（arm64）。Intel 用户请从源码构建（见[开发](#开发)）

## 安装

### 方式一：下载 DMG（推荐）

1. 打开 [Releases](../../releases) 下载 `API-Meter-x.y.z.dmg`
2. 打开 DMG，把 **API Meter** 拖入 **应用程序**
3. 首次启动：**右键点击 App → 打开**（当前为 ad-hoc 本地签名，见常见问题）
4. App 常驻菜单栏，默认不显示 Dock 图标

### 方式二：源码构建

```bash
git clone https://github.com/GabrielMu2006/APIMeter.git
cd APIMeter
xcodebuild -project APIMeter.xcodeproj -scheme APIMeter \
  -configuration Release -derivedDataPath .build/DerivedData-Release build
open ".build/DerivedData-Release/Build/Products/Release/API Meter.app"
```

或用 Xcode 打开 `APIMeter.xcodeproj` 直接 Run。

## 首次配置

### 1. 添加 DeepSeek API Key

1. 点菜单栏图标 → 齿轮按钮（或在 Dashboard 右上角点齿轮）
2. 进入 **DeepSeek** 页，把 API Key 粘贴到安全输入框
3. 点 **Save to Keychain**，再点 **Test Connection**，余额出现即成功

Key 只保存在 macOS 钥匙串（条目 `com.apimeter.deepseek-api-keys`）。
数据库只存 Key 的 SHA256 指纹，绝不存明文。

### 2. 导入历史用量

1. 在 DeepSeek 平台导出用量：
   `platform.deepseek.com → 用量信息 → 选择时间维度 → 导出`，
   得到包含 `amount-*.csv`（按 Key 的 token/请求量）和 `cost-*.csv`（按天/模型的金额）的 ZIP
2. 在 API Meter 中：**Settings → Data → Import Usage Export...**（或直接把 ZIP/CSV 拖到 Data 页）
3. 重复导入是安全的：文件按 SHA256 去重；更新的导出会**替换**同一天桶的旧总额

### 3.（可选）开启每日自动导出

见 [DeepSeekSync](#deepseeksync可选自动导出)。不开启的话，手动重新导入导出文件即可。

### 4. 余额提醒

**Settings → Notifications**：选择阈值（Off / ¥5 / ¥10 / ¥20 / 自定义），
点 **Allow Notifications**。余额每次跌破阈值只提醒一次，回升到阈值之上后重新武装。
若系统弹窗被拒绝：系统设置 → 通知 → API Meter → 允许。

### 5. 通用设置

- **Launch at Login**：App 需在「应用程序」目录才能可靠生效
- **Show Dock Icon**：立即切换 Dock 显示
- **Global Shortcut**：默认 ⌥Space，可重新录制
- **Appearance**：System / Light / Dark

## 日常使用

| 位置 | 内容 |
|---|---|
| 菜单栏面板 | 余额 + 更新时间、今日（请求/Tokens）、7 天迷你趋势、Top 3 Keys、打开 Dashboard / 设置 / 退出 |
| Dashboard 顶栏 | Pin（悬浮置顶）、Mini 模式、设置、刷新（**只刷新余额，绝不触发导出同步**） |
| 指标卡 | 余额、今日（点击打开今日详情）、期间花费、请求数、Tokens |
| 柱状图 | 悬停任意柱子：日期、花费、请求、Tokens 及当天按 Key 明细 |
| 每日列表 | 点击某天查看详情：总额 + 按 Key 明细 |
| API Keys 面板 | 所选时间范围内按 Key 的成本 / 请求 / Tokens；上方多选筛选 |
| Mini 模式 | 只显示余额 + 今日；可拖拽、双击展开、右键操作 |

## 数字是怎么算出来的

- **官方导出是已完成天的权威数据**。它的日桶是累计快照，因此导入采用按（天、模型、Key）
  分组的替换语义。
- **按 Key 成本**由导出文件自带的 `price x amount` 推导，导入时与账单总额交叉核对；
  不一致则标记为 estimated。
- **金额用 Decimal、Token 用 Int64、时间存 UTC**。日桶在导入时按本地时区一次性计算，
  时区变更不会破坏历史。

### 今日花费的计算机制（余额推算法）

今日花费是**估算值**，由余额快照推算（余额 API 没有按 Key / 按时段的数据，这是唯一
可用的实时信号）：

1. **基线**：本地午夜前的最后一次余额快照（App 每次刷新余额都会自动存快照）
2. 今天的每条快照与前一条比较：
   - 余额下降 → 差额计入消费
   - 余额上升 → 视为充值（或赠送）并忽略
3. 所有下降量之和 = 今日花费。面板/仪表盘可见时每 60 秒刷新一次余额，后台每 15 分钟
   一次，今日花费随之更新

回退规则（Today 卡片上会明确标注口径）：

- **尚无午夜基线**（如安装第一天、或 Mac 跨夜关机）：从「今天第一条快照」起算，
  标注 "since HH:mm"；该快照之前的消费未被计入
- **基线超过 24 小时会被拒绝**（避免混入多天误差）
- **完全没有快照**：回退显示最近一次官方导出值，并标注导入时间

### 重要：使用 API 期间请勿充值

充值会**掩盖**消费：余额跳涨，同一次刷新窗口内（下次刷新前）发生的消费会被上涨抵消，
下降量不再出现，导致当日估算偏低。**请在 API 空闲时充值。** 无论估算值如何，官方导出
（每天 00:30 自动同步）都会在次日修正已完成天的账单。

## DeepSeekSync（可选自动导出）

一个独立 CLI（Node + Playwright），在**自己的**浏览器配置里打开官方用量页面，
点击官方「导出」按钮并下载 ZIP。App 每天 00:30 运行一次（错过则下次启动/唤醒补跑）。

```bash
cd DeepSeekSync
./scripts/setup-runtime.sh   # 内置便携 Node + 安装 Playwright 与 Chromium（无需系统安装）
./deepseek-sync login       # 弹出浏览器窗口，手动完成登录（验证码/MFA 等一切步骤）
                            # 会话（Cookie + localStorage）加密存入 macOS 钥匙串
./deepseek-sync sync        # 隐藏窗口运行：选近30天 → 点导出 → 下载 ZIP
./deepseek-sync status      # 查看会话与上次同步信息
./deepseek-sync dump        # 调试：打印页面按钮/链接文本
./deepseek-sync logout      # 删除已保存的会话
```

然后在 App 里指定目录：**Settings → Data → DeepSeekSync path**（粘贴 DeepSeekSync 目录的
绝对路径）。此后每日同步会**下载并自动导入**。刷新按钮只更新余额，不会触发同步。

安全说明：不读取你正常浏览器的 Cookie、不保存 DeepSeek 用户名与密码、不调用未公开 API。

## 开发

```bash
swift build && swift test        # 核心库 + CLI + 64 个单元测试
.build/debug/apimeter selfcheck  # 端到端自检（钥匙串/数据库/CSV/定价）
.build/debug/apimeter help
```

CLI 命令：`keychain set/list/delete`、`balance`、`db init/info/dump`、`analyze`、
`import`、`daily`、`rebuild`、`selfcheck`。

目录结构：

```
APIMeter/            App + 核心源码（Xcode App target + SPM 库）
Tools/PhaseAValidator 验证 CLI
DeepSeekSync/        Playwright 导出下载器（独立，内置 Node 已 gitignore）
Tests/               Swift Testing 单元测试
docs/                Schema 与阶段报告（真实样例已 gitignore）
```

欢迎提交 PR，见 CONTRIBUTING.md。CI 在 macOS runner 上执行构建与测试。

## 常见问题

| 问题 | 解决办法 |
|---|---|
| 提示「API Meter」无法打开（未验证开发者） | 首次右键 → 打开（ad-hoc 签名） |
| 重新构建后余额获取失败 | 钥匙串条目与构建签名绑定：在 Settings → DeepSeek 重新输入 Key 保存 |
| 今日显示「—」 | 尚无午夜前的余额快照基线；保持 App 运行，或等待回退显示官方值 |
| 每日同步提示 session expired | 在 DeepSeekSync 目录重新执行 `./deepseek-sync login` |
| 每日同步提示 not configured | 在 Settings → Data 填入 DeepSeekSync 目录路径 |
| 数字偏大 | 历史 bug：重复导入会累加（已用替换语义修复）。重新导入最新导出或执行 `apimeter rebuild <zip>` |
| 收不到通知 | 系统设置 → 通知 → API Meter → 允许 |

## 隐私与安全

- API Key 只存 macOS 钥匙串；SQLite 只存 SHA256 指纹。
- 不读浏览器 Cookie、除官方导出按钮外不抓取用量页面、不做 HTTPS MITM、不装根证书。
- 日志经过脱敏（`sk-***`），绝不含 Prompt 或补全内容。
- 所有数据只留在你的 Mac 上。详见 [PRIVACY.md](PRIVACY.md)。

## 许可证

[MIT](LICENSE)