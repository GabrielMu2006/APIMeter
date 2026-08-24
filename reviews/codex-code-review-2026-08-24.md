# API Meter 项目评价报告

## 评估元信息

| 项目 | 内容 |
|---|---|
| 评估模型 | OpenAI Codex（GPT-5 系列；运行环境未暴露更细的模型子版本） |
| 评估日期 | 2026-08-24 |
| 评估方式 | **仅静态代码审查**：通读 Swift 主工程、DeepSeekSync、测试源码、构建配置、CI、文档与 Git 状态；遵照用户要求，未运行应用，不采用测试或构建结果作为评价依据 |
| 评估对象版本 | 仓库 `main` 分支，HEAD `8b7cf63`；评估前工作区仅 `reviews/` 为未跟踪目录 |
| 评分量表 | 每维度 1–10 分，10 分为同类个人开源项目中的顶尖水平 |

> 说明：本报告供跨模型/跨框架横向对比使用，评分维度与 `reviews/` 中现有报告保持一致；权重与结论由本模型独立判断。

---

## 一、评分总表

| 维度 | 权重 | 得分 | 一句话理由 |
|---|---:|---:|---|
| 架构设计 | 15% | 8.0 | 分层与组合根清晰，但自动同步对象缺少生命周期所有者，架构意图未真正落地 |
| 代码质量 | 15% | 7.8 | 命名、类型与职责边界总体优秀；错误分类过宽、子进程协议松散等细节造成真实功能风险 |
| 数据正确性 | 20% | 8.8 | Decimal、覆盖语义、双重去重、对账与诚实降级很强；ZIP 多文件导入缺少事务性会留下不可恢复的半导入状态 |
| 测试覆盖 | 15% | 6.8 | 静态可见 68 个测试声明，核心纯逻辑覆盖扎实；自动同步、导入编排、ZIP、网络与 TypeScript 工具基本无覆盖 |
| 安全性 | 10% | 8.2 | API Key 与日志处理可靠；浏览器持久化 profile 的会话副本和 ZIP 解压资源上限仍有披露与防护缺口 |
| 文档质量 | 10% | 8.5 | 双语 README、架构文档、长规格与隐私声明完整；测试计数、同步现状和会话存储描述存在失真 |
| 工程化/CI/发布 | 10% | 6.0 | CI 覆盖 SwiftPM 与 Xcode，但无 TypeScript 检查、lint、发布流水线、公证与 hardened runtime |
| 可维护性 | 5% | 7.3 | 小文件、少依赖、清晰命名利于维护；双构建清单、471 行 Repository 与页面自动化会持续增加维护成本 |
| **加权总分** | **100%** | **7.8** | 核心数据工程优秀，但“每日自动同步”存在阻断级静态缺陷，当前更像高质量手动导入工具而非可靠自动化产品 |

---

## 二、项目概述

**API Meter** 是面向 macOS 15+ 的本地优先菜单栏应用，以 DeepSeek Balance API 提供实时余额，以官方 Usage Export 提供历史消费，并通过余额快照差值估算当天支出。仓库由四部分组成：

- **APIMeter/**：Swift 6、SwiftUI + AppKit、GRDB/SQLite 的主应用，共 69 个 Swift 源文件。
- **DeepSeekSync/**：TypeScript + Playwright CLI，通过独立 Chromium profile 登录 DeepSeek 平台、点击官方导出并下载 ZIP。
- **Tools/PhaseAValidator/**：SwiftPM 自检与数据验证 CLI。
- **Tests/**：静态统计为 66 个 Core 测试声明和 2 个 App 宿主测试声明，共 68 个。

应用层采用 UI → ViewModel → AppEnvironment → Repository/Service → SQLite/Keychain/API 的依赖方向；SwiftPM 只构建核心层，Xcode 工程额外构建 UI/App/Window 层并引入 KeyboardShortcuts。

## 三、主要优点

1. **核心数据正确性设计是项目最强的部分。** 金额使用 `Decimal` 并以 TEXT 持久化，Token 使用 `Int64`；官方累计导出按 `(day, model, api key)` 执行覆盖语义，而不是重复累加；文件 SHA256 与行哈希形成两级去重；账单总额与按 Key 派生成本不一致时会降级为 `estimated`。这些规则不仅写在规格中，也能在 Repository、Mapper、Aggregator 与测试源码之间互相对应。

2. **“不确定就不伪造精确值”的产品原则贯彻得很好。** 今日消费有“午夜前基线 → 当天首快照下界 → 官方导出”多级回退，陈旧基线会被拒绝，充值上升段不会被误计为负消费，缺失指标保留为 `nil` 而不是伪装成 0。这比单纯追求界面始终有数字更可信。

3. **安全基础扎实。** 原始 API Key 只进入 Keychain，请求使用 ephemeral `URLSession`，数据库仅保存 SHA256 指纹；日志集中经过 `sk-...` 脱敏，网络错误也刻意不记录 URL、Authorization 或响应体。静态审查未发现硬编码凭据。

4. **代码组织克制、可读。** 大部分文件只承担单一 UI 或领域角色，命名直接，Swift 6 严格并发已在 Xcode 配置中开启。第三方依赖仅 GRDB 与 KeyboardShortcuts，依赖面很小；全仓未发现 TODO/FIXME 堆积。

5. **文档体系明显高于普通个人项目。** 中英 README、ARCHITECTURE、PRIVACY、贡献指南、真实 CSV schema 分析和 3500 余行规格形成了较完整的知识链。规格中的条款号还被代码注释引用，便于追溯设计意图。

6. **桌面产品形态考虑较完整。** 菜单栏、浮动面板、Mini 模式、Pin、全局快捷键、窗口状态、余额告警、数据导入导出和深浅色外观都已有独立实现，而不是把所有逻辑堆在一个 SwiftUI View 中。

## 四、主要问题

1. **阻断级：`SyncScheduler` 没有强引用，自动同步对象很可能在启动方法结束后立即释放。** `AppDelegate` 只强持有 `RefreshCoordinator`，却把 `SyncScheduler` 创建为局部变量；`AppState.syncScheduler` 又被声明为 `weak`。定时器回调同样以 `[weak self]` 捕获，因此没有形成其他所有权。结果是 00:30 定时检查、设置页中的 scheduler 状态和后续同步都可能失效。位置：`AppDelegate.swift:5-27`、`AppState.swift:15-16`、`SyncScheduler.swift:37-43`。

2. **阻断级：自动导入把所有 `ImportError` 都当成成功。** `SyncScheduler.run()` 的注释只想把 `.duplicateFile` 视为同日重复成功，但实现捕获整个 `ImportError` 枚举，并无条件写入 `lastSyncDay`、标记 `ok: true`。因此 unsupported schema、空文件、ZIP 解压失败、文件过大、日期非法等都会被记录成“今天已成功”，当天不再重试，且用户看到的是 OK。位置：`SyncScheduler.swift:71-86`。

3. **高风险：Swift 与 TypeScript 的 JSON 错误协议不一致。** DeepSeekSync 成功 JSON 写到 stdout，失败 JSON 却通过 `console.error` 写到 stderr；Swift 只从 stdout 最后一行解析 `CLIOutput`，stderr 仅作为普通字符串错误展示。因此 `sessionExpired` 的结构化分支实际上难以到达，专门的过期通知也会失效。与此同时 Swift 不检查退出码，采用 500ms 轮询、进程结束后才读取两个 pipe，超时仅 `terminate()` 而无强制结束兜底，协议可靠性不足。位置：`SyncScheduler.swift:114-155`、`DeepSeekSync/src/index.ts:120-130`。

4. **高风险：多 CSV ZIP 导入不是原子的，失败后可能无法正常续传。** ZIP 内文件逐个调用 `importCSV`，每个文件会立即修改 usage、规则、Key 名称并记录 batch。如果第二个文件失败，第一个已提交；再次导入时，第一个文件被判重并直接抛错，循环无法继续到第二个文件。外层 ZIP 的 hash 也从未写入 batch。需要把整个 ZIP 的解析/校验与数据库写入放进一个事务，或让重复子文件跳过后继续。位置：`UsageImportService.swift:67-84`、`90-134`。

5. **ZIP 边界防护不足。** 100MB 限制只检查压缩包本身，解压后没有累计大小或单文件大小限制；临时目录没有 `defer` 清理。虽然 `ditto` 避免了自己实现解压器，但压缩炸弹或长期多次导入仍可能消耗大量磁盘。位置：`UsageImportService.swift:55-78`、`ZIPExtractor.swift:8-31`。

6. **自动化关键路径缺少直接测试。** 68 个测试声明主要覆盖 Decimal、聚合、Mapper、数据库、Keychain、设置与 `SyncSchedule` 纯函数；没有覆盖 `SyncScheduler` 生命周期、错误分类、CLI 输出协议、`UsageImportService` 的 ZIP 编排、`ZIPExtractor`、`DeepSeekClient` 的 HTTP 行为，也没有 DeepSeekSync 的 TypeScript 测试。现有两处阻断级问题恰好都位于这些盲区。

7. **会话“只在 Keychain”这一披露不完全准确。** `launchPersistentContext(PROFILE_DIR, storageState)` 会使用持久化 Chromium profile；注入的 cookie/localStorage 在运行期可能同步落盘到 `~/Library/Application Support/DeepSeekSync/browser-profile`。代码只在 `login` 前删除 profile，`sync`、`dump` 与 `logout` 后均不清理，但 README/PRIVACY 和源码注释声称会话只存在 Keychain。它不等同于读取用户主浏览器数据，但应如实披露并清理临时 profile。位置：`browser.ts:7-30`、`index.ts:18-23, 107-110`。

8. **登录成功标记正则写成了字符类。** `/[消费金额用量信息请求次数Usage]/` 的含义是“包含括号内任意一个字符”，不是匹配这些短语之一；在 Usage URL 上出现任意常见汉字或 `U/s/a/g/e` 就可能过早认定登录成功并保存无效会话。位置：`authenticator.ts:27-42`。

9. **发布工程仍停留在作者自用阶段。** Xcode 的 Debug/Release 均关闭 hardened runtime，README 明确说明 DMG 为 ad-hoc 签名且未公证；CI 没有 lint、TypeScript 编译/测试、制品构建与 release 自动化。SwiftPM 与 Xcode 分别维护依赖与源集合，`swift build` 也无法验证完整 App 层，存在长期漂移风险。

10. **若干一致性与 UX 小问题。** README/ARCHITECTURE 写 64 个测试，而源码中有 68 个测试声明；“Clear” API Key filter 会把集合清空，但空集合在查询层被解释为“不筛选”，所以 Clear 与 Select All 得到相同数据，只是勾选状态不同；UI 文案几乎全部硬编码英文，规格中的 Accessibility 目标也缺少系统性的 label/hint 覆盖；`UsageRepository.swift` 471 行同时承担 Key、usage、快照、批次、价格、估算、对账与 retention，已成为主要变更热点。

## 五、改进建议（按优先级）

1. **先修复 scheduler 所有权（P0）。** 让 `AppDelegate` 或 `AppState` 强持有 `SyncScheduler`，并增加一个生命周期测试：启动后 scheduler 与 timer 仍存在、到期只执行一次。没有这一步，其余同步可靠性优化都无法发挥作用。

2. **精确分类导入错误（P0）。** 只对 `case .duplicateFile` 写入成功状态；其余 `ImportError` 必须保留失败、允许当天重试并通知用户。建议把“是否可重试/是否算成功”建模为错误属性，避免 catch 范围再次扩大。

3. **定义稳定的 CLI 协议（P0/P1）。** JSON 模式下无论成功失败都只向 stdout 输出一条 JSON，日志全部走 stderr；Swift 检查退出码并解析完整结构。抽象 `ProcessRunner` 以注入测试，使用异步 termination handler，同时消费 stdout/stderr，并为超时提供 terminate/kill 两阶段兜底。

4. **让 ZIP 导入具备事务性和资源上限（P1）。** 先解析并验证全部 CSV，再用单个数据库事务提交；或者记录 ZIP batch 并允许已完成子文件跳过后继续。限制解压后的总字节数/单文件字节数，并在所有退出路径清理临时目录。

5. **把测试预算优先投入边界编排（P1）。** 首批补 SyncScheduler、UsageImportService 多文件失败恢复、ZIPExtractor、CLI JSON 成功/失败协议、HTTP 状态映射；DeepSeekSync 至少增加 browser helper、会话状态和错误输出的单元测试。核心数学测试已经足够扎实，新增价值主要在 I/O 边界。

6. **修正会话安全实现与披露（P1）。** sync/dump/logout 结束后清理 scratch profile，或改用非持久 context；PRIVACY 与 README 明确说明运行期临时 profile。登录标记改为短语 alternation，例如 `/消费金额|用量信息|请求次数|Usage/i`，并同时验证页面的关键控件。

7. **补齐发布链路（P2）。** 使用 Developer ID、开启 hardened runtime、完成 notarization；tag 驱动版本校验、构建、签名、公证和 DMG 发布。CI 同时增加 TypeScript 编译/测试、格式检查和 SwiftPM/Xcode 源清单一致性检查。

8. **收敛维护成本（P2）。** 将 `UsageRepository` 按存储职责拆分，保持一个薄门面；统一 Xcode/SwiftPM 的依赖来源；更新测试计数与实际功能状态；为 UI 引入 String Catalog，并补键盘与 VoiceOver 基础检查。

## 六、总体结论

API Meter 的核心数据层明显优于普通个人项目：模型精确、导入覆盖语义合理、去重和对账严谨、安全基础可靠、文档可追溯。它真正的问题集中在外围编排，而外围恰好承载了产品最重要的卖点之一——无人值守的每日同步。

从静态代码看，scheduler 生命周期缺失与 `ImportError` 全部算成功是两处必须在发布前修复的阻断问题；CLI 协议和 ZIP 事务性则决定自动同步修复后是否可靠。因此本报告给出 **7.8/10**：它已经是一款很扎实的本地数据仪表盘和手动导入工具，但尚不能把“自动同步”视为可信、可交付的能力。修完前三项并补上对应测试后，整体质量有望稳定进入 8.5 分以上。

---

*本报告由 OpenAI Codex 生成。评估结论仅来自静态代码、配置与文档审查；未运行应用，未引用测试或构建执行结果。除新增本评价文件外，未修改任何原有源码或配置。*
