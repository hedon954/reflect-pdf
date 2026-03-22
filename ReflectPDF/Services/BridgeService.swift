import Foundation

/// Wraps all UniFFI-generated calls from ReflectPdfLib.
/// Swift types (TranslationResult etc.) mirror the Rust `#[uniffi::Record]` structs.
final class BridgeService {
    static let shared = BridgeService()

    private var isInitialized = false
    private let dbURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ReflectPDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("data.db")
    }

    func initializeIfNeeded() {
        guard !isInitialized else { return }
        let apiKey = KeychainService.load(key: "llm_api_key") ?? ""
        let config = AppConfig(
            llmBaseUrl: UserDefaults.standard.string(forKey: "llm_base_url") ?? "https://api.openai.com/v1",
            llmApiKey: apiKey,
            llmModel: UserDefaults.standard.string(forKey: "llm_model") ?? "gpt-4o-mini",
            targetLanguage: UserDefaults.standard.string(forKey: "target_language") ?? "简体中文"
        )
        try? initialize(dbPath: dbURL.path, config: config)
        isInitialized = true
    }

    func updateConfig(baseURL: String, apiKey: String, model: String, targetLanguage: String) {
        // Re-initialize with new config by restarting (simplest approach for MVP).
        // A production app would expose a dedicated update_config API.
        isInitialized = false
        initializeIfNeeded()
    }

    // MARK: - Translation

    func translate(word: String, sentence: String) async throws -> TranslationResult {
        try await ReflectPdfLib.translate(request: TranslationRequest(word: word, sentence: sentence))
    }

    // MARK: - Vocabulary

    @discardableResult
    func saveVocabulary(
        word: String, sentence: String, sentenceHash: String,
        pdfPath: String, pdfName: String, pageIndex: UInt32,
        selectionBounds: String, phonetic: String, partOfSpeech: String,
        contextTranslation: String, contextExplanation: String,
        generalDefinition: String, translationSource: String,
        annotationId: String? = nil
    ) throws -> VocabularyEntry {
        try ReflectPdfLib.saveVocabulary(req: SaveVocabularyRequest(
            word: word, sentence: sentence, sentenceHash: sentenceHash,
            pdfPath: pdfPath, pdfName: pdfName, pageIndex: pageIndex,
            selectionBounds: selectionBounds, phonetic: phonetic,
            partOfSpeech: partOfSpeech, contextTranslation: contextTranslation,
            contextExplanation: contextExplanation, generalDefinition: generalDefinition,
            translationSource: translationSource, annotationId: annotationId
        ))
    }

    func getVocabularyEntry(id: String) throws -> VocabularyEntry? {
        try ReflectPdfLib.getVocabularyEntry(id: id)
    }

    func getVocabularyByWordAndHash(word: String, sentenceHash: String) throws -> VocabularyEntry? {
        try ReflectPdfLib.getVocabularyByWordAndHash(word: word, sentenceHash: sentenceHash)
    }

    func listVocabulary() throws -> [VocabularyEntry] {
        try ReflectPdfLib.listVocabulary()
    }

    func deleteVocabulary(id: String) throws {
        try ReflectPdfLib.deleteVocabulary(id: id)
    }

    func updateVocabularyAnnotation(id: String, annotationId: String) throws {
        try ReflectPdfLib.updateVocabularyAnnotation(id: id, annotationId: annotationId)
    }

    // MARK: - PDF Documents

    @discardableResult
    func upsertPdfDocument(filePath: String, fileName: String, totalPages: UInt32) throws -> PdfDocument {
        try ReflectPdfLib.upsertPdfDocument(req: UpsertPdfRequest(
            filePath: filePath, fileName: fileName, totalPages: totalPages
        ))
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) throws {
        try ReflectPdfLib.saveReadingPosition(filePath: filePath, page: page, scrollOffset: scrollOffset)
    }

    func listPdfDocuments() throws -> [PdfDocument] {
        try ReflectPdfLib.listPdfDocuments()
    }

    func deletePdfDocument(filePath: String) throws {
        try ReflectPdfLib.deletePdfDocument(filePath: filePath)
    }
}
