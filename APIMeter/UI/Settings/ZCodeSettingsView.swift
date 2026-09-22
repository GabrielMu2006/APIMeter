import SwiftUI

/// ZCode (Zhipu Coding Plan) key management + quota status. Mirrors the
/// DeepSeek tab: raw key never shown after saving, only the fingerprint.
struct ZCodeSettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Coding Plan API Key") {
                if state.zcodeQuotaViewModel.hasStoredKey == false {
                    SecureField("Paste your Coding Plan API key", text: $state.settingsViewModel.zcodeKeyInput)
                        .onSubmit {
                            Task {
                                await state.settingsViewModel.saveZCodeKey()
                                await state.zcodeQuotaViewModel.refresh(force: true)
                            }
                        }
                    Button("Save to Keychain") {
                        Task {
                            await state.settingsViewModel.saveZCodeKey()
                            await state.zcodeQuotaViewModel.refresh(force: true)
                        }
                    }
                    Text("Create the key in the BigModel / Z.ai console (Coding Plan section) and paste it here. It is stored only in the macOS Keychain, never in the database or logs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Stored key") {
                        HStack(spacing: 6) {
                            Text("••••••••" + KeyFingerprint.displayPrefix(state.zcodeQuotaViewModel.activeFingerprint ?? "", length: 4))
                                .monospaced()
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                Task {
                                    await state.settingsViewModel.removeZCodeKey()
                                    await state.zcodeQuotaViewModel.refresh(force: true)
                                }
                            }
                        }
                    }
                }
            }

            Section("Region") {
                Picker("Account region", selection: Binding(
                    get: { state.environment.settings.zcodeRegion },
                    set: { newValue in
                        state.environment.settings.zcodeRegion = newValue
                        state.zcodeQuotaViewModel.resetThrottle()
                        Task { await state.zcodeQuotaViewModel.refresh(force: true) }
                    }
                )) {
                    ForEach(ZCodeRegion.allCases) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("BigModel (China) uses open.bigmodel.cn; Z.ai (Global) uses api.z.ai. The key is region-bound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quota") {
                HStack {
                    Button("Test Connection") {
                        Task {
                            await state.settingsViewModel.testZCodeConnection()
                            await state.zcodeQuotaViewModel.refresh(force: true)
                        }
                    }
                    if let quota = state.settingsViewModel.zcodeQuota ?? state.zcodeQuotaViewModel.quota {
                        Text("Last fetch " + quota.fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let quota = state.settingsViewModel.zcodeQuota ?? state.zcodeQuotaViewModel.quota {
                    LabeledContent("Plan") { Text(quota.planLevel?.capitalized ?? "—") }
                    quotaRow(label: "5-hour window", window: quota.fiveHour)
                    quotaRow(label: "Weekly window", window: quota.weekly)
                } else {
                    Text("No quota fetched yet. Save a key and click Test Connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = state.zcodeQuotaViewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                if let message = state.settingsViewModel.zcodeStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Failed") || message.hasPrefix("Connection failed") ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Kimi (auto-detected)") {
                switch state.kimiQuotaViewModel.credentialState {
                case .available:
                    LabeledContent("Credential") {
                        Text("Kimi CLI token detected")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Refresh") {
                        Text("Automatic - expired tokens refresh in the background")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .expired:
                    LabeledContent("Credential") {
                        Text("凭据已失效 - 请运行 kimi login 重新登录")
                            .foregroundStyle(.orange)
                    }
                case .missing:
                    LabeledContent("Credential") {
                        Text("Not found - install/log in to the Kimi CLI (~/.kimi-code)")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Test Connection") {
                        Task { await state.kimiQuotaViewModel.refresh(force: true) }
                    }
                    if let quota = state.kimiQuotaViewModel.quota {
                        Text("Last fetch " + quota.fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let quota = state.kimiQuotaViewModel.quota {
                    LabeledContent("Plan") { Text(quota.planLevel ?? "—") }
                    LabeledContent("Windows") {
                        Text("5-hour and weekly (7d); no monthly limit")
                            .foregroundStyle(.secondary)
                    }
                    if let weekly = quota.weekly {
                        LabeledContent("Weekly") {
                            Text("剩 " + (weekly.remainingPercent.map(QuotaWidgetCard.percentText) ?? "—"))
                                .monospacedDigit()
                        }
                    }
                    if let fiveHour = quota.fiveHour {
                        LabeledContent("5-hour") {
                            Text("剩 " + (fiveHour.remainingPercent.map(QuotaWidgetCard.percentText) ?? "—"))
                                .monospacedDigit()
                        }
                    }
                }
                if let error = state.kimiQuotaViewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("Qoder (auto-detected)") {
                switch state.qoderQuotaViewModel.credentialState {
                case .available(let credential):
                    LabeledContent("Credential") {
                        Text("Qoder CN token detected" + (credential.accountLabel.map { " · " + $0 } ?? ""))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    LabeledContent("Token expiry") {
                        Text(credential.expiresAt.map { "有效期至 " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                case .expired:
                    LabeledContent("Credential") {
                        Text("凭据已过期 - 请在 Qoder 桌面版重新登录")
                            .foregroundStyle(.orange)
                    }
                case .missing:
                    LabeledContent("Credential") {
                        Text("未找到 - 安装并登录 Qoder 桌面版")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Test Connection") {
                        Task { await state.qoderQuotaViewModel.refresh(force: true) }
                    }
                    if let quota = state.qoderQuotaViewModel.quota {
                        Text("Last fetch " + quota.fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let quota = state.qoderQuotaViewModel.quota {
                    if let personal = quota.monthly {
                        LabeledContent("个人池") {
                            Text("剩 " + (personal.effectiveRemaining.map(QuotaWidgetCard.remainingText) ?? "—")
                                + " / " + (personal.totalValue.map(QuotaWidgetCard.remainingText) ?? "—") + " credits")
                                .monospacedDigit()
                        }
                    }
                    if let org = quota.orgMonthly {
                        LabeledContent("组织池") {
                            Text("剩 " + (org.effectiveRemaining.map(QuotaWidgetCard.remainingText) ?? "—") + " credits")
                                .monospacedDigit()
                        }
                    } else {
                        LabeledContent("组织池") {
                            Text("未开放")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = state.qoderQuotaViewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("Codex (auto-detected)") {
                switch state.codexQuotaViewModel.credentialState {
                case .available(let credential):
                    LabeledContent("Credential") {
                        Text("Codex CLI token detected"
                            + (credential.planType.map { " · " + $0.capitalized } ?? ""))
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Token expiry") {
                        Text(credential.expiresAt.map { "有效期至 " + $0.formatted(date: .abbreviated, time: .omitted) + "（过期自动续期）" } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                case .expired:
                    LabeledContent("Credential") {
                        Text("凭据已失效 - 请运行 codex login 重新登录")
                            .foregroundStyle(.orange)
                    }
                case .missing:
                    LabeledContent("Credential") {
                        Text("未找到 - 安装并运行 codex login")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Use proxy for Codex requests", isOn: Binding(
                    get: { state.environment.settings.codexProxyEnabled },
                    set: { enabled in
                        state.environment.settings.codexProxyEnabled = enabled
                        Task { await state.codexQuotaViewModel.refresh(force: true) }
                    }
                ))
                if state.environment.settings.codexProxyEnabled {
                    TextField("http://127.0.0.1:7890", text: Binding(
                        get: { state.environment.settings.codexProxyAddress },
                        set: { state.environment.settings.codexProxyAddress = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await state.codexQuotaViewModel.refresh(force: true) }
                    }
                    if let proxy = CodexProxyConfig.parse(state.environment.settings.codexProxyAddress) {
                        Text("已启用：Codex 请求经由 \(proxy.host):\(proxy.port)（\(proxy.kind == .http ? "HTTP" : "SOCKS")），仅影响 API Meter 自己的额度请求。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("无法解析代理地址 - 示例：http://127.0.0.1:8080 或 socks5://127.0.0.1:7890（需带端口）。地址无效时仍按直连尝试。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("chatgpt.com 在部分网络无法直连。URLSession 不读取环境变量代理，如果你的 Codex CLI 依赖本地代理，请在上面填入同一地址。默认关闭。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Test Connection") {
                        Task { await state.codexQuotaViewModel.refresh(force: true) }
                    }
                    if let quota = state.codexQuotaViewModel.quota {
                        Text("Last fetch " + quota.fetchedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let quota = state.codexQuotaViewModel.quota {
                    if let fiveHour = quota.fiveHour {
                        LabeledContent("5-hour") {
                            Text("已用 " + (fiveHour.usedPercent.map(QuotaWidgetCard.percentText) ?? "—"))
                                .monospacedDigit()
                        }
                    }
                    if let weekly = quota.weekly {
                        LabeledContent("Weekly") {
                            Text("已用 " + (weekly.usedPercent.map(QuotaWidgetCard.percentText) ?? "—"))
                                .monospacedDigit()
                        }
                    }
                }
                if let error = state.codexQuotaViewModel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section("Desktop Widgets") {
                Toggle("Show on Desktop", isOn: Binding(
                    get: { state.environment.settings.showDesktopWidgets },
                    set: { enabled in
                        state.environment.settings.showDesktopWidgets = enabled
                        if enabled {
                            state.widgetPanelController?.show()
                        } else {
                            state.widgetPanelController?.hide()
                        }
                    }
                ))
                Text("Floating widget cards at desktop level: ZCode 5-hour and weekly quota plus the DeepSeek balance. Drag to move; right-click for actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    @ViewBuilder
    private func quotaRow(label: String, window: QuotaWindow?) -> some View {
        if let window {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    if let remaining = window.effectiveRemaining {
                        Text("剩 " + QuotaWidgetCard.remainingText(remaining)).monospacedDigit()
                    } else {
                        Text("—")
                    }
                    if let remaining = window.effectiveRemaining, let total = window.totalValue {
                        Text("/ " + QuotaWidgetCard.remainingText(total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let percent = window.remainingPercent {
                        Text("剩 " + QuotaWidgetCard.percentText(percent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let resetsAt = window.resetsAt {
                        Text("resets " + resetsAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}
