import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("llm_base_url") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("llm_model") private var model = "gpt-4o-mini"
    @AppStorage("target_language") private var targetLanguage = "简体中文"
    @State private var apiKey = ""
    @State private var showSavedBadge = false

    var body: some View {
        Form {
            Section("LLM 配置") {
                TextField("API Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { apiKey = KeychainService.load(key: "llm_api_key") ?? "" }

                TextField("模型", text: $model)
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
                Spacer()
                if showSavedBadge {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("保存设置") {
                    saveSettings()
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
        BridgeService.shared.updateConfig(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            targetLanguage: targetLanguage
        )
        withAnimation {
            showSavedBadge = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSavedBadge = false }
        }
    }
}
