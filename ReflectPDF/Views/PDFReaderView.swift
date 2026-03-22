import SwiftUI
import PDFKit

// MARK: - Selection info for the action menu

struct SelectionInfo: Equatable {
    let word: String
    let sentence: String
    let bounds: CGRect
    let page: Int
}

struct PDFReaderView: View {
    let document: PdfDocument
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var translationRequest: TranslationBubbleRequest?
    @State private var isTranslating = false
    /// Pending selection waiting for user to choose action (translate / highlight / underline).
    @State private var pendingSelection: SelectionInfo?

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
                    // Show action menu instead of immediate translation
                    pendingSelection = SelectionInfo(word: word, sentence: sentence,
                                                    bounds: bounds, page: page)
                },
                onClearSelection: {
                    // Selection was cleared (click away) — dismiss pending menu
                    if translationRequest == nil {
                        pendingSelection = nil
                    }
                },
                onDocumentLoaded: { totalPages in
                    handleDocumentLoaded(totalPages: totalPages)
                }
            )

            // Selection action bar (translate / highlight / underline)
            if let sel = pendingSelection, translationRequest == nil {
                selectionActionBar(sel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(duration: 0.22), value: pendingSelection)
            }

            // Translation bubble
            if let req = translationRequest {
                TranslationBubble(
                    request: req,
                    isLoading: isTranslating,
                    onSave: { result in
                        saveToDiary(result: result, request: req)
                    },
                    onDelete: { deletedId in
                        // Remove the highlight annotation from the PDFView
                        NotificationCenter.default.post(
                            name: .removeHighlight,
                            object: nil,
                            userInfo: [
                                "entryId": deletedId,
                                "pageIndex": req.page,
                                "filePath": document.filePath
                            ]
                        )
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

    // MARK: - Selection Action Bar

    private func selectionActionBar(_ sel: SelectionInfo) -> some View {
        HStack(spacing: 0) {
            actionBarBtn(icon: "character.bubble", label: "翻译") {
                requestTranslation(word: sel.word, sentence: sel.sentence,
                                   bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 24)
            actionBarBtn(icon: "highlighter", label: "高亮") {
                postFreeAnnotation(type: "highlight", bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 24)
            actionBarBtn(icon: "underline", label: "划线") {
                postFreeAnnotation(type: "underline", bounds: sel.bounds, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 24)
            actionBarBtn(icon: "xmark", label: "") {
                pendingSelection = nil
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func actionBarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                if !label.isEmpty { Text(label).font(.callout) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func postFreeAnnotation(type: String, bounds: CGRect, page: Int) {
        NotificationCenter.default.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: [
                "annotationType": type,
                "pageIndex": page,
                "bounds": NSStringFromRect(bounds),
                "filePath": document.filePath
            ]
        )
    }

    // MARK: - Document loaded

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

    // MARK: - Translation

    private func requestTranslation(word: String, sentence: String, bounds: CGRect, page: Int) {
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

    // MARK: - Save to vocabulary

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
    let onClearSelection: () -> Void
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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.outlineNavigate(_:)),
            name: .outlineNavigate,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.jumpToPage(_:)),
            name: .jumpToPage,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.addHighlight(_:)),
            name: .addHighlight,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.removeHighlight(_:)),
            name: .removeHighlight,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.addFreeAnnotation(_:)),
            name: .addFreeAnnotation,
            object: nil
        )
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard pdfView.document?.documentURL?.path != filePath else { return }

        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        pdfView.document = doc
        context.coordinator.parent = self
        onDocumentLoaded(doc.pageCount)

        DispatchQueue.main.async {
            if self.savedPage > 0, self.savedPage < doc.pageCount,
               let page = doc.page(at: self.savedPage) {
                pdfView.go(to: page)
            }
        }

        context.coordinator.applyHighlights(to: doc, filePath: filePath)
    }

    /// Load a PDFDocument, falling back to a security-scoped bookmark if direct access fails.
    static func loadDocument(filePath: String) -> PDFDocument? {
        let url = URL(fileURLWithPath: filePath)
        if let doc = PDFDocument(url: url) { return doc }

        // Sandbox fallback: resolve saved security-scoped bookmark
        if let data = UserDefaults.standard.data(forKey: "bm_\(filePath)") {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                _ = resolved.startAccessingSecurityScopedResource()
                return PDFDocument(url: resolved)
            }
            // Non-security-scope fallback
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                return PDFDocument(url: resolved)
            }
        }
        return nil
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var debounceTimer: Timer?
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
            addVocabAnnotation(entryId: entryId, boundsStr: boundsStr, to: page)
        }

        @objc func removeHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  let pdfView,
                  pdfView.document?.documentURL?.path == filePath,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }
            if let ann = page.annotations.first(where: { $0.userName == entryId }) {
                page.removeAnnotation(ann)
            }
        }

        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr   = notification.userInfo?["annotationType"] as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]      as? Int,
                  let boundsStr = notification.userInfo?["bounds"]         as? String,
                  let filePath  = notification.userInfo?["filePath"]       as? String,
                  let pdfView,
                  pdfView.document?.documentURL?.path == filePath,
                  let page = pdfView.document?.page(at: pageIndex)
            else { return }

            let bounds = NSRectFromString(boundsStr)
            guard bounds != .zero else { return }

            let annType: PDFAnnotationSubtype = typeStr == "underline" ? .underline : .highlight
            let ann = PDFAnnotation(bounds: bounds, forType: annType, withProperties: nil)
            ann.color = typeStr == "underline"
                ? NSColor.systemBlue.withAlphaComponent(0.6)
                : NSColor.systemYellow.withAlphaComponent(0.5)
            page.addAnnotation(ann)
        }

        func applyHighlights(to doc: PDFDocument, filePath: String) {
            let entries = (try? BridgeService.shared.listVocabulary()) ?? []
            for entry in entries where entry.pdfPath == filePath {
                guard let page = doc.page(at: Int(entry.pageIndex)) else { continue }
                addVocabAnnotation(entryId: entry.id, boundsStr: entry.selectionBounds, to: page)
            }
        }

        private func addVocabAnnotation(entryId: String, boundsStr: String, to page: PDFPage) {
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
            guard let pdfView = notification.object as? PDFView else { return }

            guard let selection = pdfView.currentSelection,
                  let selectedString = selection.string,
                  !selectedString.isEmpty else {
                // Selection cleared — cancel debounce and notify parent
                debounceTimer?.invalidate()
                DispatchQueue.main.async {
                    self.parent.onClearSelection()
                }
                return
            }

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

// MARK: - Notification names

extension Notification.Name {
    static let addHighlight     = Notification.Name("addHighlight")
    static let removeHighlight  = Notification.Name("removeHighlight")
    static let addFreeAnnotation = Notification.Name("addFreeAnnotation")
}

// MARK: - Supporting types

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
