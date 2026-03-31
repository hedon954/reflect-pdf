import SwiftUI
import PDFKit
import AppKit

// MARK: - Selection info for the action menu

struct SelectionInfo: Equatable {
    let word: String
    let sentence: String
    /// Overall bounding box of the selection on the page (for menu anchor calculation only).
    let bounds: CGRect
    /// Pipe-separated per-line NSRect strings (e.g. "{x,y},{w,h}|{x,y},{w,h}").
    /// Using one rect per line avoids the large gap that spans between lines when a
    /// selection crosses a line break.  Backward-compatible: single-line selections
    /// produce a string with no `|`.
    let boundsStr: String
    let page: Int
    /// Center of the action menu in SwiftUI coordinates (relative to PDFKitView's frame).
    let menuAnchor: CGPoint

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.page == rhs.page && lhs.bounds == rhs.bounds
    }
}

struct PDFReaderView: View {
    let document: PdfDocument
    @EnvironmentObject private var appState: AppState
    @StateObject private var session = ReadingSessionService()

    @State private var translationRequest: TranslationBubbleRequest?
    @State private var isTranslating = false
    @State private var pendingSelection: SelectionInfo?
    // totalPages is kept as a local state for the initial load callback,
    // then written to appState so ContentView can display it in the toolbar.

    var body: some View {
        ZStack {
            PDFKitView(
                filePath: document.filePath,
                // Use AppState, not PdfDocument: the library snapshot is stale until refresh;
                // after minimize the representable may re-init and would otherwise restore the
                // page from the first open of this session.
                savedPage: appState.currentPageIndex,
                savedScrollOffset: appState.currentScrollOffset,
                onPageChange: { page, offset in
                    appState.saveReadingPosition(
                        filePath: document.filePath,
                        page: UInt32(page),
                        scrollOffset: offset
                    )
                },
                onTextSelected: { word, sentence, bounds, boundsStr, page, anchor in
                    guard !word.isEmpty else { return }
                    pendingSelection = SelectionInfo(
                        word: word, sentence: sentence,
                        bounds: bounds, boundsStr: boundsStr,
                        page: page, menuAnchor: anchor
                    )
                },
                onClearSelection: {
                    if translationRequest == nil { pendingSelection = nil }
                },
                onDocumentLoaded: { total in
                    handleDocumentLoaded(totalPages: total)
                }
            )

            // Selection action menu — positioned near the selection
            if let sel = pendingSelection, translationRequest == nil {
                selectionActionBar(sel)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    .animation(.spring(duration: 0.18), value: pendingSelection)
            }

            // Translation bubble
            if let req = translationRequest {
                TranslationBubble(
                    request: req,
                    isLoading: isTranslating,
                    onSave: { result in
                        if req.isSentenceMode {
                            saveSentenceToNote(result: result, request: req)
                        } else {
                            saveToDiary(result: result, request: req)
                        }
                    },
                    onDelete: { deletedId in
                        // Remove underline annotation if it was saved as a note
                        NotificationCenter.default.post(
                            name: .removeUnderlineNote,
                            object: nil,
                            userInfo: [
                                "noteId": deletedId,
                                "pageIndex": req.page,
                                "filePath": document.filePath
                            ]
                        )
                        // Also try to remove highlight (in case it was saved as vocabulary)
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
                        appState.refreshNotes()
                    },
                    onDismiss: { translationRequest = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .animation(.easeOut(duration: 0.15), value: translationRequest != nil)
            }
            // ⌘S — invisible button that flushes reading position immediately.
            // Must be inside the ZStack (not .background) to stay in the responder chain.
            Button("") {
                NotificationCenter.default.post(
                    name: .saveReadingPositionNow,
                    object: nil,
                    userInfo: ["filePath": document.filePath]
                )
            }
            .keyboardShortcut("s", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            // Forward Cmd+Z to the responder chain (PDFView undoManager) for annotation undo.
            Button("") {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            .keyboardShortcut("z", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .id(document.id)
    }

    // MARK: - Selection Action Bar

    private func selectionActionBar(_ sel: SelectionInfo) -> some View {
        HStack(spacing: 0) {
            actionBarBtn(icon: "character.bubble", label: "翻译") {
                requestTranslation(word: sel.word, sentence: sel.sentence,
                                   bounds: sel.bounds, boundsStr: sel.boundsStr,
                                   page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "highlighter", label: "高亮") {
                postFreeAnnotation(type: "highlight", boundsStr: sel.boundsStr, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "note.text", label: "划线") {
                saveUnderlineNote(word: sel.word, boundsStr: sel.boundsStr, page: sel.page)
                pendingSelection = nil
            }
            Divider().frame(height: 26)
            actionBarBtn(icon: "xmark", label: "") {
                pendingSelection = nil
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 3)
        .fixedSize()
        .position(x: sel.menuAnchor.x, y: sel.menuAnchor.y)
    }

    private func actionBarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                if !label.isEmpty {
                    Text(label).font(.system(size: 13))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func postFreeAnnotation(type: String, boundsStr: String, page: Int) {
        NotificationCenter.default.post(
            name: .addFreeAnnotation,
            object: nil,
            userInfo: [
                "annotationType": type,
                "pageIndex": page,
                "boundsStr": boundsStr,
                "filePath": document.filePath
            ]
        )
    }

    /// 划线并自动保存为笔记（支持 toggle：重复点击则删除）
    private func saveUnderlineNote(word: String, boundsStr: String, page: Int) {
        BridgeService.shared.initializeIfNeeded()

        // 先检查是否已存在相同选区的笔记（toggle 逻辑）
        if let existingNotes = try? BridgeService.shared.listNotesByPdf(pdfPath: document.filePath) {
            let matchingNote = existingNotes.first { note in
                note.pageIndex == UInt32(page) && note.boundsStr == boundsStr
            }
            if let match = matchingNote {
                // 已存在 → 删除笔记和划线
                try? BridgeService.shared.deleteNote(id: match.id)
                NotificationCenter.default.post(
                    name: .removeUnderlineNote,
                    object: nil,
                    userInfo: [
                        "noteId": match.id,
                        "pageIndex": page,
                        "filePath": document.filePath
                    ]
                )
                appState.refreshNotes()
                appState.showToast("已移除笔记")
                return
            }
        }

        // 不存在 → 保存新笔记
        guard let noteEntry = try? BridgeService.shared.saveNote(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(page),
            content: word,
            note: "",
            boundsStr: boundsStr
        ) else {
            appState.showToast("保存笔记失败")
            return
        }

        // 再添加划线，使用笔记 ID 作为 userName
        NotificationCenter.default.post(
            name: .addUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteEntry.id,
                "pageIndex": page,
                "boundsStr": boundsStr,
                "filePath": document.filePath
            ]
        )

        appState.refreshNotes()
        appState.showToast("已添加笔记")
    }

    // MARK: - Document loaded

    private func handleDocumentLoaded(totalPages: Int) {
        appState.totalPages = totalPages
        try? BridgeService.shared.upsertPdfDocument(
            filePath: document.filePath,
            fileName: document.fileName,
            totalPages: UInt32(totalPages)
        )
        appState.refreshLibrary()
        if appState.currentPageIndex > 0 {
            appState.showToast("已定位到 P\(appState.currentPageIndex + 1)")
        }
    }

    // MARK: - Translation

    private func requestTranslation(word: String, sentence: String,
                                     bounds: CGRect, boundsStr: String, page: Int) {
        BridgeService.shared.initializeIfNeeded()

        // Determine if this is sentence mode (multi-word selection)
        let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 25

        translationRequest = TranslationBubbleRequest(
            word: word, sentence: sentence,
            bounds: bounds, boundsStr: boundsStr,
            page: page, result: nil, translationError: nil,
            existingEntryId: nil,
            isSentenceMode: isSentenceMode
        )
        isTranslating = true

        Task {
            do {
                let result: TranslationResult
                if isSentenceMode {
                    // Sentence mode: translate the selection directly
                    result = try await BridgeService.shared.translateSentence(sentence: word)
                } else {
                    // Word mode: check for existing entry first
                    let hash = session.sentenceHash(sentence)
                    let existingEntry = try? BridgeService.shared.getVocabularyByWordAndHash(
                        word: word, sentenceHash: hash
                    )
                    if let e = existingEntry { BridgeService.shared.incrementQueryCount(id: e.id) }

                    // Update the request with existing entry ID
                    await MainActor.run {
                        if var req = translationRequest {
                            req.existingEntryId = existingEntry?.id
                            translationRequest = req
                        }
                    }

                    result = try await BridgeService.shared.translate(word: word, sentence: sentence)
                }

                await MainActor.run {
                    guard var req = translationRequest else { return }
                    req.result = result
                    req.translationError = nil
                    translationRequest = req
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    guard var req = translationRequest else { return }
                    var detail = TranslationErrorFormatter.userMessage(from: error)
                    if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detail = "翻译失败：\(String(describing: error))"
                    }
                    req.translationError = detail
                    translationRequest = req
                    isTranslating = false
                }
            }
        }
    }

    // MARK: - Save to vocabulary

    @discardableResult
    private func saveToDiary(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        let hash = session.sentenceHash(request.sentence)
        guard let entry = try? BridgeService.shared.saveVocabulary(
            word: result.word, sentence: request.sentence, sentenceHash: hash,
            pdfPath: document.filePath, pdfName: document.fileName,
            pageIndex: UInt32(request.page), selectionBounds: request.boundsStr,
            phonetic: result.phonetic, partOfSpeech: result.partOfSpeech,
            contextTranslation: result.contextTranslation,
            contextExplanation: result.contextExplanation,
            generalDefinition: result.generalDefinition,
            contextSentenceTranslation: result.contextSentenceTranslation,
            translationSource: result.source
        ) else { return nil }

        NotificationCenter.default.post(
            name: .addHighlight, object: nil,
            userInfo: [
                "entryId": entry.id, "pageIndex": Int(entry.pageIndex),
                "boundsStr": request.boundsStr, "filePath": document.filePath
            ]
        )
        appState.refreshVocabulary()
        appState.showToast("已保存「\(entry.word)」")
        return entry.id
    }

    // MARK: - Save sentence translation to notes

    @discardableResult
    private func saveSentenceToNote(result: TranslationResult, request: TranslationBubbleRequest) -> String? {
        BridgeService.shared.initializeIfNeeded()

        // Get translation text (prefer contextSentenceTranslation, fallback to contextTranslation)
        let translation = result.contextSentenceTranslation.isEmpty
            ? result.contextTranslation
            : result.contextSentenceTranslation

        guard let noteEntry = try? BridgeService.shared.saveNote(
            pdfPath: document.filePath,
            pdfName: document.fileName,
            pageIndex: UInt32(request.page),
            content: request.word,
            note: translation,
            boundsStr: request.boundsStr
        ) else {
            appState.showToast("保存笔记失败")
            return nil
        }

        // Add underline annotation linked to the note
        NotificationCenter.default.post(
            name: .addUnderlineNote,
            object: nil,
            userInfo: [
                "noteId": noteEntry.id,
                "pageIndex": request.page,
                "boundsStr": request.boundsStr,
                "filePath": document.filePath
            ]
        )

        appState.refreshNotes()
        appState.showToast("已保存到笔记")
        return noteEntry.id
    }
}

// MARK: - PDFKit NSViewRepresentable

struct PDFKitView: NSViewRepresentable {
    let filePath: String
    let savedPage: Int
    let savedScrollOffset: Double
    let onPageChange: (Int, Double) -> Void
    /// word, sentence, overallBounds, perLineBoundsStr, pageIndex, menuAnchor
    let onTextSelected: (String, String, CGRect, String, Int, CGPoint) -> Void
    let onClearSelection: () -> Void
    let onDocumentLoaded: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        let nc = NotificationCenter.default
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                       name: .PDFViewPageChanged, object: pdfView)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged(_:)),
                       name: .PDFViewSelectionChanged, object: pdfView)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.outlineNavigate(_:)),
                       name: .outlineNavigate, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.jumpToPage(_:)),
                       name: .jumpToPage, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addHighlight(_:)),
                       name: .addHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.removeHighlight(_:)),
                       name: .removeHighlight, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addFreeAnnotation(_:)),
                       name: .addFreeAnnotation, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.addUnderlineNote(_:)),
                       name: .addUnderlineNote, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.removeUnderlineNote(_:)),
                       name: .removeUnderlineNote, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.savePositionNow(_:)),
                       name: .saveReadingPositionNow, object: nil)
        // App-level: save on quit
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.appWillTerminate(_:)),
                       name: NSApplication.willTerminateNotification, object: nil)
        // Window-level: save before miniaturize, restore after deminiaturize.
        // object: nil = observe ANY window; the handler verifies it's our window.
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.windowWillMiniaturize(_:)),
                       name: NSWindow.willMiniaturizeNotification, object: nil)
        nc.addObserver(context.coordinator, selector: #selector(Coordinator.windowDidDeminiaturize(_:)),
                       name: NSWindow.didDeminiaturizeNotification, object: nil)

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        // Use coordinator's stored filePath (not documentURL?.path) because
        // Security-Scoped Bookmark-resolved URLs can differ from the original path.
        guard context.coordinator.currentFilePath != filePath else { return }
        guard let doc = Self.loadDocument(filePath: filePath) else { return }
        context.coordinator.parent = self
        context.coordinator.currentFilePath = filePath
        // Set BEFORE `document =` — assigning the document fires PDFViewPageChanged at page 0.
        // Without this, we would persist page 0 and reset TOC to the first chapter.
        context.coordinator.pendingRestoreTargetPage = savedPage
        context.coordinator.lastScrollOffset = savedScrollOffset
        context.coordinator.schedulePendingRestoreTimeout()
        pdfView.document = doc
        onDocumentLoaded(doc.pageCount)
        context.coordinator.lastKnownPageIndex = savedPage
        context.coordinator.applyHighlights(to: doc, filePath: filePath)
        DispatchQueue.main.async { [savedPage = self.savedPage, savedScroll = self.savedScrollOffset] in
            if savedPage > 0, savedPage < doc.pageCount,
               let page = doc.page(at: savedPage) {
                pdfView.go(to: page)
            }
            // Continuous mode: restore vertical scroll within the document after layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Coordinator.applyNormalizedScrollOffset(savedScroll, to: pdfView)
            }
        }

        // Re-attach the scroll observer to the new scroll view when the document changes.
        if let sv = pdfView.enclosingScrollView {
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.didLiveScroll(_:)),
                name: NSScrollView.didLiveScrollNotification,
                object: sv
            )
        }
    }

    /// Load a PDFDocument, with security-scoped bookmark fallback for sandboxed apps.
    static func loadDocument(filePath: String) -> PDFDocument? {
        let url = URL(fileURLWithPath: filePath)
        if let doc = PDFDocument(url: url) { return doc }
        if let data = UserDefaults.standard.data(forKey: "bm_\(filePath)") {
            var isStale = false
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                _ = resolved.startAccessingSecurityScopedResource()
                if let doc = PDFDocument(url: resolved) { return doc }
            }
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &isStale) {
                return PDFDocument(url: resolved)
            }
        }
        return nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        private var selectionDebounce: Timer?
        private var scrollDebounce: Timer?
        private var annotationSaveDebounce: Timer?
        var isJumping = false
        /// The file path of the currently loaded document.
        /// Stored explicitly so we never rely on `documentURL?.path`,
        /// which differs from the original path when loaded via a Security-Scoped Bookmark.
        var currentFilePath: String = ""
        /// Last page index the user was actually on — used to restore after window deminiaturize.
        var lastKnownPageIndex: Int = 0
        /// Normalized vertical scroll (0…1), kept in sync with saves.
        var lastScrollOffset: Double = 0
        /// While non-nil, ignore spurious `pageChanged` / scroll-save until we reach this page (document load).
        var pendingRestoreTargetPage: Int?
        private var pendingRestoreTimeoutWorkItem: DispatchWorkItem?

        init(_ parent: PDFKitView) {
            self.parent = parent
            self.lastKnownPageIndex = parent.savedPage
            self.lastScrollOffset = parent.savedScrollOffset
        }

        /// Trigger auto-save of annotations to PDF file (debounced)
        func triggerAnnotationSave() {
            annotationSaveDebounce?.invalidate()
            annotationSaveDebounce = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self, let pdfView = self.pdfView, let doc = pdfView.document else { return }
                Task {
                    await AnnotationPersistenceService.shared.saveAnnotations(
                        for: doc, filePath: self.currentFilePath
                    )
                }
            }
        }

        func schedulePendingRestoreTimeout() {
            pendingRestoreTimeoutWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingRestoreTargetPage = nil
            }
            pendingRestoreTimeoutWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        }

        /// Inverse of `scrollOffset(for:)` — restores vertical position in continuous scroll mode.
        static func applyNormalizedScrollOffset(_ normalized: Double, to pdfView: PDFView) {
            guard let sv = pdfView.enclosingScrollView, let dv = sv.documentView else { return }
            let h = dv.bounds.height
            guard h > 0 else { return }
            let y = CGFloat(max(0, min(1, normalized))) * h
            let visibleH = sv.documentVisibleRect.height
            let maxY = max(0, h - visibleH)
            sv.contentView.scroll(to: NSPoint(x: 0, y: min(y, maxY)))
        }

        // MARK: Outline / page navigation

        @objc func outlineNavigate(_ notification: Notification) {
            guard let idx   = notification.userInfo?["pageIndex"] as? Int,
                  let path  = notification.userInfo?["filePath"]  as? String,
                  path == currentFilePath,
                  let pdfView,
                  let page  = pdfView.document?.page(at: idx)
            else { return }
            pendingRestoreTargetPage = nil
            pendingRestoreTimeoutWorkItem?.cancel()
            pdfView.go(to: page)
        }

        // MARK: Vocab highlights

        @objc func addHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr = notification.userInfo?["boundsStr"]  as? String,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            addVocabAnnotation(entryId: entryId, boundsStr: boundsStr, to: page)
        }

        @objc func removeHighlight(_ notification: Notification) {
            guard let entryId   = notification.userInfo?["entryId"]   as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath  = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            page.annotations
                .filter { $0.userName == entryId }
                .forEach { page.removeAnnotation($0) }
        }

        // MARK: Free annotations (highlight / underline) with toggle + merge

        /// Snapshot for undo/redo of free-form highlight/underline (not vocabulary-linked).
        /// Subtype is derived from `tag` (`__fu` = underline, `__fh` = highlight).
        private struct FreeAnnotationSnapshot {
            let bounds: CGRect
            let color: NSColor
            let tag: String
            init(ann: PDFAnnotation) {
                bounds = ann.bounds
                color = (ann.color as NSColor?) ?? .yellow
                tag = ann.userName ?? ""
            }
            var subtype: PDFAnnotationSubtype {
                tag == "__fu" ? .underline : .highlight
            }
        }

        @objc func addFreeAnnotation(_ notification: Notification) {
            guard let typeStr   = notification.userInfo?["annotationType"] as? String,
                  let pageIndex = notification.userInfo?["pageIndex"]      as? Int,
                  let boundsStr = notification.userInfo?["boundsStr"]      as? String,
                  let filePath  = notification.userInfo?["filePath"]       as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }

            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard !lineRects.isEmpty else { return }

            let annType: PDFAnnotationSubtype = typeStr == "underline" ? .underline : .highlight
            let color: NSColor = typeStr == "underline"
                ? NSColor.systemRed
                : NSColor.systemYellow.withAlphaComponent(0.5)
            let tag = typeStr == "underline" ? "__fu" : "__fh"
            let undoLabel = typeStr == "underline" ? "划线" : "高亮"

            let selectionUnion = lineRects.dropFirst().reduce(lineRects[0]) { $0.union($1) }

            let existing = page.annotations.filter {
                $0.userName == tag && $0.bounds.intersects(selectionUnion)
            }

            var added: [PDFAnnotation] = []
            var removedSnapshots: [FreeAnnotationSnapshot] = []

            if existing.isEmpty {
                let contents = typeStr == "underline" ? "free:underline" : "free:highlight"
                for rect in lineRects {
                    added.append(Self.makeAnnotation(bounds: rect, type: annType, color: color, tag: tag, page: page, contents: contents))
                }
            } else {
                let existingUnion = existing.dropFirst().reduce(existing[0].bounds) { $0.union($1.bounds) }
                let isFullyCovered = lineRects.allSatisfy { existingUnion.contains($0) }
                removedSnapshots = existing.map { FreeAnnotationSnapshot(ann: $0) }
                existing.forEach { page.removeAnnotation($0) }
                if !isFullyCovered {
                    let contents = typeStr == "underline" ? "free:underline" : "free:highlight"
                    for rect in lineRects {
                        added.append(Self.makeAnnotation(bounds: rect, type: annType, color: color, tag: tag, page: page, contents: contents))
                    }
                }
            }

            if !added.isEmpty || !removedSnapshots.isEmpty {
                registerUndoAnnotationMutation(
                    page: page,
                    added: added,
                    removedSnapshots: removedSnapshots,
                    label: undoLabel
                )
                triggerAnnotationSave()
            }
        }

        private func registerUndoAnnotationMutation(
            page: PDFPage,
            added: [PDFAnnotation],
            removedSnapshots: [FreeAnnotationSnapshot],
            label: String
        ) {
            guard let undo = pdfView?.undoManager else { return }
            let addedSnaps = added.map { FreeAnnotationSnapshot(ann: $0) }

            undo.registerUndo(withTarget: self) { [weak self] _ in
                guard let self else { return }
                for ann in added {
                    page.removeAnnotation(ann)
                }
                var restored: [PDFAnnotation] = []
                for snap in removedSnapshots {
                    restored.append(Self.makeAnnotation(from: snap, page: page))
                }
                self.registerRedoAnnotationMutation(
                    page: page,
                    restoredRemoved: restored,
                    readdSnapshots: addedSnaps,
                    label: label
                )
            }
            if !undo.isUndoing {
                undo.setActionName(label)
            }
        }

        private func registerRedoAnnotationMutation(
            page: PDFPage,
            restoredRemoved: [PDFAnnotation],
            readdSnapshots: [FreeAnnotationSnapshot],
            label: String
        ) {
            guard let undo = pdfView?.undoManager else { return }
            let snapshotsOfRestored = restoredRemoved.map { FreeAnnotationSnapshot(ann: $0) }

            undo.registerUndo(withTarget: self) { [weak self] _ in
                guard let self else { return }
                for ann in restoredRemoved {
                    page.removeAnnotation(ann)
                }
                var readded: [PDFAnnotation] = []
                for snap in readdSnapshots {
                    readded.append(Self.makeAnnotation(from: snap, page: page))
                }
                self.registerUndoAnnotationMutation(
                    page: page,
                    added: readded,
                    removedSnapshots: snapshotsOfRestored,
                    label: label
                )
            }
            if !undo.isUndoing {
                undo.setActionName(label)
            }
        }

        private static func makeAnnotation(from snap: FreeAnnotationSnapshot, page: PDFPage) -> PDFAnnotation {
            let contents = snap.tag == "__fu" ? "free:underline" : "free:highlight"
            return makeAnnotation(bounds: snap.bounds, type: snap.subtype, color: snap.color, tag: snap.tag, page: page, contents: contents)
        }

        // MARK: Underline note (划线 + 笔记)

        /// 添加划线笔记（划线 + 自动保存到笔记）
        @objc func addUnderlineNote(_ notification: Notification) {
            guard let noteId     = notification.userInfo?["noteId"]     as? String,
                  let pageIndex  = notification.userInfo?["pageIndex"]  as? Int,
                  let boundsStr  = notification.userInfo?["boundsStr"]  as? String,
                  let filePath   = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page       = pdfView.document?.page(at: pageIndex)
            else { return }

            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard !lineRects.isEmpty else { return }

            // 使用笔记 ID 作为 userName，方便后续删除
            for rect in lineRects {
                let ann = PDFAnnotation(bounds: rect, forType: .underline, withProperties: nil)
                ann.color = NSColor.systemRed
                ann.userName = noteId
                ann.contents = "note:\(noteId)"
                page.addAnnotation(ann)
            }
            triggerAnnotationSave()
        }

        /// 删除划线笔记时移除对应的划线标注
        @objc func removeUnderlineNote(_ notification: Notification) {
            guard let noteId     = notification.userInfo?["noteId"]     as? String,
                  let pageIndex  = notification.userInfo?["pageIndex"]  as? Int,
                  let filePath   = notification.userInfo?["filePath"]   as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page       = pdfView.document?.page(at: pageIndex)
            else { return }

            // 移除所有使用该笔记 ID 的划线标注
            page.annotations
                .filter { $0.userName == noteId }
                .forEach { page.removeAnnotation($0) }
            triggerAnnotationSave()
        }

        // MARK: Apply saved highlights on document load

        func applyHighlights(to doc: PDFDocument, filePath: String) {
            let entries = (try? BridgeService.shared.listVocabulary()) ?? []
            for entry in entries where entry.pdfPath == filePath {
                guard let page = doc.page(at: Int(entry.pageIndex)) else { continue }
                addVocabAnnotation(entryId: entry.id, boundsStr: entry.selectionBounds, to: page)
            }
        }

        private func addVocabAnnotation(entryId: String, boundsStr: String, to page: PDFPage) {
            // Avoid duplicates
            guard !page.annotations.contains(where: { $0.userName == entryId }) else { return }
            let lineRects = Self.parseAnnotationRects(boundsStr)
            guard !lineRects.isEmpty else { return }
            for rect in lineRects {
                guard rect != .zero else { continue }
                let ann = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                ann.color = NSColor.systemYellow.withAlphaComponent(0.5)
                ann.userName = entryId
                ann.contents = "vocab:\(entryId)" // Persist to PDF metadata
                page.addAnnotation(ann)
            }
            triggerAnnotationSave()
        }

        // MARK: Page jump

        @objc func jumpToPage(_ notification: Notification) {
            guard let pageIndex = notification.userInfo?["pageIndex"] as? Int,
                  let filePath  = notification.userInfo?["filePath"]  as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let page      = pdfView.document?.page(at: pageIndex)
            else { return }
            pendingRestoreTargetPage = nil
            pendingRestoreTimeoutWorkItem?.cancel()
            isJumping = true
            pdfView.go(to: page)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.isJumping = false
            }
        }

        // MARK: Reading position save

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            let pageIndex = doc.index(for: currentPage)

            if let target = pendingRestoreTargetPage {
                if pageIndex != target { return }
                pendingRestoreTimeoutWorkItem?.cancel()
                pendingRestoreTargetPage = nil
                // Layout not updated yet — measured offset is ~0; keep DB scroll until `didLiveScroll`.
                lastKnownPageIndex = pageIndex
                parent.onPageChange(pageIndex, lastScrollOffset)
                return
            }

            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            parent.onPageChange(pageIndex, offset)
        }

        /// Debounced live-scroll handler — saves position ~0.5 s after scrolling stops.
        @objc func didLiveScroll(_ notification: Notification) {
            if pendingRestoreTargetPage != nil { return }
            scrollDebounce?.invalidate()
            scrollDebounce = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, let pdfView = self.pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let pageIndex = doc.index(for: currentPage)
                let offset = self.scrollOffset(for: pdfView)
                self.lastKnownPageIndex = pageIndex
                self.lastScrollOffset = offset
                self.parent.onPageChange(pageIndex, offset)
            }
        }

        /// Save position synchronously just before the window is minimized.
        @objc func windowWillMiniaturize(_ notification: Notification) {
            // Verify this notification belongs to the window that contains our PDFView.
            guard let notifWindow = notification.object as? NSWindow,
                  let pdfView, pdfView.window === notifWindow,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            let pageIndex = doc.index(for: currentPage)
            let offset = scrollOffset(for: pdfView)
            lastKnownPageIndex = pageIndex
            lastScrollOffset = offset
            try? BridgeService.shared.saveReadingPosition(
                filePath: currentFilePath,
                page: UInt32(pageIndex),
                scrollOffset: offset
            )
        }

        /// PDFKit resets scroll when a window is un-minimized; restore page + vertical offset.
        @objc func windowDidDeminiaturize(_ notification: Notification) {
            guard let notifWindow = notification.object as? NSWindow,
                  let pdfView, pdfView.window === notifWindow,
                  let page = pdfView.document?.page(at: lastKnownPageIndex) else { return }
            let offset = lastScrollOffset
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak pdfView] in
                guard let pdfView else { return }
                pdfView.go(to: page)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    Self.applyNormalizedScrollOffset(offset, to: pdfView)
                }
            }
            NotificationCenter.default.post(name: .windowDidDeminiaturize, object: nil)
        }

        /// Cmd+S — flush current position to SQLite immediately.
        @objc func savePositionNow(_ notification: Notification) {
            guard let filePath = notification.userInfo?["filePath"] as? String,
                  filePath == currentFilePath,
                  let pdfView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            let pageIndex = doc.index(for: currentPage)
            let offset = scrollOffset(for: pdfView)
            lastScrollOffset = offset
            parent.onPageChange(pageIndex, offset)
        }

        /// Called just before the app process terminates — saves position synchronously.
        @objc func appWillTerminate(_ notification: Notification) {
            guard let pdfView,
                  let currentPage = pdfView.currentPage,
                  let doc = pdfView.document else { return }
            scrollDebounce?.invalidate()
            let pageIndex = doc.index(for: currentPage)
            // Call directly on BridgeService to bypass any async dispatch
            try? BridgeService.shared.saveReadingPosition(
                filePath: currentFilePath,
                page: UInt32(pageIndex),
                scrollOffset: scrollOffset(for: pdfView)
            )
        }

        // MARK: Text selection

        @objc func selectionChanged(_ notification: Notification) {
            guard !isJumping else { return }
            guard let pdfView = notification.object as? PDFView else { return }

            guard let selection = pdfView.currentSelection,
                  let selectedStr = selection.string, !selectedStr.isEmpty else {
                selectionDebounce?.invalidate()
                DispatchQueue.main.async { self.parent.onClearSelection() }
                return
            }

            selectionDebounce?.invalidate()
            selectionDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self, weak pdfView] _ in
                guard let self, let pdfView,
                      let currentPage = pdfView.currentPage,
                      let doc = pdfView.document else { return }
                let word = selectedStr.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !word.isEmpty else { return }
                let sentence = self.extractSentence(from: pdfView, containing: selection) ?? word

                // Build per-line rects for precise annotation.
                let rawLines = selection.selectionsByLine()
                let lineSelections = rawLines.isEmpty ? [selection] : rawLines
                let lineRects = lineSelections.compactMap { s -> CGRect? in
                    let r = s.bounds(for: currentPage)
                    return r.isEmpty ? nil : r
                }
                let overallBounds = selection.bounds(for: currentPage)
                let boundsStr = lineRects.isEmpty
                    ? NSStringFromRect(overallBounds)
                    : lineRects.map { NSStringFromRect($0) }.joined(separator: "|")

                let pageIndex = doc.index(for: currentPage)
                let menuAnchor = Self.menuAnchor(boundsInPage: overallBounds,
                                                 page: currentPage, pdfView: pdfView)
                DispatchQueue.main.async {
                    self.parent.onTextSelected(word, sentence, overallBounds, boundsStr, pageIndex, menuAnchor)
                }
            }
        }

        /// Convert selection bounds (page coords) to a SwiftUI-space CGPoint for the action menu.
        private static func menuAnchor(boundsInPage: CGRect,
                                       page: PDFPage, pdfView: PDFView) -> CGPoint {
            let boundsInPDFView  = pdfView.convert(boundsInPage, from: page)
            let boundsInWindow   = pdfView.convert(boundsInPDFView, to: nil)
            let pdfFrameInWindow = pdfView.convert(pdfView.bounds, to: nil)

            let swiftUICenterX = boundsInWindow.midX - pdfFrameInWindow.minX
            let selTopSwiftUI   = pdfFrameInWindow.maxY - boundsInWindow.maxY

            let menuH: CGFloat = 40
            let menuY = max(selTopSwiftUI - 8 - menuH / 2, menuH / 2 + 4)
            let menuX = min(max(swiftUICenterX, 120), pdfView.bounds.width - 120)
            return CGPoint(x: menuX, y: menuY)
        }

        // MARK: Sentence extraction

        private func extractSentence(from pdfView: PDFView, containing selection: PDFSelection) -> String? {
            guard let page = pdfView.currentPage, let pageText = page.string,
                  !pageText.isEmpty else { return nil }
            let word = (selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = pageText as NSString
            let selRange = selection.range(at: 0, on: page)
            guard selRange.location != NSNotFound, selRange.length > 0 else {
                return fallbackSentence(word: word, in: pageText)
            }
            let anchor = min(selRange.location + max(0, selRange.length / 2), ns.length - 1)
            if let extracted = extractFullSentence(from: ns, anchorUTF16: anchor) {
                return extracted
            }
            return fallbackSentence(word: word, in: pageText)
        }

        private func extractFullSentence(from ns: NSString, anchorUTF16: Int) -> String? {
            let len = ns.length
            guard len > 0, anchorUTF16 >= 0, anchorUTF16 < len else { return nil }
            var start = anchorUTF16
            while start > 0 {
                let c = ns.character(at: start - 1)
                if isSentenceTerminatorUTF16(c) { break }
                start -= 1
            }
            var end = anchorUTF16
            while end < len {
                let c = ns.character(at: end)
                if isSentenceTerminatorUTF16(c) { end += 1; break }
                end += 1
            }
            let r = NSRange(location: start, length: end - start)
            let sentence = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.count >= 2, sentence.count <= 2000 { return sentence }
            return nil
        }

        private func isSentenceTerminatorUTF16(_ c: UInt16) -> Bool {
            switch c {
            case 0x002E, 0x0021, 0x003F: return true // . ! ?
            case 0x3002, 0xFF01, 0xFF1F: return true // 。！？
            default: return false
            }
        }

        private func fallbackSentence(word: String, in pageText: String) -> String? {
            guard !word.isEmpty else { return nil }
            let seps = CharacterSet(charactersIn: ".!?。！？")
            for part in pageText.components(separatedBy: seps) {
                let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.contains(word), t.count >= 4, t.count <= 2000 { return t }
            }
            return nil
        }

        // MARK: Scroll offset

        private func scrollOffset(for pdfView: PDFView) -> Double {
            guard let sv = pdfView.enclosingScrollView else { return 0 }
            let h = sv.documentView?.bounds.height ?? 1
            guard h > 0 else { return 0 }
            return max(0, min(1, sv.documentVisibleRect.minY / h))
        }

        // MARK: Helpers

        /// Parse a pipe-separated per-line bounds string back to CGRect array.
        /// Backward compatible: strings without `|` are treated as a single rect.
        static func parseAnnotationRects(_ boundsStr: String) -> [CGRect] {
            boundsStr.components(separatedBy: "|").compactMap { part -> CGRect? in
                let r = NSRectFromString(part)
                return r.isEmpty ? nil : r
            }
        }

        @discardableResult
        private static func makeAnnotation(bounds: CGRect, type: PDFAnnotationSubtype,
                                           color: NSColor, tag: String, page: PDFPage,
                                           contents: String? = nil) -> PDFAnnotation {
            let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
            ann.color = color
            ann.userName = tag
            if let contents = contents {
                ann.contents = contents
            }
            page.addAnnotation(ann)
            return ann
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let addHighlight           = Notification.Name("addHighlight")
    static let removeHighlight        = Notification.Name("removeHighlight")
    static let addFreeAnnotation      = Notification.Name("addFreeAnnotation")
    static let addUnderlineNote       = Notification.Name("addUnderlineNote")
    static let removeUnderlineNote    = Notification.Name("removeUnderlineNote")
    static let saveReadingPositionNow = Notification.Name("saveReadingPositionNow")
    static let windowDidDeminiaturize = Notification.Name("windowDidDeminiaturize")
}

// MARK: - Supporting types

struct TranslationBubbleRequest: Identifiable, Equatable {
    let id = UUID()
    let word: String
    let sentence: String
    let bounds: CGRect
    let boundsStr: String
    let page: Int
    var result: TranslationResult?
    /// Set when `translate` throws; shown at the bottom of the bubble.
    var translationError: String?
    var existingEntryId: String?
    /// When true, the selection is a multi-word phrase/sentence, not a single word.
    let isSentenceMode: Bool
    /// Must compare all fields that affect the bubble UI. Comparing only `id` made SwiftUI
    /// treat success/error updates as «unchanged» and skip redrawing — users saw「翻译未完成」
    /// with an empty detail area even when `translationError` was set.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.word == rhs.word
            && lhs.sentence == rhs.sentence
            && lhs.bounds == rhs.bounds
            && lhs.boundsStr == rhs.boundsStr
            && lhs.page == rhs.page
            && lhs.result == rhs.result
            && lhs.translationError == rhs.translationError
            && lhs.existingEntryId == rhs.existingEntryId
            && lhs.isSentenceMode == rhs.isSentenceMode
    }
}
