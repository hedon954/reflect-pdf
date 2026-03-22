import SwiftUI

// VocabularyEntry has `id: String` — just declare conformance so sheet(item:) works.
extension VocabularyEntry: Identifiable {}

struct VocabularyListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var audio = AudioService()
    @State private var searchText = ""
    @State private var editingEntry: VocabularyEntry?

    private var filtered: [VocabularyEntry] {
        guard !searchText.isEmpty else { return appState.vocabulary }
        let q = searchText.lowercased()
        return appState.vocabulary.filter {
            $0.word.lowercased().contains(q)
            || $0.contextTranslation.lowercased().contains(q)
            || $0.generalDefinition.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索单词…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            Divider()

            if appState.vocabulary.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                Spacer()
                Text("没有匹配结果").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { entry in
                            VocabularyCard(entry: entry, audio: audio)
                                .contextMenu {
                                    Button { editingEntry = entry } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    Divider()
                                    Button(role: .destructive) { delete(entry) } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .onTapGesture { jumpToPDF(entry: entry) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .onAppear { appState.refreshVocabulary() }
        .sheet(item: $editingEntry) { entry in
            VocabularyEditSheet(entry: entry) { appState.refreshVocabulary() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("还没有保存单词")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func delete(_ entry: VocabularyEntry) {
        try? BridgeService.shared.deleteVocabulary(id: entry.id)
        appState.refreshVocabulary()
    }

    private func jumpToPDF(entry: VocabularyEntry) {
        if let doc = appState.library.first(where: { $0.filePath == entry.pdfPath }) {
            appState.selectedDocument = doc
            appState.activeTab = .reader
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(
                    name: .jumpToPage,
                    object: nil,
                    userInfo: ["pageIndex": Int(entry.pageIndex), "filePath": entry.pdfPath]
                )
            }
        }
    }
}

// MARK: - Card

private struct VocabularyCard: View {
    let entry: VocabularyEntry
    let audio: AudioService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // ── Top row: word + phonetic + POS + speaker ──────────────────────
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.word)
                    .font(.title3.bold())

                if !entry.phonetic.isEmpty {
                    Text("[\(entry.phonetic)]")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !entry.partOfSpeech.isEmpty {
                    Text(entry.partOfSpeech)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                Button { audio.speak(entry.word) } label: {
                    Image(systemName: "speaker.wave.1.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // ── Context translation ───────────────────────────────────────────
            if !entry.contextTranslation.isEmpty {
                Text(entry.contextTranslation)
                    .font(.body)
            }

            // ── General definition ────────────────────────────────────────────
            if !entry.generalDefinition.isEmpty {
                Text(entry.generalDefinition)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // ── Original sentence ─────────────────────────────────────────────
            if !entry.sentence.isEmpty {
                Text("「\(entry.sentence)」")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
            }

            // ── Footer: source + query count + badge ──────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(entry.pdfName)  P\(entry.pageIndex + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if entry.queryCount > 0 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    Label("\(entry.queryCount) 次", systemImage: "repeat")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                sourceBadge(entry.translationSource)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private func sourceBadge(_ src: String) -> some View {
        let (label, color): (String, Color) = switch src {
            case "llm":      ("AI", .purple)
            case "fallback": ("基础", .orange)
            default:         ("缓存", .gray)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Edit sheet (all translation fields editable)

private struct VocabularyEditSheet: View {
    let entry: VocabularyEntry
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phonetic: String
    @State private var partOfSpeech: String
    @State private var contextTranslation: String
    @State private var contextExplanation: String
    @State private var generalDefinition: String

    init(entry: VocabularyEntry, onSave: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        _phonetic           = State(initialValue: entry.phonetic)
        _partOfSpeech       = State(initialValue: entry.partOfSpeech)
        _contextTranslation = State(initialValue: entry.contextTranslation)
        _contextExplanation = State(initialValue: entry.contextExplanation)
        _generalDefinition  = State(initialValue: entry.generalDefinition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑「\(entry.word)」")
                .font(.title2.bold())

            Divider()

            editRow("音标", text: $phonetic)
            editRow("词性", text: $partOfSpeech)
            editArea("语境翻译", text: $contextTranslation, height: 54)
            editArea("语境解释", text: $contextExplanation, height: 54)
            editArea("通用释义", text: $generalDefinition,  height: 54)

            // Read-only source info
            HStack(spacing: 4) {
                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                Text("\(entry.pdfName)  P\(entry.pageIndex + 1)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    try? BridgeService.shared.updateVocabulary(
                        id: entry.id,
                        phonetic: phonetic,
                        partOfSpeech: partOfSpeech,
                        contextTranslation: contextTranslation,
                        contextExplanation: contextExplanation,
                        generalDefinition: generalDefinition
                    )
                    onSave(); dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 520)
    }

    private func editRow(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func editArea(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.callout)
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }
}

extension Notification.Name {
    static let jumpToPage = Notification.Name("jumpToPage")
}
