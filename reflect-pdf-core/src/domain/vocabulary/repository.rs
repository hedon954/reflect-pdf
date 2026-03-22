use crate::error::ReflectError;
use super::entity::{VocabularyEntry, SaveVocabularyRequest, UpdateVocabularyRequest};

pub trait VocabularyRepository: Send + Sync {
    fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, ReflectError>;
    fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, ReflectError>;
    fn get_by_word_and_hash(&self, word: &str, sentence_hash: &str) -> Result<Option<VocabularyEntry>, ReflectError>;
    fn list(&self) -> Result<Vec<VocabularyEntry>, ReflectError>;
    fn delete(&self, id: &str) -> Result<(), ReflectError>;
    fn update_annotation_id(&self, id: &str, annotation_id: &str) -> Result<(), ReflectError>;
    fn increment_query_count(&self, id: &str) -> Result<(), ReflectError>;
    fn update(&self, req: UpdateVocabularyRequest) -> Result<VocabularyEntry, ReflectError>;
}
