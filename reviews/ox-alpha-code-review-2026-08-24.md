# API Meter 项目评价报告

## 评估元信息

| 项目 | 内容 |
|---|---|
| 评估模型 | **ox-alpha**（开发方未公开），经由 opencode CLI 运行 |
| 评估日期 | 2026-08-24 |
| 评估方式 | 静态代码审查 + **实测验证**：亲自通读核心源码（UsageRepository / SyncScheduler / DeepSeekClient / KeychainService / AppEnvironment 等）、通过只读子代理覆盖测试/CI/Xcode 工程/DeepSeekSync/文档/Git 状态；**实际执行了 `swift test`**（非推断） |
| 评估对象版本 | 仓库 `main` 分支，HEAD `8b7cf63`，工作区仅 `reviews/` 未跟踪 |
| 评分量表 | 每维度 1–10 分，10 分为同类个人开源项目中的顶尖水平 |

> 说明：本报告供跨模型/跨框架横向对比使用，评分维度与 kimi-code-review-2026-08-24.md 保持一致，权重由本模型独立设定并在总表中注明。

---

## 一、评分总表

| 维度 | 权重 | 得分 | 一句话理由 |
|---|---|---|---|
| 架构设计 | 15% | 8.5 | 分层清晰、组合根 DI 干净、domain 与存储模型分离；双构建系统是唯一明显扣分项 |
| 代码质量 | 15% | 8.5 | 小文件高内聚、零 TODO、注释引用 spec 条款可追溯；`UsageRepository` 七种职责偏重 |
| 数据正确性 | 20% | 9.5 | Decimal 金额、REPLACE 语义、双重去重、导入对账、多级诚实降级——全项目最突出的亮点 |
| 测试覆盖 | 15% | 7.0 | 核心库测试精准覆盖最易错逻辑且**实测全部通过**；但 ZIPExtractor、导入编排、SyncScheduler、网络层为零覆盖 |
| 安全性 | 10% | 9.0 | Keychain 存密钥、日志脱敏、ephemeral session 执行彻底；扣分点：签名弱 + DeepSeekSync 运行期存在明文 cookie 副本未披露 |
| 文档质量 | 10% | 8.5 | 双语 README 与代码逐项吻合、自曝缺陷的诚实度高；测试计数过时、会话存储表述略乐观 |
| 工程化/CI/发布 | 10% | 6.0 | CI 双轨跑测试可靠，但无 lint、无 release 流水线、ad-hoc 签名 + 无公证直接伤害用户体验 |
| 可维护性 | 5% | 7.5 | 结构易读、提交历史规范；双构建漂移与 spec 滞后是长期隐患 |
| **加权总分** | 100% | **8.2** | 数据层纪律性罕见的优质个人项目，短板集中在分发体验与自动化链路可靠性 |

---

## 二、项目概述

**API Meter** 是本地优先的 macOS 15+ 菜单栏应用（Swift 6 严格并发 / SwiftUI + AppKit / GRDB-SQLite），将 DeepSeek 官方余额 API 与 Usage 导出整合为常驻仪表盘。单仓多组件：

- **APIMeter/**（Swift 约 5500 行）：主应用，分层为 UI → ViewModel → AppEnvironment（组合根）→ Repository/Service → SQLite/Keychain/API。
- **DeepSeekSync/**（TypeScript + Playwright 约 400 行）：独立 CLI，驱动真实 Chromium 自动下载官方导出，会话存 macOS Keychain。
- **Tools/PhaseAValidator**：`apimeter` 验证 CLI（SPM executable）。
- **Tests/**：66 个 Swift Testing 核心测试 + 2 个 XCTest app 宿主回归。

依赖面克制：GRDB 7.x 与 KeyboardShortcuts 两个第三方库。

## 三、主要优点

1. **数据正确性工程达到商业产品水准**。金额全程 Decimal（TEXT 存储）；官方导入按 `(day, model, key)` REPLACE 语义防累计快照重复计数；文件级 SHA256 + 行级哈希双重去重；每次导入后用 Σ(price×amount) 与账单总额对账，超容差自动降级为 estimated；"今日消费"基于余额快照差值估算，带 24h 陈旧基线拒绝、充值识别忽略、无基线 partial 降级三级策略。"宁可 Unknown 不给错数"不是口号——每个回退分支都有对应测试（DatabaseTests 中余额推算 5 连测）。

2. **实测验证通过**。本模型实际运行 `swift test`：**66 个核心测试在 14 个套件中全部通过（0.043s）**，覆盖 PricingEngine、CSV 解析/Schema 检测、官方映射器、去重器、聚合器、数据库全链路（ephemeral SQLite）、Keychain、告警状态机、同步调度纯函数。测试写的是行为断言而非实现断言，质量高。

3. **安全红线执行干净**。密钥仅存 Keychain（指纹索引支持多密钥、幂等保存、`AfterFirstUnlockThisDeviceOnly` 本机不同步）；SQLite 只存 SHA256 指纹；网络客户端 ephemeral 且错误日志刻意不含 URL/key；审查未发现任何硬编码凭据。

4. **Git 仓库卫生极佳（实测）**。`git count-objects` 共 2.62 MiB 无 pack；196MB 的便携 Node runtime 与 node_modules 均正确嵌套忽略未被跟踪；`.gitignore` 覆盖密钥类文件与真实样例数据。

5. **文档诚实度罕见**。双语 README 与代码逐项吻合，主动披露自身缺陷（ad-hoc 签名需右键放行、重建后 Keychain 失效、充值会掩盖当日消费）；phase-a-report 含自我纠错的 Addendum。

## 四、主要问题

1. **分发签名弱（高优先级痛点）**。ad-hoc 签名 + hardened runtime 关闭 + 无公证：用户首次启动需右键放行；重建导致签名身份变化进而使 Keychain 访问失效（README 自认）。这不是边缘问题，而是直接落在每个新用户的第一接触点上。

2. **SyncScheduler 子进程链路脆弱且零测试（中危）**。这是全项目唯一无人值守的自动化路径，实现上四处隐患叠加：500ms 忙轮询代替 `terminationHandler`；不检查子进程退出码；假设"stdout 最后一行即 JSON"；超时 `terminate()` 后无 `kill()` 兜底；读 stdout 用 `readDataToEndOfFile` 在子进程大量输出时存在管道缓冲区阻塞的经典风险模式。当前因输出量小而侥幸可用。

3. **外围测试盲区（中危）**。ZIPExtractor（ditto 子进程解压）、UsageImportService 导入编排（ZIP 分发、大小限制分支）、SyncScheduler、DeepSeekClient 网络层（URLSession 部分）均零直接测试。核心计算有测试而边界编排没有，恰与故障高发区相反。

4. **双构建漂移的具体形态（中危）**。KeyboardShortcuts 仅存在于 Xcode 工程，Package.swift 排除 App/UI 层——意味着 `swift build` 从不能验证完整 app，新增依赖若只加一边会静默失同步。

5. **隐私披露缺口（低危）**。DeepSeekSync 会话主路径存 Keychain 是干净的，但 `browser.ts` 使用 `launchPersistentContext(PROFILE_DIR)`，sync 运行期间 Chromium 会把注入的 cookie 落盘到 `~/Library/Application Support/DeepSeekSync/browser-profile` 的明文副本（受用户账户保护，但 README"会话加密存入钥匙串"的说法字面上不完全成立，且仅 `login` 命令清理 profile）。另发现登录成功判定正则（authenticator.ts:34）是字符类而非短语匹配，任一单字命中即判成功，过于宽松。

6. **小瑕疵集合（低危）**。`reconcileDerivedCosts` 容差 0.000001 为硬编码魔数；README 写"64 unit tests"实际为 68（66 core + 2 app）；`reviews/` 目录未入库；CI 无 lint。

## 五、改进建议（按优先级）

1. **发布工程（收益最大）**：Developer ID + 开启 hardened runtime + 公证 + tag 触发的 DMG release workflow。一并根治 Gatekeeper 拦截与 Keychain 随构建失效两大用户可见痛点。

2. **加固并测试同步链路**：抽出命令运行器协议注入 SyncScheduler 使其可测；改用 `terminationHandler` + 退出码检查 + JSON 起止标记解析 + terminate 后 kill 兜底。补 ZIPExtractor 与导入管线的端到端集成测试。

3. **统一构建源**：引入 XcodeGen/Tuist 以单一清单生成 xcodeproj，或 CI 加双构建源清单一致性校验步骤。

4. **拆分 UsageRepository**（471 行七种职责）：按 APIKeyStore / BalanceSnapshotStore / PriceRuleStore / TodayEstimator 拆分，Repository 保留薄门面，各块独立可测。

5. **CI 增强**：SwiftLint/SwiftFormat + 依赖缓存；`reviews/` 目录入库。

6. **文档与披露修正**：更新测试计数至 68；README 披露 browser-profile 明文 cookie 副本及清理方式；DeepSeekSync 在每次 sync 结束后清理 profile。

7. **中期机会**：app UI 中文化（目前仅文档双语）；PriceRule 已预留 `provider` 字段，为多提供商（OpenAI/Anthropic 等）演进的架构空间已在。

## 六、总体结论

这是一个数据层纪律性罕见严格的个人项目：导入/去重/对账/估算的核心链路幂等且诚实，66 个核心测试实测全绿，安全红线执行到位，仓库卫生无可挑剔。它的短板不在"做得差"而在"没做完"——分发签名、外围编排层测试、构建系统统一三件事决定了它目前仍是"作者自己的工具"而非"陌生人也敢装的工具"。以同类个人开源 macOS 工具为参照系，加权总分 **8.2/10**；补齐发布工程后有望进入 9 分档。

---

*本报告由 ox-alpha（经 opencode CLI）生成。与纯静态审查不同，本报告的测试结论来自实际执行的 `swift test`，Git 健康度结论来自实际的 `git count-objects`/`git ls-files` 检查；GUI 应用本身未运行，Xcode 构建路径未实测。*
