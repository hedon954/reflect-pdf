import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if let doc = appState.selectedDocument {
                PDFReaderView(document: doc)
            } else {
                EmptyStateView()
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = appState.toastMessage {
                ToastView(message: msg)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: appState.toastMessage)
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $appState.sidebarTab) {
                Text("文库").tag(SidebarTab.library)
                Text("单词本").tag(SidebarTab.vocabulary)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch appState.sidebarTab {
            case .library:
                LibrarySidebarView()
            case .vocabulary:
                VocabularyListView()
            }
        }
        .frame(minWidth: 220, idealWidth: 240)
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("打开一个 PDF 开始阅读")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("选择文件…") {
                appState.openFilePicker()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
    }
}
