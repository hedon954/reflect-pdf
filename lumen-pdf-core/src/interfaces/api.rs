use crate::application::pdf_document::use_case::PdfDocumentUseCase;
use crate::application::translation::use_case::TranslationUseCase;
use crate::application::vocabulary::use_case::VocabularyUseCase;
use crate::domain::pdf_document::entity::{PdfDocument, UpsertPdfRequest};
use crate::domain::translation::entity::{TranslationRequest, TranslationResult};
use crate::domain::vocabulary::entity::{
    SaveVocabularyRequest, UpdateVocabularyRequest, VocabularyEntry,
};
use crate::error::LumenError;
use crate::infrastructure::db::{self, DbPool};
use crate::infrastructure::db::{
    pdf_document_repo::SqlitePdfDocumentRepo, translation_cache_repo::SqliteTranslationCacheRepo,
    vocabulary_repo::SqliteVocabularyRepo,
};
use crate::infrastructure::translator::{
    fallback_translator::FallbackTranslator,
    llm_translator::{LlmConfig, LlmTranslator},
};
use std::sync::{Arc, OnceLock, RwLock};

// ── Global state ────────────────────────────────────────────────────────────

static POOL: OnceLock<DbPool> = OnceLock::new();
// RwLock so the config can be hot-swapped without restarting the app.
static LLM_CONFIG: RwLock<Option<LlmConfig>> = RwLock::new(None);

/// Called once on app launch. Safe to call again — the DB pool is only created
/// once; calling again only updates the LLM config (useful for re-init after
/// settings change, though `update_llm_config` is preferred for that).
#[uniffi::export]
pub fn initialize(db_path: String, config: AppConfig) -> Result<(), LumenError> {
    // Pool: only create if not already initialised.
    if POOL.get().is_none() {
        let pool = db::create_pool(&db_path).map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;
        {
            let conn = pool.get().map_err(|e| LumenError::DatabaseError {
                message: e.to_string(),
            })?;
            crate::infrastructure::db::migration::run(&conn)?;
        }
        // Ignore error if another thread beat us to it.
        let _ = POOL.set(pool);
    }

    // Config: always write (allows subsequent calls to update settings).
    set_llm_config_inner(config)?;
    Ok(())
}

/// Hot-swap the LLM configuration without touching the DB pool.
/// Call this when the user saves new settings in the UI — takes effect
/// immediately for the next translation request.
#[uniffi::export]
pub fn update_llm_config(config: AppConfig) -> Result<(), LumenError> {
    set_llm_config_inner(config)
}

fn set_llm_config_inner(config: AppConfig) -> Result<(), LumenError> {
    let mut guard = LLM_CONFIG.write().map_err(|_| LumenError::DatabaseError {
        message: "LLM config lock poisoned".into(),
    })?;
    *guard = Some(LlmConfig {
        base_url: config.llm_base_url,
        api_key: config.llm_api_key,
        model: config.llm_model,
        target_language: config.target_language,
    });
    Ok(())
}

fn pool() -> Result<&'static DbPool, LumenError> {
    POOL.get().ok_or(LumenError::ConfigNotInitialized)
}

/// Returns a *clone* of the current LLM config (cheap — all fields are `String`).
fn llm_config() -> Result<LlmConfig, LumenError> {
    LLM_CONFIG
        .read()
        .map_err(|_| LumenError::ConfigNotInitialized)?
        .clone()
        .ok_or(LumenError::ConfigNotInitialized)
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
pub async fn translate(request: TranslationRequest) -> Result<TranslationResult, LumenError> {
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
pub fn save_vocabulary(req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone()))).save(req)
}

#[uniffi::export]
pub fn get_vocabulary_entry(id: String) -> Result<Option<VocabularyEntry>, LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone()))).get_by_id(&id)
}

#[uniffi::export]
pub fn get_vocabulary_by_word_and_hash(
    word: String,
    sentence_hash: String,
) -> Result<Option<VocabularyEntry>, LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .get_by_word_and_hash(&word, &sentence_hash)
}

#[uniffi::export]
pub fn list_vocabulary() -> Result<Vec<VocabularyEntry>, LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone()))).list()
}

#[uniffi::export]
pub fn delete_vocabulary(id: String) -> Result<(), LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone()))).delete(&id)
}

#[uniffi::export]
pub fn update_vocabulary_annotation(id: String, annotation_id: String) -> Result<(), LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .update_annotation_id(&id, &annotation_id)
}

#[uniffi::export]
pub fn increment_vocabulary_query_count(id: String) -> Result<(), LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone())))
        .increment_query_count(&id)
}

#[uniffi::export]
pub fn update_vocabulary(req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(pool()?.clone()))).update(req)
}

// ── PDF Document API ─────────────────────────────────────────────────────────

#[uniffi::export]
pub fn upsert_pdf_document(req: UpsertPdfRequest) -> Result<PdfDocument, LumenError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone()))).upsert(req)
}

#[uniffi::export]
pub fn save_reading_position(
    file_path: String,
    page: u32,
    scroll_offset: f64,
) -> Result<(), LumenError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .save_reading_position(&file_path, page, scroll_offset)
}

#[uniffi::export]
pub fn list_pdf_documents() -> Result<Vec<PdfDocument>, LumenError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone()))).list()
}

#[uniffi::export]
pub fn delete_pdf_document(file_path: String) -> Result<(), LumenError> {
    PdfDocumentUseCase::new(Arc::new(SqlitePdfDocumentRepo::new(pool()?.clone())))
        .delete(&file_path)
}
