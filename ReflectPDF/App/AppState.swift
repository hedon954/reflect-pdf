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
        guard let doc = try? bridge.upsertPdfDocument(
            filePath: url.path,
            fileName: url.lastPathComponent,
            totalPages: 0
        ) else { return }
        selectedDocument = doc
        refreshLibrary()
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
        refreshLibrary()
    }

    // MARK: - Private

    private func loadKitDocument() {
        guard let filePath = selectedDocument?.filePath else {
            kitDocument = nil
            return
        }
        let url = URL(fileURLWithPath: filePath)
        kitDocument = PDFKit.PDFDocument(url: url)
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
