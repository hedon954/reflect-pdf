import SwiftUI
import AppKit

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let onSave: (TranslationResult) -> String?
    let onDelete: (String) -> Void
    let onDismiss: () -> Void

    @StateObject private var audio = AudioService()
    @State private var savedEntryId: String?
    /// Tracks whether the saved entry is a note (sentence mode) or vocabulary entry
    @State private var savedToNote: Bool = false

    // Drag offset — updated directly from AppKit mouse events (no SwiftUI gesture layer)
    @State private var offset: CGSize = .zero

    var body: some View {
        card
            .offset(offset)
            // Suppress all implicit animations on the card during drag
            .animation(nil, value: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss() }
            )
            .onAppear { savedEntryId = request.existingEntryId }
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
        .frame(maxHeight: 680) // Upper bound for long content
    }

    // MARK: - Header (AppKit drag handle)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // 纵向排列：单词独占一行按词换行，避免与音标挤在同一行导致「拦腰断词」
                Text(request.result?.word ?? request.word)
                    .font(.title2.bold())
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let phonetic = request.result?.phonetic, !phonetic.isEmpty {
                    Text("[\(phonetic)]")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let src = request.result?.source, src == "fallback" {
                    Label(
                        (request.result?.llmErrorMessage.isEmpty == false)
                            ? "基础翻译（LLM 未成功，见下方说明）"
                            : "基础翻译",
                        systemImage: "info.circle"
                    )
                    .font(.caption2).foregroundStyle(.orange)
                }
            }

            Spacer()

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
        // AppKit-level drag capture sits behind the content; buttons on top still fire normally
        .background(
            AppKitDragCapture { delta in
                offset.width  += delta.width
                offset.height += delta.height
            }
        )
        .cursor(.openHand)
    }

    // MARK: - Content body

    @ViewBuilder
    private var content: some View {
        // While streaming, show the partial result as soon as ANY field is
        // populated. Falling back to the full spinner only when we have
        // nothing to display avoids the awkward "blank → 5 s → everything"
        // transition the non-streaming version produced.
        if let result = request.result, Self.hasAnyContent(result) {
            if result.isCompleteFailure {
                completeFailureView(result: result)
            } else {
                if isLoading {
                    streamingBanner
                }
                ViewThatFits(in: .vertical) {
                    contentBody(result: result)
                    ScrollView { contentBody(result: result) }
                        .frame(maxHeight: 520)
                }

                errorSection(result: result)

                if !isLoading {
                    Divider()
                    footer(result: result)
                }
            }
        } else if isLoading {
            HStack(spacing: 8) {
                SpinnerView()
                Text("翻译中…").font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("翻译未完成")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                Spacer(minLength: 24)
                Divider()
                Group {
                    if let detail = request.translationError, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("请检查网络与 LLM 设置后重试。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
    }

    // MARK: - Streaming banner

    /// Slim header rendered above the content while the LLM is still
    /// streaming. Lets the user see early fields while keeping a clear
    /// "still loading" affordance.
    private var streamingBanner: some View {
        HStack(spacing: 6) {
            SpinnerView()
            Text("正在生成…").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    /// Returns true if the result has at least one user-visible field filled
    /// in (anything other than `word` alone, since `word` defaults to the
    /// selection text and is always present).
    private static func hasAnyContent(_ r: TranslationResult) -> Bool {
        !r.phonetic.isEmpty
            || !r.partOfSpeech.isEmpty
            || !r.contextTranslation.isEmpty
            || !r.contextExplanation.isEmpty
            || !r.generalDefinition.isEmpty
            || !r.contextSentenceTranslation.isEmpty
            || r.isCompleteFailure
    }

    // MARK: - Complete failure view

    @ViewBuilder
    private func completeFailureView(result: TranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("翻译失败")
                .font(.headline)
                .foregroundStyle(.red)

            Text("所有翻译途径均失败，请检查网络连接和 LLM 设置")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // LLM error
            if !result.llmErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("LLM 调用失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Text(result.llmErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Fallback error
            if !result.fallbackErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("兜底翻译失败", systemImage: "xmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Text(result.fallbackErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
    }

    // MARK: - Error section

    @ViewBuilder
    private func errorSection(result: TranslationResult) -> some View {
        // LLM error (shown even when fallback succeeded)
        if !result.llmErrorMessage.isEmpty || !result.fallbackErrorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !result.llmErrorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LLM 调用未成功", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(result.llmErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                if !result.fallbackErrorMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("兜底翻译部分失败", systemImage: "info.circle")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(result.fallbackErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Content body helper

    @ViewBuilder
    private func contentBody(result: TranslationResult) -> some View {
        // Check if this is sentence-only mode (word is the sentence, no word-level analysis)
        let isSentenceOnly = request.isSentenceMode
            && result.contextTranslation.isEmpty
            && result.generalDefinition.isEmpty
            && result.phonetic.isEmpty

        if isSentenceOnly {
            // Sentence translation mode: show original and translation only
            VStack(alignment: .leading, spacing: 12) {
                BubbleSection("原文") {
                    Text(ContextSentenceFormatting.displayParagraph(request.word))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.contextSentenceTranslation.isEmpty {
                    BubbleSection("译文") {
                        Text(result.contextSentenceTranslation)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
        } else {
            // Word translation mode: show all fields
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
                BubbleSection("原文语境") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ContextSentenceFormatting.displayParagraph(request.sentence))
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !result.contextSentenceTranslation.isEmpty {
                            Text(result.contextSentenceTranslation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(result: TranslationResult) -> some View {
        HStack {
            Spacer()
            if let entryId = savedEntryId {
                HStack(spacing: 12) {
                    Label(savedToNote ? "已保存到笔记" : "已保存", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                    Button(role: .destructive) {
                        if savedToNote {
                            try? BridgeService.shared.deleteNote(id: entryId)
                        } else {
                            try? BridgeService.shared.deleteVocabulary(id: entryId)
                        }
                        savedEntryId = nil
                        onDelete(entryId)
                    } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    savedEntryId = onSave(result)
                    savedToNote = request.isSentenceMode
                } label: {
                    if request.isSentenceMode {
                        Label("保存到笔记", systemImage: "note.text")
                    } else {
                        Label("保存到单词本", systemImage: "bookmark")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - AppKit drag capture (bypasses SwiftUI gesture pipeline for frame-perfect drag)

/// Transparent NSView that processes mouseDown/mouseDragged at AppKit level.
/// Placed as .background() so SwiftUI buttons layered on top still receive clicks normally.
private struct AppKitDragCapture: NSViewRepresentable {
    /// Called on the main thread with each incremental drag delta (SwiftUI coordinate space).
    let onDelta: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDelta) }
    func makeNSView(context: Context) -> NSView { context.coordinator.view }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    final class Coordinator: NSObject {
        var onDelta: (CGSize) -> Void
        lazy var view: CaptureView = CaptureView(coordinator: self)
        init(_ cb: @escaping (CGSize) -> Void) { onDelta = cb }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        /// Last mouse position in window coordinates.
        private var lastLoc: CGPoint?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {
            lastLoc = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let last = lastLoc else { return }
            let cur = event.locationInWindow
            // Window coords: Y increases upward; SwiftUI: Y increases downward → negate dy
            let delta = CGSize(width: cur.x - last.x, height: -(cur.y - last.y))
            lastLoc = cur
            coordinator?.onDelta(delta)
        }

        override func mouseUp(with event: NSEvent) {
            lastLoc = nil
        }

        // Accept the first mouse-down even when the window is not key
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - Spinner

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
