import Foundation

// File-scope type-aliased references to UniFFI top-level functions.
// BridgeService methods have the same names → would shadow them inside the class.
// By capturing them here at file scope, we can call them unambiguously.
private let _initialize: (String, AppConfig) throws -> Void              = initialize(dbPath:config:)
private let _updateLlmConfig: (AppConfig) throws -> Void                 = updateLlmConfig(config:)
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
private let _saveNote: (SaveNoteRequest) throws -> NoteEntry             = saveNote(req:)
private let _listNotes: () throws -> [NoteEntry]                         = listNotes
private let _listNotesByPdf: (String) throws -> [NoteEntry]              = listNotesByPdf(pdfPath:)
private let _deleteNote: (String) throws -> Void                         = deleteNote(id:)
private let _updateNote: (UpdateNoteRequest) throws -> NoteEntry         = updateNote(req:)
private let _exportNotesMarkdown: (String?) throws -> String             = exportNotesMarkdown(pdfPath:)

/// Wraps all UniFFI-generated top-level calls and manages app initialization.
final class BridgeService {
    static let shared = BridgeService()

    private var isInitialized = false
    private let dbURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LumenPDF", isDirectory: true)
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
        guard (try? _initialize(dbURL.path, config)) != nil else {
            // Do not flip isInitialized — allow retry on next launch / next call path.
            return
        }
        isInitialized = true
    }

    /// Hot-swap LLM config — takes effect for the very next translation call.
    func updateConfig(baseURL: String, apiKey: String, model: String, targetLanguage: String) {
        try? _updateLlmConfig(AppConfig(
            llmBaseUrl: baseURL,
            llmApiKey: apiKey,
            llmModel: model,
            targetLanguage: targetLanguage
        ))
    }

    // MARK: - Translation

    func translate(word: String, sentence: String) async throws -> TranslationResult {
        // translate(request:) has different param label — no shadowing conflict
        try await LumenPDF.translate(request: TranslationRequest(word: word, sentence: sentence))
    }

    /// Translate a full sentence without word-level analysis.
    /// Use this when the user selects a phrase/sentence instead of a single word.
    func translateSentence(sentence: String) async throws -> TranslationResult {
        try await LumenPDF.translateSentence(sentence: sentence)
    }

    /// Streaming word-level translation. `onPartial` fires repeatedly on
    /// `MainActor` while fields stream in; the returned `TranslationResult`
    /// is the final, complete result (also matching the last `onPartial`).
    func translateStreaming(
        word: String,
        sentence: String,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        let receiver = TranslationStreamReceiver(onPartial: onPartial)
        return try await LumenPDF.translateStreaming(
            request: TranslationRequest(word: word, sentence: sentence),
            callback: receiver
        )
    }

    /// Streaming sentence translation. `onPartial` fires as soon as any
    /// `context_sentence_translation` text is available.
    func translateSentenceStreaming(
        sentence: String,
        onPartial: @escaping @MainActor (TranslationResult) -> Void
    ) async throws -> TranslationResult {
        let receiver = TranslationStreamReceiver(onPartial: onPartial)
        return try await LumenPDF.translateSentenceStreaming(
            sentence: sentence,
            callback: receiver
        )
    }

    // MARK: - Vocabulary

    @discardableResult
    func saveVocabulary(
        word: String, sentence: String, sentenceHash: String,
        pdfPath: String, pdfName: String, pageIndex: UInt32,
        selectionBounds: String, phonetic: String, partOfSpeech: String,
        contextTranslation: String, contextExplanation: String,
        generalDefinition: String, contextSentenceTranslation: String,
        translationSource: String,
        annotationId: String? = nil
    ) throws -> VocabularyEntry {
        try _saveVocabulary(SaveVocabularyRequest(
            word: word, sentence: sentence, sentenceHash: sentenceHash,
            pdfPath: pdfPath, pdfName: pdfName, pageIndex: pageIndex,
            selectionBounds: selectionBounds, phonetic: phonetic,
            partOfSpeech: partOfSpeech, contextTranslation: contextTranslation,
            contextExplanation: contextExplanation, generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation,
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
                          generalDefinition: String, contextSentenceTranslation: String) throws -> VocabularyEntry {
        try _updateVocabulary(UpdateVocabularyRequest(
            id: id, phonetic: phonetic, partOfSpeech: partOfSpeech,
            contextTranslation: contextTranslation, contextExplanation: contextExplanation,
            generalDefinition: generalDefinition,
            contextSentenceTranslation: contextSentenceTranslation
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

    // MARK: - Notes

    @discardableResult
    func saveNote(
        pdfPath: String, pdfName: String, pageIndex: UInt32,
        content: String, note: String, boundsStr: String
    ) throws -> NoteEntry {
        try _saveNote(SaveNoteRequest(
            pdfPath: pdfPath,
            pdfName: pdfName,
            pageIndex: pageIndex,
            content: content,
            note: note,
            boundsStr: boundsStr
        ))
    }

    func listNotes() throws -> [NoteEntry] {
        try _listNotes()
    }

    func listNotesByPdf(pdfPath: String) throws -> [NoteEntry] {
        try _listNotesByPdf(pdfPath)
    }

    func deleteNote(id: String) throws {
        try _deleteNote(id)
    }

    @discardableResult
    func updateNote(id: String, note: String) throws -> NoteEntry {
        try _updateNote(UpdateNoteRequest(id: id, note: note))
    }

    func exportNotesMarkdown(pdfPath: String? = nil) -> String {
        (try? _exportNotesMarkdown(pdfPath)) ?? "# 笔记导出\n\n暂无笔记。"
    }
}

// MARK: - Streaming receiver

/// Adapter from UniFFI's `TranslationStreamCallback` protocol to a Swift
/// `@MainActor` closure. Rust may invoke `onProgress` on any thread (the
/// streaming consumer task), so we hop to `MainActor` before touching UI.
private final class TranslationStreamReceiver: TranslationStreamCallback {
    private let onPartial: @MainActor (TranslationResult) -> Void

    init(onPartial: @escaping @MainActor (TranslationResult) -> Void) {
        self.onPartial = onPartial
    }

    func onProgress(partial: TranslationResult) {
        let snapshot = partial
        Task { @MainActor in
            self.onPartial(snapshot)
        }
    }
}
