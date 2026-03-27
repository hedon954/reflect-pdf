use std::sync::Arc;
use crate::error::LumenError;
use crate::domain::vocabulary::{
    entity::{VocabularyEntry, SaveVocabularyRequest, UpdateVocabularyRequest},
    repository::VocabularyRepository,
};

pub struct VocabularyUseCase {
    repo: Arc<dyn VocabularyRepository>,
}

impl VocabularyUseCase {
    pub fn new(repo: Arc<dyn VocabularyRepository>) -> Self {
        Self { repo }
    }

    pub fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
        self.repo.save(req)
    }

    pub fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, LumenError> {
        self.repo.get_by_id(id)
    }

    pub fn get_by_word_and_hash(&self, word: &str, sentence_hash: &str) -> Result<Option<VocabularyEntry>, LumenError> {
        self.repo.get_by_word_and_hash(word, sentence_hash)
    }

    pub fn list(&self) -> Result<Vec<VocabularyEntry>, LumenError> {
        self.repo.list()
    }

    pub fn delete(&self, id: &str) -> Result<(), LumenError> {
        self.repo.delete(id)
    }

    pub fn update_annotation_id(&self, id: &str, annotation_id: &str) -> Result<(), LumenError> {
        self.repo.update_annotation_id(id, annotation_id)
    }

    pub fn increment_query_count(&self, id: &str) -> Result<(), LumenError> {
        self.repo.increment_query_count(id)
    }

    pub fn update(&self, req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
        self.repo.update(req)
    }
}
