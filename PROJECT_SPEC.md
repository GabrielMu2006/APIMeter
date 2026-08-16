# API Meter — macOS DeepSeek API Usage Dashboard

> 项目类型：原生 macOS 菜单栏 + 悬浮 Dashboard  
> 目标平台：macOS 15+  
> 推荐技术栈：Swift 6 / SwiftUI / AppKit  
> 文档状态：开发执行稿  
> 更新时间：2026-08-16

---

# 1. 项目概述

## 1.1 项目目标

开发一个原生 macOS 常驻工具，用于查看和管理 DeepSeek API 的：

- 当前账户余额
- 今日消费金额
- 历史每日消费金额
- API 请求次数
- Token 使用量
- 多 API Key 消费分布
- 7 天 / 30 天 / 本月 / 自定义时间范围趋势
- 余额不足提醒

产品以：

> **菜单栏快速查看 + 可 Pin 的完整悬浮 Dashboard + Mini 悬浮模式**

为主要交互形式。

项目暂定名称：

```text
API Meter
```

名称保持中性，方便未来扩展其他 API Provider，同时避免让用户误认为是 DeepSeek 官方软件。

---

# 2. 核心产品原则

整个项目遵循以下原则：

1. **原生 macOS 体验优先**
2. **数据尽可能来自 DeepSeek 官方来源**
3. **不自动抓取 DeepSeek Usage 网页**
4. **不读取 Safari / Chrome Cookie**
5. **不保存 DeepSeek 登录密码**
6. **敏感凭据只保存到 macOS Keychain**
7. **历史 Usage 数据只保存在本机**
8. **核心功能即使离线也能查看已有历史数据**
9. **数据获取模块与 UI 解耦**
10. **先验证数据链路，再开发完整 UI**

---

# 3. 非目标

V1 不考虑以下功能：

- 多 DeepSeek 账号
- 云同步
- iCloud 同步
- iOS / iPadOS
- Web Dashboard
- 团队账户
- 多人共享
- SaaS 服务
- 服务端数据库
- 自动读取浏览器 Cookie
- 自动抓取 DeepSeek Usage 网页
- 自动保存用户 DeepSeek 密码
- 自动安装系统根证书
- HTTPS MITM
- 系统级网络代理劫持

---

# 4. 最终产品形态

应用由四个主要 UI Surface 组成：

```text
API Meter
│
├── Menu Bar Panel
│
├── Floating Dashboard
│
├── Mini Floating Panel
│
└── Settings
```

另外包含：

```text
History Detail
CSV Import
CSV Export
Balance Notification
```

---

# 5. 产品定位

产品主要用于：

> 长期使用 DeepSeek API 的 macOS 用户快速了解 API 消费情况。

重点不是完整复刻 DeepSeek 官网，而是把官网 Usage 中最重要的数据重新组织成一个适合长期常驻桌面的原生 macOS 工具。

---

# 6. 数据源设计

整个系统使用三类数据源。

```text
                    API Meter
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
Balance API       Official CSV      Local Gateway
        │               │               │
        ▼               ▼               ▼
当前余额          历史真实账单       实时本地统计
```

---

# 7. 数据源一：DeepSeek Balance API

## 7.1 用途

用于获得：

- 当前余额
- 充值余额
- 赠送余额
- 货币类型
- 当前账户是否可继续调用

主要用于：

```text
当前余额
Mini Panel
Menu Bar
余额不足提醒
```

---

# 8. API Key 保存策略

至少保存一个能够读取余额的 DeepSeek API Key。

必须使用：

```text
macOS Keychain
```

禁止：

```text
UserDefaults
plist
SQLite 明文
日志文件
配置文件
.env
```

保存完整 API Key。

SQLite 中只能保存：

```text
keyFingerprint
displayName
metadata
```

---

# 9. API Key Fingerprint

使用：

```text
SHA256(API_KEY)
```

生成唯一标识。

例如：

```text
sk-xxxxxxxxxxxxxxxx
        ↓
SHA256
        ↓
A7E92C14...
```

数据库只保存：

```text
A7E92C14...
```

原始 Key 仅存在：

```text
Keychain
```

或者只存在于外部应用配置中。

---

# 10. 多 API Key 支持

单 DeepSeek Account 下允许存在多个 API Key。

例如：

```text
DeepSeek Account
│
├── Coding
├── Research
├── Python
└── Test
```

用户可以为每个 API Key 设置：

```text
Display Name
```

例如：

```text
官方名称：key_8492
本地名称：Research
```

Dashboard 始终优先显示：

```text
Local Alias
```

若不存在 Alias，则显示官方名称。

---

# 11. 数据源二：DeepSeek 官方 Usage Export

历史真实消费优先使用：

> DeepSeek 官方 Usage Export 数据。

用户在 DeepSeek Usage 页面：

```text
选择月份
    ↓
Export
    ↓
ZIP / CSV
```

随后导入 API Meter。

---

# 12. CSV 导入方式

必须支持：

### 方式一

拖入 ZIP。

### 方式二

拖入 CSV。

### 方式三

系统文件选择器：

```text
FileImporter
```

---

# 13. CSV Import Pipeline

推荐：

```text
File
 ↓
Detect Type
 ↓
ZIP Extract
 ↓
CSV Parser
 ↓
Schema Detection
 ↓
Normalization
 ↓
Deduplication
 ↓
SQLite
 ↓
Aggregation
```

---

# 14. CSV Schema 技术验证

这是项目开发前必须首先验证的内容之一。

需要从真实 DeepSeek Usage 页面导出一个月份的数据。

检查是否包含：

```text
date
timestamp
api_key
api_key_name
request_count
input_tokens
output_tokens
cache_hit_tokens
cache_miss_tokens
total_tokens
amount
model
currency
```

实际字段以官方导出文件为准。

不要提前假设 CSV Schema。

必须先：

```text
Export → Inspect → Document Schema
```

再实现正式 Parser。

---

# 15. 历史消费目标

用户需要能够查询：

```text
今天
昨天
最近 7 天
最近 30 天
本月
自定义日期
全部历史
```

历史记录尽可能永久保存。

设置中允许选择：

```text
30 Days
90 Days
1 Year
Forever
```

默认：

```text
Forever
```

---

# 16. CSV 去重

必须避免同一文件重复导入导致消费金额重复。

每个文件计算：

```text
SHA256(fileContent)
```

保存：

```text
import_batches
```

如果 hash 已存在：

```text
Ignore
```

并显示：

```text
This usage file has already been imported.
```

---

# 17. 行级去重

除文件级去重外，建议每条 Usage 数据生成：

```text
sourceRowHash
```

例如基于：

```text
date
apiKey
amount
tokens
requestCount
model
```

生成稳定 hash。

用于避免：

```text
不同月份导出文件存在重叠
```

造成重复。

---

# 18. 数据源三：Local Usage Gateway

Local Gateway 属于：

> **可选高级功能**

不应阻塞 MVP。

目标是实现：

```text
Coding Tool
Python Program
Other Client
      │
      ▼
127.0.0.1
API Meter Gateway
      │
      ▼
DeepSeek
```

---

# 19. 为什么需要 Local Gateway

官方 CSV 更适合：

```text
历史账单
对账
```

但不适合：

```text
分钟级实时 Dashboard
```

Local Gateway 可以实时记录：

```text
timestamp
apiKey
model
input tokens
output tokens
cache hit
cache miss
request
estimated cost
```

从而立即更新：

```text
今日消费
今日 Token
今日请求次数
```

---

# 20. Gateway 原则

Gateway 必须：

```text
listen = 127.0.0.1
```

禁止：

```text
0.0.0.0
```

默认端口可以使用：

```text
43123
```

但必须支持检测端口占用。

---

# 21. Gateway 不应该做什么

禁止：

- 修改 Prompt
- 修改系统消息
- 修改返回内容
- 修改模型参数
- 保存 Prompt
- 保存 Completion
- 保存用户对话
- HTTPS MITM
- 安装根证书

原则：

> Gateway 只负责 transparent forwarding + Usage metadata collection。

---

# 22. Gateway 请求链路

例如：

```text
Client
  │
  ▼
http://127.0.0.1:43123
  │
  ▼
Usage Gateway
  │
  ├── Forward Request
  │
  ▼
DeepSeek
  │
  ▼
Response
  │
  ├── Parse Usage
  ├── Save Metadata
  │
  ▼
Client
```

---

# 23. Streaming

Gateway 必须支持 Streaming。

不得：

```text
先完整读取响应
再返回客户端
```

应该：

```text
DeepSeek Streaming
        │
        ├────→ Client
        │
        └────→ Usage parser
```

保持 Streaming latency 尽可能接近直接调用 DeepSeek。

---

# 24. Local Gateway 开关

Settings：

```text
Local Usage Gateway
────────────────────

[ ] Enable Gateway

Port
43123

Status
● Running

Endpoint
http://127.0.0.1:43123

[Copy Endpoint]
```

关闭以后：

```text
Gateway completely stops listening.
```

---

# 25. 数据可信度

定义：

```text
UsageSource
```

枚举：

```swift
enum UsageSource {
    case officialCSV
    case localGateway
    case balanceSnapshot
}
```

可信度：

```text
Official CSV
    ↓
最高

Local Gateway
    ↓
实时估算

Balance Snapshot
    ↓
只用于余额
```

---

# 26. 官方数据覆盖本地估算

例如：

Gateway：

```text
2026-08-16
¥3.72
```

后来导入官方 CSV：

```text
2026-08-16
¥3.69
```

最终：

```text
Official CSV = ¥3.69
```

Dashboard 显示：

```text
¥3.69 ✓
```

而不是：

```text
¥7.41
```

---

# 27. Verification State

推荐：

```swift
enum VerificationState {
    case estimated
    case official
}
```

历史 UI 可以显示：

```text
8/16  ¥3.69  ✓
8/15  ¥2.18  ✓
8/14  ¥1.73
```

其中：

```text
✓ = Official
无图标 = Estimated
```

---

# 28. Pricing Engine

如果 Gateway 需要计算实时金额，禁止把价格写死在业务代码中。

创建：

```text
PricingEngine
```

根据：

```text
model
timestamp
cache hit
cache miss
output
pricing rule
```

计算。

---

# 29. PriceRule

数据库：

```text
price_rules
```

建议字段：

```text
id
provider
model
effective_from
effective_to
period
cache_hit_price
cache_miss_price
output_price
currency
```

支持未来价格变化。

---

# 30. PricingEngine 规则版本

例如：

```text
Rule v1
2026-01-01 → 2026-08-16

Rule v2
2026-08-17 → ...
```

历史消费必须按照：

```text
request.timestamp
```

匹配对应规则。

不能使用：

```text
当前价格
```

重新计算所有历史调用。

---

# 31. UI 总体结构

```text
MenuBarExtra
     │
     ▼
Quick Panel
     │
     ▼
Floating Dashboard
     │
     ├── Mini
     ├── Full
     │
     ▼
History Detail
```

---

# 32. Menu Bar

菜单栏图标：

```text
API Meter icon
```

点击打开 Quick Panel。

---

# 33. Quick Panel

目标：

> 3 秒内知道现在 API 消费情况。

建议布局：

```text
┌──────────────────────────┐
│ API Meter            ↻   │
│                          │
│ Balance                  │
│ ¥32.34                   │
│                          │
│ Today          ¥1.42     │
│ ▁▂▁▃▂▅▇                  │
│                          │
│ Last 7 Days    ¥7.83     │
│                          │
│ Coding         ¥0.91     │
│ Research       ¥0.34     │
│ Test           ¥0.17     │
│                          │
│ [ Open Dashboard ]       │
└──────────────────────────┘
```

---

# 34. Quick Panel 信息

显示：

```text
Current Balance
Today Usage
7-Day Mini Trend
Top API Keys
Last Refresh
Refresh Button
Open Dashboard
```

不应该塞入：

```text
复杂配置
完整历史表格
大量按钮
```

---

# 35. 完整 Dashboard

参考 DeepSeek Usage 页面信息层级，但视觉使用原生 macOS 风格。

建议：

```text
┌──────────────────────────────────────────────┐
│ API Meter            Updated 23:32      ⚙︎  │
│                                              │
│ ┌────────────┐ ┌────────────┐               │
│ │ Balance    │ │ Today      │               │
│ │ ¥32.34     │ │ ¥1.42      │               │
│ └────────────┘ └────────────┘               │
│                                              │
│ 7D   30D   Month   Custom      API Key ▾    │
│                                              │
│ ┌────────┐ ┌────────┐ ┌────────────┐        │
│ │ Cost   │ │Request │ │ Tokens     │        │
│ │¥13.71  │ │906     │ │114.8M      │        │
│ └────────┘ └────────┘ └────────────┘        │
│                                              │
│ Usage Trend                                  │
│                                              │
│  4 ┤                 ▇                       │
│  3 ┤       ▆         █                       │
│  2 ┤   ▅   █   ▅     █                       │
│  1 ┤ ▂ █   █ ▂ █ ▂   █ ▅                     │
│    └────────────────────────                  │
│                                              │
│ Daily Usage                                  │
│                                              │
│ 8/16 ¥1.42   96 req     8.4M Tokens         │
│ 8/15 ¥3.81  218 req    21.7M Tokens         │
└──────────────────────────────────────────────┘
```

---

# 36. 主指标

Dashboard 顶部优先级：

### 第一优先级

```text
Current Balance
Today Cost
```

### 第二优先级

```text
Selected Period Cost
Requests
Tokens
```

### 第三优先级

```text
API Key Breakdown
Trend
Daily History
```

---

# 37. 时间筛选

必须支持：

```text
7 Days
30 Days
This Month
Custom
```

默认：

```text
30 Days
```

Custom 使用 macOS 原生日期选择器。

---

# 38. API Key 筛选

支持多选。

例如：

```text
API Keys

[x] Coding
[x] Research
[ ] Test
[x] Python
```

图表、金额、请求数、Token：

全部根据当前选中的 Key 重新聚合。

必须支持：

```text
Select All
Clear
```

---

# 39. API Key 显示名称

Settings：

```text
API Keys

Coding
••••72AF
[Rename]

Research
••••931B
[Rename]
```

Alias 只修改本地 UI。

不得修改 DeepSeek 服务器上的 Key。

---

# 40. 消费趋势图

使用：

```text
Swift Charts
```

优先使用：

```text
BarMark
```

代表每日消费。

Hover 时显示：

```text
Aug 16

Cost
¥3.69

Requests
218

Tokens
21.7M
```

---

# 41. 每日消费统计

这是核心功能。

必须支持：

```text
Today
Yesterday
Historical Daily Usage
```

每一日显示：

```text
Date
Cost
Requests
Tokens
Verification
```

---

# 42. 点击某一天

进入详情。

例如：

```text
August 16

Total Cost
¥3.81

Requests
218

Tokens
21,738,294


API Keys
────────────────

Coding
¥2.14

Research
¥1.21

Test
¥0.46
```

V1 不要求模型维度展开。

---

# 43. 今日消费

Dashboard 中始终固定提供：

```text
Today
```

今日金额优先数据来源：

```text
Official CSV
    ↓
Local Gateway
```

如果今天没有 Official 数据：

```text
显示 Estimated
```

---

# 44. Mini Floating Panel

用户已经明确 Mini 模式只需要：

```text
余额 + 今日消费
```

设计：

```text
╭────────────────────────────╮
│ ¥32.34      Today ¥1.42    │
╰────────────────────────────╯
```

---

# 45. Mini Panel 行为

支持：

```text
Drag
Pin
Expand
Hide
Refresh
```

右键菜单：

```text
Open Dashboard
Pin / Unpin
Refresh
Settings
Quit
```

---

# 46. Floating Dashboard

完整 Dashboard 可以：

```text
Pin
Unpin
Mini
Restore
Close
```

---

# 47. Pin

使用：

```text
NSPanel
```

推荐行为：

```text
Pin OFF
→ normal window level

Pin ON
→ NSWindow.Level.floating
```

---

# 48. 窗口状态保存

必须记录：

```text
Window Position
Window Size
Pin State
Mini / Full
Last Display
```

下次启动自动恢复。

---

# 49. Global Shortcut

支持用户设置全局快捷键。

默认可以考虑：

```text
⌥ Space
```

但如果存在冲突，允许修改。

行为：

```text
Shortcut
   ↓
Show / Hide Dashboard
```

---

# 50. Login at Startup

支持：

```text
Launch at Login
```

默认建议：

```text
ON
```

使用：

```text
SMAppService
```

---

# 51. Dock Icon

默认：

```text
Hidden
```

Settings 提供：

```text
[ ] Show Dock Icon
```

切换后立即更新应用 activation policy。

---

# 52. Balance Alert

用户可以设置：

```text
Balance Alert Threshold
```

例如：

```text
¥5
¥10
¥20
Custom
```

默认：

```text
¥10
```

---

# 53. Notification

当：

```text
balance < threshold
```

发送：

```text
API Meter

DeepSeek balance is low.

Remaining:
¥8.42
```

使用：

```text
UserNotifications
```

---

# 54. 防止提醒轰炸

同一余额状态不能每次刷新都通知。

需要保存：

```text
lastAlertState
```

例如：

第一次：

```text
¥9.80
→ Alert
```

随后：

```text
¥9.60
¥9.20
¥8.80
```

不重复提醒。

充值超过阈值：

```text
¥30
```

以后再次跌破：

```text
¥9
```

才重新提醒。

---

# 55. 刷新策略

采用自适应刷新。

## Dashboard 打开

```text
立即刷新
```

## Floating Panel 可见

```text
每 5 分钟
```

## 仅菜单栏后台

```text
每 15 分钟
```

## Mac Sleep

```text
停止
```

## Wake

```text
立即刷新
```

用户也可以：

```text
Manual Refresh
```

---

# 56. Settings

Settings 至少包含：

```text
General
DeepSeek
API Keys
Usage
Notifications
Gateway
Appearance
Data
About
```

---

# 57. General

包含：

```text
Launch at Login
Show Dock Icon
Global Shortcut
Open Dashboard at Launch
Restore Window State
```

---

# 58. DeepSeek

包含：

```text
API Key
Connection Status
Test Connection
Current Balance
Last Sync
```

API Key 输入完成后：

```text
Save to Keychain
```

UI 之后只显示：

```text
••••••••72AF
```

---

# 59. Usage

包含：

```text
History Retention

30 Days
90 Days
1 Year
Forever
```

默认：

```text
Forever
```

---

# 60. Data

包含：

```text
Import DeepSeek Usage
Export Local Data
Database Size
Imported Months
Clear Local Usage
```

清空数据必须二次确认。

---

# 61. CSV Export

API Meter 自己的数据也支持导出。

至少支持：

```text
CSV
```

字段建议：

```text
date
api_key
cost
requests
tokens
source
verification
```

---

# 62. Appearance

总体风格：

> DeepSeek 的信息架构 + 原生 macOS 视觉。

不要简单复制网页 CSS。

---

# 63. macOS 15

使用：

```text
SwiftUI Material
RoundedRectangle
SF Symbols
Native Typography
System Spacing
```

---

# 64. macOS 26

针对 macOS 26 增加：

```text
Liquid Glass
```

但是 Glass 主要应用：

```text
Toolbar
Filter
Floating Control
Mini Panel
Button
Popover
```

不要把所有数据卡片全部玻璃化。

---

# 65. Dark / Light Mode

默认：

```text
Follow System
```

设置提供：

```text
System
Light
Dark
```

---

# 66. 推荐技术栈

```text
Language
Swift 6

UI
SwiftUI

Window
AppKit / NSPanel

Charts
Swift Charts

Networking
URLSession

Database
SQLite + GRDB

Secrets
Keychain

Gateway
SwiftNIO

Notifications
UserNotifications

Login Item
SMAppService

Global Shortcut
KeyboardShortcuts
```

---

# 67. 推荐依赖

尽量控制外部依赖。

第一版推荐最多：

```text
GRDB
KeyboardShortcuts
SwiftNIO
```

其余优先使用 Apple Framework。

---

# 68. 软件架构

推荐：

```text
UI
 ↓
ViewModel
 ↓
Repository
 ↓
Services
 ↓
Storage / Network
```

不要：

```text
SwiftUI View
直接调用 URLSession
直接读 SQLite
```

---

# 69. Provider 层

即使当前只支持 DeepSeek，也应建立抽象。

例如：

```swift
protocol BalanceProvider {
    func fetchBalance() async throws -> Balance
}
```

以及：

```swift
protocol UsageProvider {
    func fetchUsage() async throws -> [UsageRecord]
}
```

这样业务逻辑不绑定 UI。

---

# 70. 项目目录结构

推荐：

```text
APIMeter/
│
├── App/
│   ├── APIMeterApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
│
├── Models/
│   ├── Balance.swift
│   ├── APIKey.swift
│   ├── UsageRecord.swift
│   ├── DailyUsage.swift
│   ├── PriceRule.swift
│   └── ImportBatch.swift
│
├── UI/
│   │
│   ├── MenuBar/
│   │   ├── MenuBarView.swift
│   │   └── MiniTrendChart.swift
│   │
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   ├── MetricCard.swift
│   │   ├── UsageChart.swift
│   │   ├── DateRangePicker.swift
│   │   ├── APIKeyFilter.swift
│   │   └── DailyUsageList.swift
│   │
│   ├── History/
│   │   └── DailyDetailView.swift
│   │
│   ├── MiniPanel/
│   │   └── MiniPanelView.swift
│   │
│   └── Settings/
│       ├── GeneralSettingsView.swift
│       ├── DeepSeekSettingsView.swift
│       ├── UsageSettingsView.swift
│       ├── NotificationSettingsView.swift
│       ├── GatewaySettingsView.swift
│       └── DataSettingsView.swift
│
├── Window/
│   ├── FloatingPanel.swift
│   ├── FloatingPanelController.swift
│   └── WindowStateManager.swift
│
├── DeepSeek/
│   ├── DeepSeekClient.swift
│   ├── BalanceProvider.swift
│   └── DeepSeekModels.swift
│
├── Import/
│   ├── UsageImportService.swift
│   ├── ZIPExtractor.swift
│   ├── CSVParser.swift
│   ├── CSVSchemaDetector.swift
│   └── ImportDeduplicator.swift
│
├── Usage/
│   ├── UsageRepository.swift
│   ├── UsageAggregator.swift
│   ├── UsageReconciler.swift
│   └── PricingEngine.swift
│
├── Gateway/
│   ├── GatewayServer.swift
│   ├── RequestForwarder.swift
│   ├── OpenAIAdapter.swift
│   ├── StreamingProxy.swift
│   └── UsageCollector.swift
│
├── Database/
│   ├── DatabaseManager.swift
│   ├── Schema.swift
│   └── Migrations/
│
├── Security/
│   ├── KeychainService.swift
│   └── KeyFingerprint.swift
│
├── Notifications/
│   └── BalanceAlertService.swift
│
├── Settings/
│   └── AppSettings.swift
│
└── Utilities/
    ├── Logger.swift
    ├── CurrencyFormatter.swift
    └── TokenFormatter.swift
```

---

# 71. 数据库

使用：

```text
SQLite
+
GRDB
```

---

# 72. balance_snapshots

```sql
CREATE TABLE balance_snapshots (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    total REAL NOT NULL,
    granted REAL,
    topped_up REAL,
    currency TEXT NOT NULL
);
```

---

# 73. api_keys

```sql
CREATE TABLE api_keys (
    id INTEGER PRIMARY KEY,
    fingerprint TEXT UNIQUE NOT NULL,
    display_name TEXT,
    official_name TEXT,
    enabled BOOLEAN NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL
);
```

---

# 74. usage_records

概念 Schema：

```sql
CREATE TABLE usage_records (
    id INTEGER PRIMARY KEY,

    timestamp DATETIME,
    day DATE NOT NULL,

    api_key_id INTEGER,

    model TEXT,

    request_count INTEGER,

    cache_hit_tokens INTEGER,
    cache_miss_tokens INTEGER,
    input_tokens INTEGER,
    output_tokens INTEGER,
    total_tokens INTEGER,

    amount REAL,
    currency TEXT,

    source TEXT NOT NULL,
    verification_state TEXT NOT NULL,

    source_row_hash TEXT UNIQUE,

    created_at DATETIME NOT NULL
);
```

---

# 75. import_batches

```sql
CREATE TABLE import_batches (
    id INTEGER PRIMARY KEY,
    file_hash TEXT UNIQUE NOT NULL,
    filename TEXT,
    month TEXT,
    imported_at DATETIME NOT NULL,
    row_count INTEGER
);
```

---

# 76. price_rules

```sql
CREATE TABLE price_rules (
    id INTEGER PRIMARY KEY,

    model TEXT NOT NULL,

    effective_from DATETIME NOT NULL,
    effective_to DATETIME,

    period TEXT,

    cache_hit_price REAL,
    cache_miss_price REAL,
    output_price REAL,

    currency TEXT NOT NULL
);
```

---

# 77. 每日聚合

不需要单独保存 DailyUsage。

使用 SQL：

```sql
SELECT
    day,
    SUM(amount),
    SUM(request_count),
    SUM(total_tokens)
FROM usage_records
GROUP BY day;
```

---

# 78. UsageRepository

UI 不应该知道数据来自：

```text
CSV
Gateway
SQLite
```

统一：

```swift
UsageRepository
```

API 示例：

```swift
func usage(
    from: Date,
    to: Date,
    apiKeys: Set<APIKeyID>
) async throws -> UsageSummary
```

---

# 79. UsageSummary

建议：

```swift
struct UsageSummary {
    let cost: Decimal
    let requests: Int
    let tokens: Int64
    let daily: [DailyUsage]
    let byAPIKey: [APIKeyUsage]
}
```

---

# 80. Error Handling

所有错误必须分级。

例如：

```text
Network Error
Authentication Error
CSV Parse Error
Unsupported CSV Schema
Database Error
Gateway Error
Pricing Error
```

---

# 81. Balance API 失败

如果余额请求失败：

不要把余额改成：

```text
¥0
```

而是：

```text
¥32.34

Last updated
23:02

⚠ Unable to refresh
```

保留上一次成功数据。

---

# 82. CSV Schema 不支持

显示：

```text
This DeepSeek usage file uses an unsupported format.

The file was not imported.

[View Details]
```

绝对不能部分解析后静默产生错误账单。

---

# 83. Gateway 失败

如果 Gateway 无法启动：

```text
Gateway unavailable

Port 43123 is already in use.
```

允许：

```text
Change Port
Retry
Disable Gateway
```

不影响：

```text
Balance
Historical CSV
Dashboard
```

正常使用。

---

# 84. 数据保留清理

用户设置：

```text
30 Days
90 Days
1 Year
Forever
```

只影响：

```text
本地 historical data
```

执行清理前：

```text
不要删除最近导入的 Import Metadata
```

以免用户重新导入历史文件导致重复。

---

# 85. 隐私原则

必须建立：

```text
Privacy.md
```

明确说明：

API Meter：

```text
does not upload usage data
does not collect prompts
does not collect completions
does not collect browser cookies
does not collect passwords
```

所有数据：

```text
remain on user's Mac
```

---

# 86. 日志

日志禁止输出：

```text
API Key
Authorization Header
Prompt
Completion
Cookie
Raw Request Body
```

允许：

```text
request duration
status code
model
token count
error type
```

API Key 只能记录：

```text
fingerprint prefix
```

例如：

```text
key=A7E9****
```

---

# 87. 第一阶段：Phase A — 技术验证

这是最优先阶段。

**不要先做完整 UI。**

必须验证以下四件事。

---

# 88. Phase A.1 Balance API

制作最简单测试程序：

```text
API Key
  ↓
Balance API
  ↓
Print Balance
```

验收：

```text
能够正确显示当前真实余额。
```

---

# 89. Phase A.2 DeepSeek CSV

从真实账户导出：

```text
一个月份 Usage
```

完成：

```text
字段分析
Schema 文档
API Key 字段分析
时间粒度分析
Token 字段分析
金额字段分析
```

输出：

```text
docs/deepseek-csv-schema.md
```

这是整个项目最重要的验证任务之一。

---

# 90. Phase A.3 Gateway

实现：

```text
localhost → DeepSeek
```

普通非 Streaming 请求。

验收：

```text
Client response 与直接调用 DeepSeek 一致。
```

---

# 91. Phase A.4 Streaming Gateway

实现 Streaming。

验收：

```text
Streaming response 正常
首 Token 延迟没有明显增加
Usage 能正确记录
```

---

# 92. Phase A Gate

只有以下全部通过：

```text
Balance ✓
CSV ✓
Gateway ✓
Streaming ✓
```

才进入完整 UI 开发。

如果 CSV 无法提供足够历史数据：

调整：

```text
Local Gateway
```

优先级。

---

# 93. Phase B — MVP

实现：

```text
MenuBarExtra

Current Balance

Today Usage

7 Day
30 Day
This Month

Daily History

Swift Charts

API Key Filter

CSV Import

SQLite

Keychain
```

Gateway 此阶段可以是：

```text
Experimental
```

---

# 94. Phase B 验收

用户必须能够：

1. 启动 App
2. 输入 DeepSeek API Key
3. 成功获得余额
4. 导入官方 Usage CSV
5. 查看最近 30 天消费
6. 查看每日消费
7. 点击某一天查看详情
8. 按 API Key 筛选
9. 关闭 App
10. 再打开后数据仍存在

---

# 95. Phase C — 完整 V1

增加：

```text
Floating NSPanel

Pin

Mini Mode

Global Shortcut

Launch at Login

Dock Icon Setting

Balance Notification

History Retention

CSV Export

Settings

Dark / Light

macOS 26 Glass

Window Restore
```

Gateway 从 Experimental 升级为：

```text
Stable Optional Feature
```

---

# 96. Phase C 验收

必须实现：

### Window

```text
Pin ✓
Mini ✓
Restore ✓
Shortcut ✓
```

### Background

```text
Launch at Login ✓
Adaptive Refresh ✓
Sleep / Wake ✓
```

### Security

```text
Keychain ✓
No plaintext key ✓
Safe logs ✓
```

### Data

```text
CSV Import ✓
CSV Deduplicate ✓
CSV Export ✓
Retention ✓
```

### Alert

```text
Threshold ✓
No repeated spam ✓
```

---

# 97. Phase C+ — 开源准备

增加：

```text
README.md
ARCHITECTURE.md
PRIVACY.md
CONTRIBUTING.md
LICENSE

GitHub Actions

Unit Tests

Integration Tests

CSV Fixtures

Database Migration Tests

Gateway Tests

Pricing Tests
```

---

# 98. 自动更新

如果未来需要独立发行 DMG：

可以考虑：

```text
Sparkle 2
```

但不属于 MVP。

---

# 99. Unit Tests

至少测试：

```text
Balance Parser

CSV Parser

CSV Schema Detector

CSV Deduplicator

Usage Aggregator

Usage Reconciliation

Pricing Engine

Date Range

API Key Filtering

History Retention
```

---

# 100. Gateway Tests

至少测试：

```text
POST request
Streaming
Authentication header forwarding
Request cancellation
Server error
Timeout
Connection interruption
Large response
Multiple parallel requests
```

---

# 101. Security Tests

确保日志中不存在：

```text
sk-
Authorization:
Cookie:
prompt
completion
```

测试：

```text
Keychain write
Keychain read
Keychain delete
```

---

# 102. Database Migration

从第一版开始设置：

```text
schemaVersion
```

例如：

```text
v1
v2
v3
```

禁止未来直接修改 production schema 而不做 migration。

---

# 103. 性能目标

菜单栏打开：

```text
< 150 ms
```

历史查询：

```text
30 day < 100 ms
```

Dashboard：

```text
保持 60 FPS
```

Gateway 本地额外 latency：

目标：

```text
尽可能 < 5 ms
```

不计 DeepSeek 网络 latency。

---

# 104. Dashboard 刷新原则

UI 首先显示：

```text
Local Database
```

然后异步：

```text
Refresh Balance
```

不要每次打开 Dashboard 都等待网络完成后才显示 UI。

---

# 105. Currency

所有金额内部建议使用：

```text
Decimal
```

不要使用：

```text
Double
```

做财务金额累计。

---

# 106. Tokens

Token 使用：

```text
Int64
```

UI 自动格式化：

```text
928
8.4K
1.2M
114.8M
```

完整值 Hover 显示：

```text
114,893,001
```

---

# 107. 时间

数据库统一保存：

```text
UTC
```

每日统计按照：

```text
User Local Timezone
```

生成 day bucket。

Timezone 改变后，历史数据不能损坏。

---

# 108. Accessibility

尽量使用：

```text
Native Controls
SF Symbols
Semantic Labels
```

Dashboard 应支持：

```text
VoiceOver
Keyboard Navigation
```

---

# 109. Empty State

无历史数据时：

```text
No Usage Data Yet

Import your DeepSeek usage export
or enable Local Usage Gateway.

[Import Usage]
```

---

# 110. First Launch

建议 onboarding：

### Step 1

```text
Welcome to API Meter
```

### Step 2

```text
Add DeepSeek API Key
```

### Step 3

```text
Import Existing Usage
```

可以：

```text
Skip
```

### Step 4

```text
Enable Launch at Login?
```

结束。

---

# 111. 不做网页抓取

这是固定技术决策。

禁止实现：

```text
WKWebView 登录 DeepSeek
读取 Usage 页面 DOM
调用网页内部隐藏接口
复制浏览器 Session
抓取 Safari Cookie
抓取 Chrome Cookie
```

如果未来 DeepSeek 发布正式 Usage API：

可以新增：

```text
OfficialUsageProvider
```

替代部分 CSV 流程。

---

# 112. 数据策略总结

最终：

```text
Current Balance
      ↓
Official Balance API


Historical Billing
      ↓
Official Usage Export


Realtime Local Usage
      ↓
Optional Local Gateway


Source of Truth
      ↓
Official CSV
```

---

# 113. 产品核心页面关系

```text
                    Menu Bar
                       │
                       ▼
                  Quick Panel
                       │
              Open Dashboard
                       │
                       ▼
              Floating Dashboard
                │             │
                │             │
             Mini          History
                                │
                                ▼
                         Daily Detail


Settings
  │
  ├── General
  ├── DeepSeek
  ├── API Keys
  ├── Usage
  ├── Notifications
  ├── Gateway
  ├── Appearance
  └── Data
```

---

# 114. 推荐开发顺序

Agent 必须按以下顺序执行。

## Step 1

创建 Swift macOS 项目。

不要先花时间做最终视觉。

---

## Step 2

实现：

```text
KeychainService
DeepSeekClient
BalanceProvider
```

验证余额 API。

---

## Step 3

获取用户真实 DeepSeek Usage Export。

分析 CSV。

输出：

```text
docs/deepseek-csv-schema.md
```

---

## Step 4

实现：

```text
GRDB
Database schema
Migration v1
```

---

## Step 5

实现：

```text
CSV Importer
Deduplication
UsageRepository
UsageAggregator
```

---

## Step 6

使用测试数据实现：

```text
Dashboard
Swift Charts
Daily History
API Key Filter
```

---

## Step 7

实现：

```text
MenuBarExtra
```

---

## Step 8

实现：

```text
NSPanel
Floating Dashboard
Mini Mode
Pin
```

---

## Step 9

实现：

```text
Window Restore
Global Shortcut
Launch at Login
Dock Setting
```

---

## Step 10

实现：

```text
Balance Alert
```

---

## Step 11

实现：

```text
CSV Export
Retention
Settings
```

---

## Step 12

完成基础版后再开发：

```text
Local Gateway
```

不要让 Gateway 阻塞基础 Dashboard。

---

# 115. Local Gateway 开发顺序

Gateway 本身按照：

```text
HTTP Forwarding
      ↓
Non Streaming
      ↓
Streaming
      ↓
Usage Parsing
      ↓
SQLite
      ↓
Pricing Engine
      ↓
API Key Mapping
      ↓
Error Handling
```

开发。

---

# 116. Agent 不应擅自改变的核心决策

以下属于已经确定的需求：

```text
macOS 15+

Menu Bar

Floating Dashboard

Mini Mode

Mini = Balance + Today Cost

Pin

Global Shortcut

Launch at Login

Dock icon optional

Multiple API Keys

Multi-select API Key filtering

Daily historical usage

7D / 30D / Month / Custom

Single DeepSeek Account

Balance threshold configurable

History retention configurable

CSV Import

CSV Export

Local-only data

Keychain

No browser cookie reading

No Usage webpage scraping
```

如无阻塞性技术问题，不要修改。

---

# 117. Agent 遇到未知情况时的处理方式

如果发现：

```text
DeepSeek CSV Schema
```

与预期不同：

不要自行猜测字段。

应该：

1. 保存真实样例
2. 记录实际 Schema
3. 更新 CSV Parser
4. 更新 `deepseek-csv-schema.md`
5. 保持数据库内部标准模型不变

---

# 118. 内部标准 Usage Model

无论外部 CSV 怎么变化，最终统一为：

```text
UsageRecord

date
timestamp
apiKey
model

requests

inputTokens
outputTokens
cacheHitTokens
cacheMissTokens
totalTokens

amount
currency

source
verification
```

不存在的字段：

```text
NULL
```

不要伪造数据。

---

# 119. 数据不可获得时的 UI 原则

例如 CSV 没有：

```text
Request Count
```

不要显示：

```text
0 Requests
```

应该显示：

```text
—
```

Tooltip：

```text
Not provided by this data source.
```

---

# 120. 最终 MVP Definition of Done

只有同时满足以下条件，才能认为 MVP 完成：

- [ ] App 可以在 macOS 15+ 启动
- [ ] 菜单栏正常存在
- [ ] DeepSeek API Key 安全保存到 Keychain
- [ ] 可以获取当前余额
- [ ] 可以导入真实 DeepSeek Usage Export
- [ ] 重复导入不会重复计费
- [ ] 可以显示今日消费
- [ ] 可以显示 7 天消费
- [ ] 可以显示 30 天消费
- [ ] 可以显示本月消费
- [ ] 可以选择自定义时间范围
- [ ] 可以查看历史每日消费
- [ ] 可以点击某一天查看详情
- [ ] 可以按 API Key 多选筛选
- [ ] 可以显示请求数
- [ ] 可以显示 Tokens
- [ ] 可以显示消费趋势图
- [ ] 数据在重启后仍存在
- [ ] 网络失败不会丢失历史数据
- [ ] 日志不包含 API Key
- [ ] 不读取浏览器 Cookie
- [ ] 不自动抓取 DeepSeek Usage 网页

---

# 121. 最终 V1 Definition of Done

在 MVP 基础上：

- [ ] 完整 Floating Dashboard
- [ ] NSPanel Pin
- [ ] Mini Mode
- [ ] Mini 显示余额 + 今日消费
- [ ] 全局快捷键
- [ ] 登录系统后自动启动
- [ ] Dock 图标可以配置
- [ ] 记忆窗口位置
- [ ] 记忆窗口大小
- [ ] 记忆 Pin 状态
- [ ] 记忆 Mini 状态
- [ ] 自适应刷新
- [ ] Sleep 时暂停刷新
- [ ] Wake 后刷新
- [ ] 余额阈值提醒
- [ ] 提醒不会重复轰炸
- [ ] 历史保留时间可配置
- [ ] CSV Export
- [ ] 完整 Settings
- [ ] Dark / Light / System
- [ ] macOS 26 视觉增强
- [ ] 数据库 Migration
- [ ] 基础 Unit Tests
- [ ] Privacy 文档

---

# 122. 最重要的技术风险

按优先级排列：

## Risk 1

```text
DeepSeek 官方 CSV Schema
```

未知程度最高。

必须首先验证。

---

## Risk 2

```text
CSV 是否提供每日粒度
```

如果官方只有月度聚合，则历史每日消费无法完全依赖官方 CSV。

此时：

```text
Local Gateway
```

重要性上升。

---

## Risk 3

Streaming Gateway。

需要确保：

```text
Streaming
Cancellation
Timeout
Usage extraction
```

稳定。

---

## Risk 4

实时 Pricing。

DeepSeek 价格可能变化。

因此必须使用：

```text
versioned PricingEngine
```

不能把价格散落在业务代码。

---

# 123. 最终架构

```text
                   ┌──────────────────────┐
                   │      API Meter       │
                   │ SwiftUI + AppKit     │
                   └──────────┬───────────┘
                              │
                       UsageRepository
                              │
                 ┌────────────┴────────────┐
                 │                         │
                 ▼                         ▼
              SQLite                    Keychain
                 │
       ┌─────────┼───────────┐
       │         │           │
       ▼         ▼           ▼
   Balance      CSV        Gateway
     API       Import      localhost
       │         │           │
       │         │           ▼
       │         │       DeepSeek API
       │         │           ▲
       └─────────┴───────────┘
```

---

# 124. 最终产品定义

API Meter 不是简单的 DeepSeek 官网缩小版。

它应该成为：

> **一个原生 macOS API 消费监控工具，以 DeepSeek 官方余额和官方账单数据作为可信基础，在本机组织长期历史消费，并通过可选的 Local Gateway 提供实时 Usage 统计。**

核心优势：

```text
比网页更快查看

比网页更适合常驻

支持每日历史

支持长期本地保存

支持多 API Key

支持桌面悬浮

支持 Mini Mode

支持快捷键

支持余额提醒

不依赖网页抓取

不上传用户数据
```

---

# 125. 开发 Agent 的第一项任务

不要立即开始制作最终 Dashboard。

首先完成：

```text
TECHNICAL VALIDATION
```

具体任务：

1. 初始化原生 macOS Swift 项目。
2. 实现 Keychain。
3. 实现 DeepSeek Balance API 测试。
4. 要求提供一个真实 DeepSeek Usage Export 样例。
5. 分析 ZIP / CSV Schema。
6. 输出 `docs/deepseek-csv-schema.md`。
7. 根据真实 CSV 确认：
   - 是否有日期
   - 是否有 API Key 名称
   - 是否有请求次数
   - 是否有 Token
   - 是否有模型
   - 是否有金额
8. 建立 SQLite 标准数据模型。
9. 完成 CSV Import Proof of Concept。
10. 用真实 Usage 数据跑出第一张 30 天消费柱状图。

只有上述流程完成后，再进入完整 UI 开发。

---

# 126. 第一阶段完成时应向用户汇报

Agent 应明确汇报：

```text
Balance API:
PASS / FAIL

CSV Import:
PASS / FAIL

Daily Granularity:
YES / NO

API Key Granularity:
YES / NO

Request Count:
YES / NO

Token Data:
YES / NO

Model Data:
YES / NO

Historical Daily Dashboard:
SUPPORTED / PARTIAL

Local Gateway Necessity:
LOW / MEDIUM / HIGH
```

然后再正式进入产品开发。

---

# 127. 最终开发原则

如果需要在：

```text
功能数量
```

和：

```text
数据准确性
```

之间选择：

永远优先：

```text
数据准确性
```

如果需要在：

```text
网页自动化
```

和：

```text
官方数据 + 本地记录
```

之间选择：

永远优先：

```text
官方数据 + 本地记录
```

如果某个字段无法可靠获得：

```text
显示 Unknown
```

不要：

```text
Guess
```

项目首先应该是一个：

> **可信的 API Usage Dashboard。**

然后才是一个漂亮的 Dashboard。