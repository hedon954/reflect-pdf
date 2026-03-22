import SwiftUI

struct VocabularyListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var audio = AudioService()
    @State private var searchText = ""

    private var filtered: [VocabularyEntry] {
        guard !searchText.isEmpty else { return appState.vocabulary }
        return appState.vocabulary.filter {
            $0.word.localizedCaseInsensitiveContains(searchText)
            || $0.contextTranslation.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
                .padding(8)

            if appState.vocabulary.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("还没有保存单词")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List(filtered, id: \.id) { entry in
                    VocabularyRow(entry: entry, audio: audio)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                        .onTapGesture {
                            jumpToPDF(entry: entry)
                        }
                }
                .listStyle(.sidebar)
            }
        }
        .onAppear { appState.refreshVocabulary() }
    }

    private func delete(_ entry: VocabularyEntry) {
        try? BridgeService.shared.deleteVocabulary(id: entry.id)
        appState.refreshVocabulary()
    }

    private func jumpToPDF(entry: VocabularyEntry) {
        guard let doc = appState.library.first(where: { $0.filePath == entry.pdfPath }) else { return }
        appState.selectedDocument = doc
        appState.sidebarTab = .library
    }
}

private struct VocabularyRow: View {
    let entry: VocabularyEntry
    let audio: AudioService

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.word)
                        .font(.callout.bold())

                    if !entry.phonetic.isEmpty {
                        Text("[\(entry.phonetic)]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        audio.speak(entry.word)
                    } label: {
                        Image(systemName: "speaker.wave.1")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                if !entry.contextTranslation.isEmpty {
                    Text(entry.contextTranslation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text("\(entry.pdfName) · P\(entry.pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索单词…", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}
