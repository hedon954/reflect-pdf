import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let document: PdfDocument
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var translationRequest: TranslationBubbleRequest?
    @State private var isTranslating = false

    var body: some View {
        ZStack {
            PDFKitView(
                filePath: document.filePath,
                savedPage: Int(document.lastPage),
                savedScrollOffset: document.lastScrollOffset,
                onPageChange: { page, offset in
                    appState.saveReadingPosition(
                        filePath: document.filePath,
                        page: UInt32(page),
                        scrollOffset: offset
                    )
                },
                onTextSelected: { word, sentence, bounds, page in
                    guard !word.isEmpty else { return }
                    requestTranslation(word: word, sentence: sentence, bounds: bounds, page: page)
                },
                onDocumentLoaded: { totalPages in
                    handleDocumentLoaded(totalPages: totalPages)
                }
            )

            if let req = translationRequest {
                TranslationBubble(
                    request: req,
                    isLoading: isTranslating,
                    onSave: { result in
                        saveToDiary(result: result, request: req)
                    },
                    onDelete: {
                        appState.refreshVocabulary()
                    },
                    onDismiss: {
                        translationRequest = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: translationRequest != nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(document.fileName)
                    .font(.headline)
            }
        }
        .id(document.id)
    }

    private func handleDocumentLoaded(totalPages: Int) {
        try? BridgeService.shared.upsertPdfDocument(
            filePath: document.filePath,
            fileName: document.fileName,
            totalPages: UInt32(totalPages)
        )
        appState.refreshLibrary()

        if document.lastPage > 0 {
            appState.showToast("已定位到 P\(document.lastPage + 1)")
        }
    }

    private func requestTranslation(word: String, sentence: String, bounds: CGRect, page: Int) {
        // Check saved vocabulary first (no LLM call)
        let hash = session.sentenceHash(sentence)
        if let saved = try? BridgeService.shared.getVocabularyByWordAndHash(word: word, sentenceHash: hash) {
            BridgeService.shared.incrementQueryCount(id: saved.id)
            translationRequest = TranslationBubbleRequest(
                word: word,
                sentence: sentence,
                bounds: bounds,
                page: page,
                result: TranslationResult(
                    word: saved.word,
                    phonetic: saved.phonetic,
                    partOfSpeech: saved.partOfSpeech,
                    contextTranslation: saved.contextTranslation,
                    contextExplanation: saved.contextExplanation,
                    generalDefinition: saved.generalDefinition,
                    source: "cache"
                ),
                existingEntryId: saved.id
            )
            return
        }

        translationRequest = TranslationBubbleRequest(
            word: word, sentence: sentence, bounds: bounds, page: page,
            result: nil, existingEntryId: nil
        )
        isTranslating = true

        Task {
            do {
                let result = try await BridgeService.shared.translate(word: word, sentence: sentence)
                await MainActor.run {
                    translationRequest?.result = result
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    isTranslating = false
                }
            }
        }
    }

    /// Returns the saved entry's ID (passed back to TranslationBubble to show delete button).
    @discardableResult
    private func saveToDiary(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        let hash = session.sentenceHash(request.sentence)
        let boundsStr = NSStringFromRect(request.bounds)
        guard let entry = try? BridgeService.shared.saveVocabulary(
            word: result.word,
            sentence: request.sentence,
            sentenceHash: hash,
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(request.page),
            selectionBounds: boundsStr,
            phonetic: result.phonetic,
            partOfSpeech: result.partOfSpeech,
            contextTranslation: result.contextTranslation,
            contextExplanation: result.contextExplanation,
            generalDefinition: result.generalDefinition,
            translationSource: result.source
        ) else { return nil }

        // Post notification so the Coordinator adds highlight to pdfView.document
        NotificationCenter.default.post(
            name: .addHighlight,
            object: nil,
            userInfo: [
                "entryId": entry.id,
                "pageIndex": Int(entry.pageIndex),
                "bounds": boundsStr,
                "filePath": document.filePath
            ]
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }
}

// MARK: - PDFKit NSViewRepresentable

struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    let onTextSelected: (String, String, CGRect, Int) -> Void
    let onDocumentLoaded: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        // Outline TOC navigation
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.outlineNavigate(_:)),
            name: .outlineNavigate,
            object: nil
        )
        // Vocabulary jump-to-page
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.jumpToPage(_:)),
            name: .jumpToPage,
            object: nil
        )
        // Add highlight annotation (on save)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.addHighlight(_:)),
            name: .addHighlight,
            object: nil
        )
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        let url = URL(fileURLWithPath: filePath)
        guard let doc = PDFDocument(url: url) else { return }

        if pdfView.document?.documentURL?.path != filePath {
            pdfView.document = doc
            context.coordinator.parent = self
            onDocumentLoaded(doc.pageCount)

            // Restore reading position
            if savedPage > 0, savedPage < doc.pageCount, let page = doc.page(at: savedPage) {
                pdfView.go(to: page)
            }

            // Restore highlights for saved vocab entries
            context.coordinator.applyHighlights(to: doc, filePath: filePath)
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var debounceTimer: Timer?
        /// Set to true during vocabulary-jump to suppress translation trigger.
        var isJumping = false

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        @objc func outlineNavigate(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath  = notification.userInfo?["filePath"]  as? String,
                  let pdfView,
                  pdfView.document?.documentURL?.path == filePath,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }
            pdfView.go(to: page)
        }

        @objc func addHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr = notification.userInfo?["bounds"]     as? String,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  let pdfView,
                  pdfView.document?.documentURL?.path == filePath,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }
            addAnnotation(entryId: entryId, boundsStr: boundsStr, to: page)
        }

        func applyHighlights(to doc: PDFDocument, filePath: String) {
            let entries = (try? BridgeService.shared.listVocabulary()) ?? []
            for entry in entries where entry.pdfPath == filePath {
                guard let page = doc.page(at: Int(entry.pageIndex)) else { continue }
                addAnnotation(entryId: entry.id, boundsStr: entry.selectionBounds, to: page)
            }
        }

        private func addAnnotation(entryId: String, boundsStr: String, to page: PDFPage) {
            let bounds = NSRectFromString(boundsStr)
            guard bounds != .zero else { return }
            guard !page.annotations.contains(where: { $0.userName == entryId }) else { return }
            let ann = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            ann.color = NSColor.systemYellow.withAlphaComponent(0.5)
            ann.userName = entryId
            page.addAnnotation(ann)
        }

        @objc func jumpToPage(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath = notification.userInfo?["filePath"] as? String,
                  let pdfView,
                  pdfView.document?.documentURL?.path == filePath,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }
            isJumping = true
            pdfView.go(to: page)
            // Clear flag after debounce window passes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let pageIndex = doc.index(for: currentPage)
            let scrollOffset = scrollOffset(for: pdfView)
            parent.onPageChange(pageIndex, scrollOffset)
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard !isJumping else { return }
            guard let pdfView = notification.object as? PDFView,
                  let selection = pdfView.currentSelection,
                  let selectedString = selection.string, !selectedString.isEmpty else { return }

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, let pdfView else { return }
                let word = selectedString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { return }
                let sentence = self.extractSentence(from: pdfView, containing: selection) ?? word
                let bounds = selection.bounds(for: pdfView.currentPage ?? pdfView.document!.page(at: 0)!)
                let pageIndex = pdfView.document!.index(for: pdfView.currentPage!)
                DispatchQueue.main.async {
                    self.parent.onTextSelected(word, sentence, bounds, pageIndex)
                }
            }
        }

        private func extractSentence(from pdfView: PDFView, containing selection: PDFSelection) -> String? {
            guard let page = pdfView.currentPage,
                  let pageText = page.string else { return nil }

            let word = selection.string ?? ""
            let sentences = pageText.components(separatedBy: CharacterSet(charactersIn: ".!?。！？"))
            for sentence in sentences {
                if sentence.contains(word) {
                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count <= 500 { return trimmed }
                }
            }
            return String(pageText.prefix(500))
        }

        private func scrollOffset(for pdfView: PDFView) -> Double {
            guard let scrollView = pdfView.enclosingScrollView else { return 0.0 }
            let contentSize = scrollView.documentView?.bounds.height ?? 1
            guard contentSize > 0 else { return 0.0 }
            let offset = scrollView.documentVisibleRect.minY / contentSize
            return max(0.0, min(1.0, offset))
        }
    }
}

// MARK: - Supporting types

extension Notification.Name {
    static let addHighlight = Notification.Name("addHighlight")
}

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let sentence: String
    let bounds: CGRect
    let page: Int
    var result: TranslationResult?
    let existingEntryId: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
