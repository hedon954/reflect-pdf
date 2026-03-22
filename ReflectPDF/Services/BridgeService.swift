import Foundation

// File-scope type-aliased references to UniFFI top-level functions.
// BridgeService methods have the same names → would shadow them inside the class.
// By capturing them here at file scope, we can call them unambiguously.
private let _initialize: (String, AppConfig) throws -> Void              = initialize(dbPath:config:)
private let _saveVocabulary: (SaveVocabularyRequest) throws -> VocabularyEntry = saveVocabulary(req:)
private let _getVocabularyEntry: (String) throws -> VocabularyEntry?     = getVocabularyEntry(id:)
private let _getVocabByHash: (String, String) throws -> VocabularyEntry? = getVocabularyByWordAndHash(word:sentenceHash:)
private let _listVocabulary: () throws -> [VocabularyEntry]              = listVocabulary
private let _deleteVocabulary: (String) throws -> Void                   = deleteVocabulary(id:)
private let _updateAnnotation: (String, String) throws -> Void           = updateVocabularyAnnotation(id:annotationId:)
private let _incrementQueryCount: (String) throws -> Void                = incrementVocabularyQueryCount(id:)
private let _updateVocabulary: (UpdateVocabularyRequest) throws -> VocabularyEntry = updateVocabulary(req:)
private let _upsertPdf: (UpsertPdfRequest) throws -> PdfDocument         = upsertPdfDocument(req:)
private let _savePosition: (String, UInt32, Double) throws -> Void       = saveReadingPosition(filePath:page:scrollOffset:)
private let _listPdfDocuments: () throws -> [PdfDocument]                = listPdfDocuments
private let _deletePdfDocument: (String) throws -> Void                  = deletePdfDocument(filePath:)

/// Wraps all UniFFI-generated top-level calls and manages app initialization.
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
        let config = AppConfig(
            llmBaseUrl: UserDefaults.standard.string(forKey: "llm_base_url") ?? "https://api.openai.com/v1",
            llmApiKey: KeychainService.load(key: "llm_api_key") ?? "",
            llmModel: UserDefaults.standard.string(forKey: "llm_model") ?? "gpt-4o-mini",
            targetLanguage: UserDefaults.standard.string(forKey: "target_language") ?? "简体中文"
        )
        try? _initialize(dbURL.path, config)
        isInitialized = true
    }

    func updateConfig(baseURL: String, apiKey: String, model: String, targetLanguage: String) {
        isInitialized = false
        initializeIfNeeded()
    }

    // MARK: - Translation

    func translate(word: String, sentence: String) async throws -> TranslationResult {
        // translate(request:) has different param label — no shadowing conflict
        try await ReflectPDF.translate(request: TranslationRequest(word: word, sentence: sentence))
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
        try _saveVocabulary(SaveVocabularyRequest(
            word: word, sentence: sentence, sentenceHash: sentenceHash,
            pdfPath: pdfPath, pdfName: pdfName, pageIndex: pageIndex,
            selectionBounds: selectionBounds, phonetic: phonetic,
            partOfSpeech: partOfSpeech, contextTranslation: contextTranslation,
            contextExplanation: contextExplanation, generalDefinition: generalDefinition,
            translationSource: translationSource, annotationId: annotationId
        ))
    }

    func getVocabularyEntry(id: String) throws -> VocabularyEntry? {
        try _getVocabularyEntry(id)
    }

    func getVocabularyByWordAndHash(word: String, sentenceHash: String) throws -> VocabularyEntry? {
        try _getVocabByHash(word, sentenceHash)
    }

    func listVocabulary() throws -> [VocabularyEntry] {
        try _listVocabulary()
    }

    func deleteVocabulary(id: String) throws {
        try _deleteVocabulary(id)
    }

    func updateVocabularyAnnotation(id: String, annotationId: String) throws {
        try _updateAnnotation(id, annotationId)
    }

    func incrementQueryCount(id: String) {
        try? _incrementQueryCount(id)
    }

    @discardableResult
    func updateVocabulary(id: String, phonetic: String, partOfSpeech: String,
                          contextTranslation: String, contextExplanation: String,
                          generalDefinition: String) throws -> VocabularyEntry {
        try _updateVocabulary(UpdateVocabularyRequest(
            id: id, phonetic: phonetic, partOfSpeech: partOfSpeech,
            contextTranslation: contextTranslation, contextExplanation: contextExplanation,
            generalDefinition: generalDefinition
        ))
    }

    // MARK: - PDF Documents

    @discardableResult
    func upsertPdfDocument(filePath: String, fileName: String, totalPages: UInt32) throws -> PdfDocument {
        try _upsertPdf(UpsertPdfRequest(filePath: filePath, fileName: fileName, totalPages: totalPages))
    }

    func saveReadingPosition(filePath: String, page: UInt32, scrollOffset: Double) throws {
        try _savePosition(filePath, page, scrollOffset)
    }

    func listPdfDocuments() throws -> [PdfDocument] {
        try _listPdfDocuments()
    }

    func deletePdfDocument(filePath: String) throws {
        try _deletePdfDocument(filePath)
    }
}
