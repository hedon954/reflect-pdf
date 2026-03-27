use super::entity::{SaveVocabularyRequest, UpdateVocabularyRequest, VocabularyEntry};
use crate::error::LumenError;

pub trait VocabularyRepository: Send + Sync {
    fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError>;
    fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, LumenError>;
    fn get_by_word_and_hash(
        &self,
        word: &str,
        sentence_hash: &str,
    ) -> Result<Option<VocabularyEntry>, LumenError>;
    fn list(&self) -> Result<Vec<VocabularyEntry>, LumenError>;
    fn delete(&self, id: &str) -> Result<(), LumenError>;
    fn update_annotation_id(&self, id: &str, annotation_id: &str) -> Result<(), LumenError>;
    fn increment_query_count(&self, id: &str) -> Result<(), LumenError>;
    fn update(&self, req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError>;
}
