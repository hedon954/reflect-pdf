#[derive(Debug, Clone, uniffi::Record)]
pub struct VocabularyEntry {
    pub id: String,
    pub word: String,
    pub sentence: String,
    pub sentence_hash: String,
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub selection_bounds: String,
    pub phonetic: String,
    pub part_of_speech: String,
    pub context_translation: String,
    pub context_explanation: String,
    pub general_definition: String,
    pub translation_source: String,
    pub annotation_id: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SaveVocabularyRequest {
    pub word: String,
    pub sentence: String,
    pub sentence_hash: String,
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub selection_bounds: String,
    pub phonetic: String,
    pub part_of_speech: String,
    pub context_translation: String,
    pub context_explanation: String,
    pub general_definition: String,
    pub translation_source: String,
    pub annotation_id: Option<String>,
}
