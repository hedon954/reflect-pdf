use super::entity::TranslationResult;
use crate::error::LumenError;

pub trait TranslationCacheRepository: Send + Sync {
    fn get(&self, word: &str, sentence_hash: &str)
        -> Result<Option<TranslationResult>, LumenError>;
    fn set(
        &self,
        word: &str,
        sentence_hash: &str,
        result: &TranslationResult,
    ) -> Result<(), LumenError>;
}

#[async_trait::async_trait]
pub trait Translator: Send + Sync {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, LumenError>;
}
