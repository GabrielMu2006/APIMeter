# API Meter 项目评价报告

## 评估元信息

| 项目 | 内容 |
|---|---|
| 评估模型 | Kimi Code CLI v0.38.0（Moonshot AI / 月之暗面），底层模型版本未在运行环境中显式暴露 |
| 评估日期 | 2026-08-24 |
| 评估方式 | 静态代码审查（只读，未改动任何文件、未运行构建/测试）；通过 3 个并行只读子代理分别覆盖 Swift 主工程、DeepSeekSync 子项目、文档/CI/Git 状态 |
| 评估对象版本 | 仓库 `main` 分支，工作区干净；最新发布产物 `dist/API-Meter-1.1.0.dmg` |
| 评分量表 | 每维度 1–10 分，10 分为同类个人开源项目中的顶尖水平 |

> 说明：本报告供跨模型/跨框架横向对比使用。其他评估者请保持评分维度一致，并在元信息中注明模型与日期。

---

## 一、评分总表

| 维度 | 得分 | 一句话理由 |
|---|---|---|
| 架构设计 | 8.5 | 分层清晰、组合根 DI、domain 与存储模型分离；双构建系统是唯一明显扣分项 |
| 代码质量 | 8.5 | 文件小而聚焦、零 TODO、命名规范；`UsageRepository` 略成上帝对象 |
| 数据正确性 | 9.5 | Decimal 金额、REPLACE 语义、双重去重、导入后对账、多级降级，远超个人项目平均水平 |
| 测试覆盖 | 7.0 | 核心库 66 个用例覆盖扎实，但 App/UI/调度层几乎无测试 |
| 安全性 | 9.0 | Keychain 存密钥、日志脱敏、ephemeral session、不存密码；签名配置弱是唯一短板 |
| 文档质量 | 9.0 | 双语 README、3554 行 spec、决策记录、诚实的验证报告；少量时效性瑕疵 |
| 工程化/CI/发布 | 6.5 | CI 双轨构建可靠，但无 lint、无 release 自动化、手工 DMG + ad-hoc 签名 |
| 可维护性 | 7.5 | 结构易读、提交历史干净规范；双构建漂移风险和 spec 状态滞后是隐患 |
| **加权总分** | **8.2** | 工程质量偏上的个人项目，核心链路严谨，外围工程化待补 |

---

## 二、项目概述

**API Meter** 是一个本地优先的 macOS 15+ 原生菜单栏应用，将 DeepSeek 官方余额 API 与 Usage 导出（ZIP/CSV）整合为常驻桌面的 API 消费仪表盘：余额展示、今日消费估算、每日趋势、多 API Key 分布、余额告警、每天 00:30 自动同步。

仓库为单仓多组件结构：

- **APIMeter/**（Swift，69 个文件约 5500 行）：主应用，SwiftUI + AppKit 混合，GRDB 持久化。
- **DeepSeekSync/**（Node.js/TypeScript + Playwright，约 393 行源码）：独立 CLI，驱动真实 Chromium 从 DeepSeek 官方平台自动下载用量导出，会话存 Keychain、不存密码；主应用通过子进程调用它。
- **Tools/PhaseAValidator**：SwiftPM 可执行目标 `apimeter`，数据链路验证与自检 CLI。
- **Tests/**：Swift Testing 为主的核心库测试 + 1 个 XCTest UI 回归测试。
- **docs/ + 根目录文档**：spec、架构、CSV schema、验证报告、隐私声明，中英双语 README。

构建为 SwiftPM 与 Xcode 双轨：SwiftPM 暴露 `APIMeterCore` 库（排除 UI/App 层），Xcode 工程构建完整 app。第三方依赖仅 GRDB 7.11.1 与 KeyboardShortcuts 1.17.0，依赖面控制得很好。

---

## 三、主要优点

1. **数据正确性工程是全项目最突出的亮点**。金额用 Decimal（TEXT 存储）避免浮点误差；官方导入采用 REPLACE 语义（按 day+model+key 先删后插）防止重复累计；文件级 SHA256 + 行级 `sourceRowHash` 双重去重；每次导入后执行派生成本与账单总额对账，不一致自动降级为 `estimated`；"今日消费"用余额快照差值估算，基线超 24 小时拒绝使用、无基线有降级方案。这套"宁可显示 Unknown 也不显示错误数字"的设计哲学贯穿始终，且在 PROJECT_SPEC 中有明确的决策记录支撑。

2. **安全红线执行干净**。API key 只存 macOS Keychain（`AfterFirstUnlockThisDeviceOnly`，本机不同步）；SQLite 只存 SHA256 指纹；日志层正则脱敏所有 `sk-...`；网络请求使用 ephemeral session，错误日志刻意不含 URL 与 key；DeepSeekSync 明确不读浏览器 cookie、不存密码、无 MITM。审查中未发现任何硬编码凭据。

3. **架构与代码组织良好**。UI → ViewModel → AppEnvironment（组合根 DI）→ Repository/Service → SQLite/Keychain/API，UI 不直接触碰存储和网络；domain model 与 GRDB row struct 分离；单文件普遍 50–60 行，最大文件 471 行，全仓零 TODO/FIXME。

4. **文档纪律高于平均水平**。中英 README 完全对照；3554 行 PROJECT_SPEC 含决策记录（DR-001），代码注释引用 spec 条目号可追溯；验证报告（phase-a-report.md）甚至包含自我纠错的 Addendum——先声称"按 key 成本不可得"，实测后主动修正。这种诚实在项目文档中很少见。

5. **Git 仓库健康**。工作区干净，提交历史粒度合理、信息规范，演进线清晰（功能 → 自动同步 → 打包 → 发布 → 修复迭代）。

## 四、主要问题

1. **双构建系统的漂移风险（中危）**。SwiftPM 靠 `exclude: ["App", "UI", "ViewModels", "Window"]` 划分 core/app，Xcode 工程手工列举源文件。新增目录若忘记同步两边，会静默漏编或重复编译，且不会报错。

2. **App/UI/调度层测试近乎空白（中危）**。66 个测试全部集中在 Core 库；`SyncScheduler`（每天自动同步的唯一调度入口）、`DashboardViewModel` 等含副作用的代码无覆盖。而 `SyncScheduler.runSyncCLI` 本身实现较脆弱：用 `while process.isRunning + sleep(500ms)` 轮询等待子进程、字符串拼接路径、只取 stdout 最后一行解析为 JSON——任何一个环节出问题都只会在第二天同步失败时暴露。

3. **`UsageRepository.swift`（471 行）是上帝对象（低危）**。一个类承担 API key 管理、usage 读写、余额快照、导入批次、定价规则、今日估算、对账、retention 共八类职责。当前规模尚可读，但会是后续迭代的冲突热点。

4. **分发与签名配置弱（中危）**。`ENABLE_HARDENED_RUNTIME = NO`、无 entitlements、ad-hoc 签名、未公证：用户首次启动需右键放行；且因签名不稳定，重新构建后 Keychain 访问失效（README 自己承认了这个问题）。DMG 构建完全手工，无 release 流水线。

5. **文档时效性小瑕疵（低危）**。README 与 ARCHITECTURE 写"64 个测试"，实际 66 个；PROJECT_SPEC 第 3 节非目标条款与 DR-001 决策冲突但未清理原文，Phase C 章节（18–24 节）未实现却无状态标注，新读者难以判断现状；`apimeter` CLI 的 usage() 帮助文本漏列 `rebuild` 命令。

6. **DeepSeekSync 的固有脆弱性（已知风险）**。导出依赖页面文本匹配（"近 30 天"/"Export"），DeepSeek 前端改版即失效；`waitForTimeout` 固定等待在慢网下不稳；hidden 模式靠把窗口移到屏幕外规避 CloudFront 检测。项目已有 `dump` 调试命令和明确的错误分类作为缓解，属合理的工程权衡，但本质上是长期维护负担。

## 五、改进建议（按优先级）

1. **给 `SyncScheduler` 补测试并加固实现**（高）：子进程等待改为 `terminationHandler` 回调；JSON 输出加起止标记而非"取最后一行"；这是唯一无人值守的自动化链路，可靠性应该最高。

2. **拆分 `UsageRepository`**（高）：按职责拆为 KeyRepository / UsageRepository / Snapshot+ReconcileRepository / PricingRepository 三到四个，471 行拆完后每块都可独立测试。

3. **统一构建源或加一致性校验**（中）：让 Xcode 工程直接引用 SwiftPM 包，或在 CI 中加一步校验两边源文件清单一致，消除静默漂移。

4. **加 release 工作流**（中）：tag 触发自动构建 DMG + 版本号校验；条件允许时申请 Apple Developer ID 做公证，可一并解决 Gatekeeper 拦截和 Keychain 随构建失效两个问题。

5. **文档维护**（低）：更新测试计数；给 PROJECT_SPEC 各章节加"已实现/未实现"状态标注；补 `rebuild` 帮助文本。

6. **DeepSeekSync 可观测性**（低）：`sync` 失败时自动附带页面截图 + `dump` 输出，DeepSeek 改版时能快速区分"选择器失效"与"会话过期"。

## 六、总体结论

这是一个工程质量明显偏上的个人项目：核心数据链路（导入/去重/对账/估算）设计严谨、幂等性好，安全红线执行彻底，文档诚实且可追溯，依赖面克制。它的短板不在"做得差"而在"没做完"——App 层测试、构建系统统一、发布自动化这三件外围工程尚未补齐。以同类个人开源 macOS 工具为参照系，综合评分 **8.2/10**。

---

*本报告由 Kimi Code CLI v0.38.0 生成。评估为静态审查，未实际运行应用或执行测试套件；涉及测试通过率的结论基于 CI 配置与代码结构推断，而非实测。*
