use std::sync::Arc;
use sha2::{Sha256, Digest};
use crate::error::LumenError;
use super::{
    entity::{TranslationRequest, TranslationResult, TranslationSource},
    repository::{TranslationCacheRepository, Translator},
};

pub struct TranslationDomainService {
    cache: Arc<dyn TranslationCacheRepository>,
    llm: Arc<dyn Translator>,
    fallback: Arc<dyn Translator>,
}

impl TranslationDomainService {
    pub fn new(
        cache: Arc<dyn TranslationCacheRepository>,
        llm: Arc<dyn Translator>,
        fallback: Arc<dyn Translator>,
    ) -> Self {
        Self { cache, llm, fallback }
    }

    pub fn sentence_hash(sentence: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(sentence.to_lowercase().as_bytes());
        hex::encode(hasher.finalize())
    }

    pub async fn translate(&self, request: TranslationRequest) -> Result<TranslationResult, LumenError> {
        let word_lower = request.word.to_lowercase();
        let hash = Self::sentence_hash(&request.sentence);

        // Level 1: local cache
        if let Some(mut cached) = self.cache.get(&word_lower, &hash)? {
            cached.source = TranslationSource::Cache.to_string();
            return Ok(cached);
        }

        // Level 2: LLM
        let llm_failure_note: Option<String> = match self.llm.translate(&request.word, &request.sentence).await {
            Ok(mut result) => {
                result.source = TranslationSource::Llm.to_string();
                result.llm_error_message = String::new();
                let _ = self.cache.set(&word_lower, &hash, &result);
                return Ok(result);
            }
            Err(e) => Some(e.user_hint_zh()),
        };

        // Level 3: fallback (MyMemory), not cached
        let mut result = self.fallback.translate(&request.word, &request.sentence).await?;
        result.source = TranslationSource::Fallback.to_string();
        if let Some(msg) = llm_failure_note {
            result.llm_error_message = msg;
        }
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use std::collections::HashMap;

    struct FakeCache(Mutex<HashMap<String, TranslationResult>>);

    impl FakeCache {
        fn new() -> Arc<Self> {
            Arc::new(Self(Mutex::new(HashMap::new())))
        }
    }

    impl TranslationCacheRepository for FakeCache {
        fn get(&self, word: &str, hash: &str) -> Result<Option<TranslationResult>, LumenError> {
            Ok(self.0.lock().unwrap().get(&format!("{word}:{hash}")).cloned())
        }
        fn set(&self, word: &str, hash: &str, r: &TranslationResult) -> Result<(), LumenError> {
            self.0.lock().unwrap().insert(format!("{word}:{hash}"), r.clone());
            Ok(())
        }
    }

    struct FakeLlm { word_result: &'static str }

    #[async_trait::async_trait]
    impl Translator for FakeLlm {
        async fn translate(&self, word: &str, _sentence: &str) -> Result<TranslationResult, LumenError> {
            Ok(TranslationResult {
                word: word.to_string(),
                general_definition: self.word_result.to_string(),
                ..Default::default()
            })
        }
    }

    struct FailingLlm;

    #[async_trait::async_trait]
    impl Translator for FailingLlm {
        async fn translate(&self, _word: &str, _sentence: &str) -> Result<TranslationResult, LumenError> {
            Err(LumenError::LlmApiError { message: "timeout".to_string() })
        }
    }

    struct FakeFallback;

    #[async_trait::async_trait]
    impl Translator for FakeFallback {
        async fn translate(&self, word: &str, _sentence: &str) -> Result<TranslationResult, LumenError> {
            Ok(TranslationResult {
                word: word.to_string(),
                general_definition: "fallback result".to_string(),
                ..Default::default()
            })
        }
    }

    #[tokio::test]
    async fn cache_hit_skips_llm() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        cache.set("run", &hash, &TranslationResult {
            word: "run".to_string(),
            general_definition: "cached".to_string(),
            ..Default::default()
        }).unwrap();

        let svc = TranslationDomainService::new(
            cache,
            Arc::new(FailingLlm),
            Arc::new(FailingLlm),
        );

        let result = svc.translate(TranslationRequest {
            word: "run".to_string(),
            sentence: "the quick brown fox".to_string(),
        }).await.unwrap();

        assert_eq!(result.source, "cache");
        assert_eq!(result.general_definition, "cached");
    }

    #[tokio::test]
    async fn successful_llm_result_is_cached() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FakeLlm { word_result: "llm def" }),
            Arc::new(FailingLlm),
        );

        let result = svc.translate(TranslationRequest {
            word: "run".to_string(),
            sentence: "the quick brown fox".to_string(),
        }).await.unwrap();

        assert_eq!(result.source, "llm");
        assert_eq!(result.general_definition, "llm def");

        // Verify it was written to cache
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        let cached = cache.get("run", &hash).unwrap();
        assert!(cached.is_some());
    }

    #[tokio::test]
    async fn llm_failure_falls_back_and_does_not_cache() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FailingLlm),
            Arc::new(FakeFallback),
        );

        let result = svc.translate(TranslationRequest {
            word: "run".to_string(),
            sentence: "the quick brown fox".to_string(),
        }).await.unwrap();

        assert_eq!(result.source, "fallback");
        assert!(
            result.llm_error_message.contains("LLM"),
            "expected LLM failure note when falling back, got {:?}",
            result.llm_error_message
        );

        // Fallback result must not be cached
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        let cached = cache.get("run", &hash).unwrap();
        assert!(cached.is_none());
    }
}
