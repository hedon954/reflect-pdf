import Foundation
import AppKit
import PDFKit
import Combine

enum MainTab { case reader, vocabulary }

@MainActor
final class AppState: ObservableObject {
    @Published var library: [PdfDocument] = []
    @Published var selectedDocument: PdfDocument? {
        didSet {
            // Persist last opened file path for auto-restore on launch
            if let path = selectedDocument?.filePath {
                UserDefaults.standard.set(path, forKey: "lastOpenedFilePath")
            }
            // Pre-set currentPageIndex from the stored lastPage so the TOC can
            // scroll to the correct chapter immediately, before the PDF finishes loading.
            if let doc = selectedDocument {
                currentPageIndex = Int(doc.lastPage)
                currentScrollOffset = doc.lastScrollOffset
                totalPages = Int(doc.totalPages)
            } else {
                currentPageIndex = 0
                currentScrollOffset = 0
                totalPages = 0
            }
            loadKitDocument()
        }
    }
    @Published var vocabulary: [VocabularyEntry] = []
    @Published var activeTab: MainTab = .reader
    @Published var toastMessage: String?

    /// PDFKit document object – used for TOC sidebar.
    @Published var kitDocument: PDFKit.PDFDocument?
    /// Current page index (0-based), updated on page change for TOC highlight.
    @Published var currentPageIndex: Int = 0
    /// Normalized vertical scroll (0…1), kept in sync with saves — must not use stale `PdfDocument` after scroll.
    @Published var currentScrollOffset: Double = 0
    /// Total page count of the currently open document (0 = unknown).
    @Published var totalPages: Int = 0

    private let bridge = BridgeService.shared

    init() {
        bridge.initializeIfNeeded()
        refreshLibrary()
        restoreLastDocument()
    }

    // MARK: - Library

    func refreshLibrary() {
        library = (try? bridge.listPdfDocuments()) ?? []
    }

    func refreshVocabulary() {
        vocabulary = (try? bridge.listVocabulary()) ?? []
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPDF(url: url)
    }

    func openPDF(url: URL) {
        // Save a security-scoped bookmark so we can re-open the file after app restart
        // (needed when the app runs in a macOS sandbox).
        saveBookmark(for: url)

        guard let doc = try? bridge.upsertPdfDocument(
            filePath: url.path,
            fileName: url.lastPathComponent,
            totalPages: 0
        ) else { return }
        selectedDocument = doc
        refreshLibrary()
    }

    private func saveBookmark(for url: URL) {
        // Try security-scoped bookmark first; fall back to plain bookmark.
        let data = (try? url.bookmarkData(options: .withSecurityScope,
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil))
                ?? (try? url.bookmarkData())
        if let data {
            UserDefaults.standard.set(data, forKey: "bm_\(url.path)")
        }
    }

    func removeFromLibrary(_ doc: PdfDocument) {
        try? bridge.deletePdfDocument(filePath: doc.filePath)
        if selectedDocument?.id == doc.id {
            selectedDocument = nil
            kitDocument = nil
        }
        refreshLibrary()
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) {
        try? bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
        currentPageIndex = Int(page)
        currentScrollOffset = scrollOffset
        // Do not refreshLibrary() here — it is expensive and can fight with PDF restore.
    }

    // MARK: - Private

    private func loadKitDocument() {
        guard let filePath = selectedDocument?.filePath else {
            kitDocument = nil
            return
        }
        kitDocument = PDFKitView.loadDocument(filePath: filePath)
    }

    private func restoreLastDocument() {
        guard let path = UserDefaults.standard.string(forKey: "lastOpenedFilePath"),
              let doc = library.first(where: { $0.filePath == path }) else { return }
        selectedDocument = doc
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.toastMessage = nil
        }
    }
}
