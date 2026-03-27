import SwiftUI

struct SettingsView: View {
    /// When non-nil, this view is shown as a setup sheet; the closure is called to dismiss it.
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var appState: AppState
    @AppStorage("llm_base_url") private var baseURL = ""
    @AppStorage("llm_model") private var model = ""
    @AppStorage("target_language") private var targetLanguage = "简体中文"
    @State private var apiKey = ""
    @State private var showSavedBadge = false

    var body: some View {
        Form {
            Section("LLM 配置") {
                TextField("例：https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKey = KeychainService.load(key: "llm_api_key") ?? "" }

                TextField("例：gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            Section("翻译设置") {
                Picker("目标语言", selection: $targetLanguage) {
                    Text("简体中文").tag("简体中文")
                    Text("繁體中文").tag("繁體中文")
                    Text("日本語").tag("日本語")
                    Text("한국어").tag("한국어")
                }
            }

            HStack {
                // Extra buttons only shown in setup-sheet mode
                if let dismiss = onDismiss {
                    Button("稍后设置") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button("永不提醒") {
                        UserDefaults.standard.set(true, forKey: "llm_setup_never_remind")
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }

                Spacer()

                if showSavedBadge {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("保存设置") {
                    saveSettings()
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }

    private func saveSettings() {
        KeychainService.save(key: "llm_api_key", value: apiKey)
        // Hot-swap config in the running Rust backend — takes effect immediately.
        BridgeService.shared.updateConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            targetLanguage: targetLanguage
        )
        withAnimation { showSavedBadge = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedBadge = false }
        }
    }
}

