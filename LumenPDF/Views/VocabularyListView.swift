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
            || $0.contextSentenceTranslation.lowercased().contains(q)
            || $0.contextExplanation.lowercased().contains(q)
        }
    }

    /// Group by word, preserving first-seen order.
    private var grouped: [(word: String, entries: [VocabularyEntry])] {
        var seen = Set<String>()
        var words: [String] = []
        var groups: [String: [VocabularyEntry]] = [:]
        for entry in filtered {
            if !seen.contains(entry.word) {
                seen.insert(entry.word)
                words.append(entry.word)
            }
            groups[entry.word, default: []].append(entry)
        }
        return words.map { (word: $0, entries: groups[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索单词…", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
            .padding(12)

            Divider()

            if appState.vocabulary.isEmpty {
                emptyState
            } else if grouped.isEmpty {
                Spacer()
                Text("没有匹配结果").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(grouped, id: \.word) { group in
                            GroupedVocabularyCard(
                                word: group.word,
                                entries: group.entries,
                                audio: audio,
                                onEdit: { editingEntry = $0 },
                                onDelete: { delete($0) },
                                onJump: { jumpToPDF(entry: $0) }
                            )
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
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text("还没有保存单词").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func delete(_ entry: VocabularyEntry) {
        try? BridgeService.shared.deleteVocabulary(id: entry.id)
        NotificationCenter.default.post(
            name: .removeHighlight, object: nil,
            userInfo: [
                "entryId": entry.id,
                "pageIndex": Int(entry.pageIndex),
                "filePath": entry.pdfPath
            ]
        )
        appState.refreshVocabulary()
    }

    private func jumpToPDF(entry: VocabularyEntry) {
        if let doc = appState.library.first(where: { $0.filePath == entry.pdfPath }) {
            appState.selectedDocument = doc
            appState.activeTab = .reader
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(
                    name: .jumpToPage, object: nil,
                    userInfo: ["pageIndex": Int(entry.pageIndex), "filePath": entry.pdfPath]
                )
            }
        }
    }
}

// MARK: - Grouped Card

private struct GroupedVocabularyCard: View {
    let word: String
    let entries: [VocabularyEntry]
    let audio: AudioService
    let onEdit: (VocabularyEntry) -> Void
    let onDelete: (VocabularyEntry) -> Void
    let onJump: (VocabularyEntry) -> Void

    /// Use the first entry's phonetic/POS/generalDefinition as the word-level summary.
    private var primary: VocabularyEntry { entries[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Word header（词性不展示，避免标签过长占版面）──────────────────────
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !primary.phonetic.isEmpty {
                        Text("[\(primary.phonetic)]")
                            .font(.body).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { audio.speak(word) } label: {
                    Image(systemName: "speaker.wave.1.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // ── General definition (word-level) ───────────────────────────────
            if !primary.generalDefinition.isEmpty {
                Text(primary.generalDefinition)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Divider().opacity(0.35)

            // ── Context entries ───────────────────────────────────────────────
            ForEach(entries) { entry in
                ContextRow(entry: entry, onEdit: onEdit, onDelete: onDelete, onJump: onJump)
                if entry.id != entries.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.16),
                            Color.primary.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Single context row inside the grouped card

private struct ContextRow: View {
    let entry: VocabularyEntry
    let onEdit: (VocabularyEntry) -> Void
    let onDelete: (VocabularyEntry) -> Void
    let onJump: (VocabularyEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Word-in-context translation
            if !entry.contextTranslation.isEmpty {
                Text(entry.contextTranslation)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }

            // 语境解释（与保存到单词本的数据一致）
            if !entry.contextExplanation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("语境解释")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(entry.contextExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            // 原文语境：英文（合并 PDF 换行）+ 下方整句译文
            if !entry.sentence.isEmpty || !entry.contextSentenceTranslation.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("原文语境")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if !entry.sentence.isEmpty {
                        Text("「\(ContextSentenceFormatting.displayParagraph(entry.sentence))」")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !entry.contextSentenceTranslation.isEmpty {
                        Text(entry.contextSentenceTranslation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            }

            // Footer: source info + actions
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.caption2).foregroundStyle(.tertiary)
                Button {
                    onJump(entry)
                } label: {
                    Text("\(entry.pdfName)  P\(entry.pageIndex + 1)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)

                if entry.queryCount > 0 {
                    Text("·").foregroundStyle(.tertiary).font(.caption2)
                    Label("\(entry.queryCount) 次", systemImage: "repeat")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Spacer()

                sourceBadge(entry.translationSource)

                // Edit / Delete buttons
                Button { onEdit(entry) } label: {
                    Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) { onDelete(entry) } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Edit sheet

private struct VocabularyEditSheet: View {
    let entry: VocabularyEntry
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phonetic: String
    @State private var partOfSpeech: String
    @State private var contextTranslation: String
    @State private var contextExplanation: String
    @State private var generalDefinition: String
    @State private var contextSentenceTranslation: String

    init(entry: VocabularyEntry, onSave: @escaping () -> Void) {
        self.entry = entry
        self.onSave = onSave
        _phonetic           = State(initialValue: entry.phonetic)
        _partOfSpeech       = State(initialValue: entry.partOfSpeech)
        _contextTranslation = State(initialValue: entry.contextTranslation)
        _contextExplanation = State(initialValue: entry.contextExplanation)
        _generalDefinition  = State(initialValue: entry.generalDefinition)
        _contextSentenceTranslation = State(initialValue: entry.contextSentenceTranslation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑「\(entry.word)」").font(.title2.bold())
            Divider()
            editRow("音标", text: $phonetic)
            editRow("词性", text: $partOfSpeech)
            editArea("语境翻译", text: $contextTranslation, height: 54)
            editArea("语境解释", text: $contextExplanation, height: 54)
            editArea("整句译文", text: $contextSentenceTranslation, height: 54)
            editArea("通用释义", text: $generalDefinition,  height: 54)
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
                        id: entry.id, phonetic: phonetic, partOfSpeech: partOfSpeech,
                        contextTranslation: contextTranslation,
                        contextExplanation: contextExplanation,
                        generalDefinition: generalDefinition,
                        contextSentenceTranslation: contextSentenceTranslation
                    )
                    onSave(); dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 580)
    }

    private func editRow(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            TextField("", text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func editArea(_ label: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            TextEditor(text: text).font(.callout).frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
    }
}

extension Notification.Name {
    static let jumpToPage = Notification.Name("jumpToPage")
}
