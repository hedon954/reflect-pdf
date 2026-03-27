use reqwest::Client;
use serde::Deserialize;
use crate::domain::translation::{entity::TranslationResult, repository::Translator};
use crate::error::LumenError;

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
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, LumenError> {
        let url = format!(
            "https://api.mymemory.translated.net/get?q={}&langpair=en|{}",
            urlencoding::encode(word),
            self.lang_code(),
        );

        let resp = self.client
            .get(&url)
            .send()
            .await
            .map_err(|e| LumenError::FallbackApiError { message: e.to_string() })?;

        if !resp.status().is_success() {
            return Err(LumenError::FallbackApiError {
                message: format!("HTTP {}", resp.status()),
            });
        }

        let data: MyMemoryResponse = resp.json().await
            .map_err(|e| LumenError::FallbackApiError { message: e.to_string() })?;

        // Second call: full sentence translation (MyMemory ~500 char practical limit)
        let sentence_tr = Self::translate_chunk(&self.client, sentence, self.lang_code()).await;

        Ok(TranslationResult {
            word: word.to_string(),
            context_translation: data.response_data.translated_text.clone(),
            general_definition: data.response_data.translated_text,
            context_sentence_translation: sentence_tr,
            source: "fallback".to_string(),
            ..Default::default()
        })
    }
}

impl FallbackTranslator {
    async fn translate_chunk(client: &Client, text: &str, lang: &str) -> String {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return String::new();
        }
        let max = 480usize;
        let q: String = trimmed.chars().take(max).collect();
        let url = format!(
            "https://api.mymemory.translated.net/get?q={}&langpair=en|{}",
            urlencoding::encode(&q),
            lang,
        );
        let Ok(resp) = client.get(&url).send().await else {
            return String::new();
        };
        if !resp.status().is_success() {
            return String::new();
        }
        let Ok(data): Result<MyMemoryResponse, _> = resp.json().await else {
            return String::new();
        };
        data.response_data.translated_text
    }
}
