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

/// Streaming progress callback used by `Translator::translate_streaming`.
/// The closure is invoked once per newly-completed field and finally once
/// with the fully-populated result. Implementations must be cheap (forward
/// to a UI update) so they don't stall the streaming consumer loop.
pub type StreamProgress = Box<dyn FnMut(TranslationResult) + Send>;

#[async_trait::async_trait]
pub trait Translator: Send + Sync {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, LumenError>;

    /// Streaming variant of `translate`. Default implementation simply calls
    /// `translate` and emits a single update with the final result, so any
    /// non-streaming translator (e.g. the MyMemory fallback) automatically
    /// satisfies the streaming contract without extra code.
    async fn translate_streaming(
        &self,
        word: &str,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let result = self.translate(word, sentence).await?;
        on_progress(result.clone());
        Ok(result)
    }
}
