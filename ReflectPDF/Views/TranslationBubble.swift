import SwiftUI

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    /// Returns the saved VocabularyEntry ID on success, or nil on failure.
    let onSave: (TranslationResult) -> String?
    /// Called after the entry is deleted; passes the deleted entry ID so the parent
    /// can remove the corresponding PDF highlight annotation.
    let onDelete: (String) -> Void
    let onDismiss: () -> Void

    @StateObject private var audio = AudioService()
    /// ID of the entry once saved (or pre-existing).
    @State private var savedEntryId: String?

    // Drag state
    @State private var baseOffset: CGSize = .zero
    @State private var dragDelta: CGSize = .zero
    private var effectiveOffset: CGSize {
        CGSize(width: baseOffset.width + dragDelta.width,
               height: baseOffset.height + dragDelta.height)
    }

    var body: some View {
        card
            .offset(effectiveOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(                // Tap outside to dismiss
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
            )
            .onAppear {
                savedEntryId = request.existingEntryId
            }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
        .frame(width: 380)
    }

    // MARK: - Header (drag handle)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(request.result?.word ?? request.word)
                        .font(.title2.bold())

                    if let phonetic = request.result?.phonetic, !phonetic.isEmpty {
                        Text("[\(phonetic)]")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let pos = request.result?.partOfSpeech, !pos.isEmpty {
                        Text(pos)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }

                if let src = request.result?.source, src == "fallback" {
                    Label("基础翻译", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

            // Drag hint + controls
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption).foregroundStyle(.tertiary)

                Button { audio.speak(request.result?.word ?? request.word) } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(.plain).disabled(isLoading)

                Button { onDismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        // Drag gesture on the header
        .gesture(
            DragGesture()
                .onChanged { v in dragDelta = v.translation }
                .onEnded { v in
                    baseOffset = CGSize(width: baseOffset.width + v.translation.width,
                                       height: baseOffset.height + v.translation.height)
                    dragDelta = .zero
                }
        )
        .cursor(.openHand)
    }

    // MARK: - Content body

    @ViewBuilder
    private var content: some View {
        if isLoading {
            HStack(spacing: 8) {
                SpinnerView()
                Text("翻译中…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
        } else if let result = request.result {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !result.contextTranslation.isEmpty {
                        BubbleSection("语境翻译") {
                            Text(result.contextTranslation).font(.body)
                        }
                    }
                    if !result.contextExplanation.isEmpty {
                        BubbleSection("语境解释") {
                            Text(result.contextExplanation)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if !result.generalDefinition.isEmpty {
                        BubbleSection("通用释义") {
                            Text(result.generalDefinition)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    // Context sentence – normal body style, no italic/tertiary
                    BubbleSection("原文语境") {
                        Text(request.sentence)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 260)

            Divider()
            footer(result: result)
        } else {
            Text("翻译失败，请重试")
                .font(.callout).foregroundStyle(.secondary).padding(14)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(result: TranslationResult) -> some View {
        HStack {
            Spacer()
            if let entryId = savedEntryId {
                // Already saved — show delete option
                HStack(spacing: 12) {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                    Button(role: .destructive) {
                        try? BridgeService.shared.deleteVocabulary(id: entryId)
                        savedEntryId = nil
                        onDelete(entryId)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    savedEntryId = onSave(result)
                } label: {
                    Label("保存到单词本", systemImage: "bookmark")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Spinner (avoids AppKit NSProgressIndicator AutoLayout warning)

private struct SpinnerView: View {
    @State private var angle: Double = 0
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

// MARK: - Section label

private struct BubbleSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Cursor modifier (macOS)

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
