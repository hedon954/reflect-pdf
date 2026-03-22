use reqwest::Client;
use serde::Deserialize;
use crate::domain::translation::{entity::TranslationResult, repository::Translator};
use crate::error::ReflectError;

pub struct FallbackTranslator {
    client: Client,
    target_lang: String,
}

impl FallbackTranslator {
    pub fn new(target_lang: String) -> Self {
        Self { client: Client::new(), target_lang }
    }

    fn lang_code(&self) -> &str {
        if self.target_lang.contains("中文") || self.target_lang.contains("Chinese") {
            "zh"
        } else {
            "zh"
        }
    }
}

#[derive(Deserialize)]
struct MyMemoryResponse {
    #[serde(rename = "responseData")]
    response_data: ResponseData,
}

#[derive(Deserialize)]
struct ResponseData {
    #[serde(rename = "translatedText")]
    translated_text: String,
}

#[async_trait::async_trait]
impl Translator for FallbackTranslator {
    async fn translate(&self, word: &str, _sentence: &str) -> Result<TranslationResult, ReflectError> {
        let url = format!(
            "https://api.mymemory.translated.net/get?q={}&langpair=en|{}",
            urlencoding::encode(word),
            self.lang_code(),
        );

        let resp = self.client
            .get(&url)
            .send()
            .await
            .map_err(|e| ReflectError::FallbackApiError { message: e.to_string() })?;

        if !resp.status().is_success() {
            return Err(ReflectError::FallbackApiError {
                message: format!("HTTP {}", resp.status()),
            });
        }

        let data: MyMemoryResponse = resp.json().await
            .map_err(|e| ReflectError::FallbackApiError { message: e.to_string() })?;

        Ok(TranslationResult {
            word: word.to_string(),
            context_translation: data.response_data.translated_text.clone(),
            general_definition: data.response_data.translated_text,
            source: "fallback".to_string(),
            ..Default::default()
        })
    }
}
