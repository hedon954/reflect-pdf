use crate::domain::translation::{
    entity::{TranslationRequest, TranslationResult},
    repository::{StreamProgress, TranslationCacheRepository, Translator},
    service::TranslationDomainService,
};
use crate::error::LumenError;
use std::sync::Arc;

pub struct TranslationUseCase {
    service: TranslationDomainService,
}

impl TranslationUseCase {
    pub fn new(
        cache: Arc<dyn TranslationCacheRepository>,
        llm: Arc<dyn Translator>,
        fallback: Arc<dyn Translator>,
    ) -> Self {
        Self {
            service: TranslationDomainService::new(cache, llm, fallback),
        }
    }

    pub async fn translate(
        &self,
        request: TranslationRequest,
    ) -> Result<TranslationResult, LumenError> {
        self.service.translate(request).await
    }

    pub async fn translate_streaming(
        &self,
        request: TranslationRequest,
        on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        self.service.translate_streaming(request, on_progress).await
    }
}
