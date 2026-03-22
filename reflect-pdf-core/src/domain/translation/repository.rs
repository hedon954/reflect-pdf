use crate::error::ReflectError;
use super::entity::TranslationResult;

pub trait TranslationCacheRepository: Send + Sync {
    fn get(&self, word: &str, sentence_hash: &str) -> Result<Option<TranslationResult>, ReflectError>;
    fn set(&self, word: &str, sentence_hash: &str, result: &TranslationResult) -> Result<(), ReflectError>;
}

#[async_trait::async_trait]
pub trait Translator: Send + Sync {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, ReflectError>;
}
