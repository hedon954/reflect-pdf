use std::sync::Arc;
use crate::error::ReflectError;
use crate::domain::vocabulary::{
    entity::{VocabularyEntry, SaveVocabularyRequest},
    repository::VocabularyRepository,
};

pub struct VocabularyUseCase {
    repo: Arc<dyn VocabularyRepository>,
}

impl VocabularyUseCase {
    pub fn new(repo: Arc<dyn VocabularyRepository>) -> Self {
        Self { repo }
    }

    pub fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, ReflectError> {
        self.repo.save(req)
    }

    pub fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, ReflectError> {
        self.repo.get_by_id(id)
    }

    pub fn get_by_word_and_hash(&self, word: &str, sentence_hash: &str) -> Result<Option<VocabularyEntry>, ReflectError> {
        self.repo.get_by_word_and_hash(word, sentence_hash)
    }

    pub fn list(&self) -> Result<Vec<VocabularyEntry>, ReflectError> {
        self.repo.list()
    }

    pub fn delete(&self, id: &str) -> Result<(), ReflectError> {
        self.repo.delete(id)
    }

    pub fn update_annotation_id(&self, id: &str, annotation_id: &str) -> Result<(), ReflectError> {
        self.repo.update_annotation_id(id, annotation_id)
    }
}
