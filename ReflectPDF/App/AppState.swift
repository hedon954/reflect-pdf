import Foundation
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var library: [PdfDocument] = []
    @Published var selectedDocument: PdfDocument?
    @Published var vocabulary: [VocabularyEntry] = []
    @Published var sidebarTab: SidebarTab = .library
    @Published var toastMessage: String?

    private var bridge = BridgeService.shared

    init() {
        bridge.initializeIfNeeded()
        refreshLibrary()
    }

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
        if selectedDocument?.id == doc.id { selectedDocument = nil }
        refreshLibrary()
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) {
        try? bridge.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
        refreshLibrary()
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.toastMessage = nil
        }
    }
}

enum SidebarTab {
    case library
    case vocabulary
}
