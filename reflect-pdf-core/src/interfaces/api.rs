use std::sync::{Arc, OnceLock};
use crate::error::ReflectError;
use crate::domain::translation::entity::{TranslationRequest, TranslationResult};
use crate::domain::vocabulary::entity::{VocabularyEntry, SaveVocabularyRequest};
use crate::domain::pdf_document::entity::{PdfDocument, UpsertPdfRequest};
use crate::application::translation::use_case::TranslationUseCase;
use crate::application::vocabulary::use_case::VocabularyUseCase;
use crate::application::pdf_document::use_case::PdfDocumentUseCase;
use crate::infrastructure::db::{self, DbPool};
use crate::infrastructure::db::{
    translation_cache_repo::SqliteTranslationCacheRepo,
    vocabulary_repo::SqliteVocabularyRepo,
    pdf_document_repo::SqlitePdfDocumentRepo,
};
use crate::infrastructure::translator::{
    llm_translator::{LlmTranslator, LlmConfig},
    fallback_translator::FallbackTranslator,
};

// ── Global state ────────────────────────────────────────────────────────────

static POOL: OnceLock<DbPool> = OnceLock::new();
static LLM_CONFIG: OnceLock<LlmConfig> = OnceLock::new();

/// Called once on app launch before any other API.
#[uniffi::export]
pub fn initialize(db_path: String, config: AppConfig) -> Result<(), ReflectError> {
    let pool = db::create_pool(&db_path)
        .map_err(|e| ReflectError::DatabaseError { message: e.to_string() })?;

    // Run migrations
    {
        let conn = pool.get()
            .map_err(|e| ReflectError::DatabaseError { message: e.to_string() })?;
        crate::infrastructure::db::migration::run(&conn)?;
    }

    POOL.set(pool).map_err(|_| ReflectError::DatabaseError {
        message: "Pool already initialized".to_string(),
    })?;

    LLM_CONFIG.set(LlmConfig {
        base_url: config.llm_base_url,
        api_key: config.llm_api_key,
        model: config.llm_model,
        target_language: config.target_language,
    }).map_err(|_| ReflectError::DatabaseError {
        message: "Config already initialized".to_string(),
    })?;

    Ok(())
}

fn pool() -> Result<&'static DbPool, ReflectError> {
    POOL.get().ok_or(ReflectError::ConfigNotInitialized)
}

fn llm_config() -> Result<&'static LlmConfig, ReflectError> {
    LLM_CONFIG.get().ok_or(ReflectError::ConfigNotInitialized)
}

// ── Config type ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, uniffi::Record)]
pub struct AppConfig {
    pub llm_base_url: String,
    pub llm_api_key: String,
    pub llm_model: String,
    pub target_language: String,
}

// ── Translation API ──────────────────────────────────────────────────────────

#[uniffi::export(async_runtime = "tokio")]
pub async fn translate(request: TranslationRequest) -> Result<TranslationResult, ReflectError> {
    let pool = pool()?;
    let config = llm_config()?;

    let cache = Arc::new(SqliteTranslationCacheRepo::new(pool.clone()));
    let llm = Arc::new(LlmTranslator::new(config.clone()));
    let fallback = Arc::new(FallbackTranslator::new(config.target_language.clone()));

    TranslationUseCase::new(cache, llm, fallback)
        .translate(request)
        .await
}

// ── Vocabulary API ───────────────────────────────────────────────────────────

#[uniffi::export]
pub fn save_vocabulary(req: SaveVocabularyRequest) -> Result<VocabularyEntry, ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .save(req)
}

#[uniffi::export]
pub fn get_vocabulary_entry(id: String) -> Result<Option<VocabularyEntry>, ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .get_by_id(&id)
}

#[uniffi::export]
pub fn get_vocabulary_by_word_and_hash(word: String, sentence_hash: String) -> Result<Option<VocabularyEntry>, ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .get_by_word_and_hash(&word, &sentence_hash)
}

#[uniffi::export]
pub fn list_vocabulary() -> Result<Vec<VocabularyEntry>, ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .list()
}

#[uniffi::export]
pub fn delete_vocabulary(id: String) -> Result<(), ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .delete(&id)
}

#[uniffi::export]
pub fn update_vocabulary_annotation(id: String, annotation_id: String) -> Result<(), ReflectError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .update_annotation_id(&id, &annotation_id)
}

// ── PDF Document API ─────────────────────────────────────────────────────────

#[uniffi::export]
pub fn upsert_pdf_document(req: UpsertPdfRequest) -> Result<PdfDocument, ReflectError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .upsert(req)
}

#[uniffi::export]
pub fn save_reading_position(file_path: String, page: u32, scroll_offset: f64) -> Result<(), ReflectError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .save_reading_position(&file_path, page, scroll_offset)
}

#[uniffi::export]
pub fn list_pdf_documents() -> Result<Vec<PdfDocument>, ReflectError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .list()
}

#[uniffi::export]
pub fn delete_pdf_document(file_path: String) -> Result<(), ReflectError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .delete(&file_path)
}
