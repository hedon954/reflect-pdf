use crate::domain::translation::{entity::TranslationResult, repository::Translator};
use crate::error::LumenError;
use crate::infrastructure::translator::http_client::shared_client;
use serde::Deserialize;

#[allow(unused)]
pub struct FallbackTranslator {
    target_lang: String,
}

impl FallbackTranslator {
    pub fn new(target_lang: String) -> Self {
        Self { target_lang }
    }

    fn lang_code(&self) -> &str {
        "zh"
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
        let word_url = format!(
            "https://api.mymemory.translated.net/get?q={}&langpair=en|{}",
            urlencoding::encode(word),
            self.lang_code(),
        );
        let sentence_tr_fut = Self::translate_chunk(sentence, self.lang_code());
        let word_resp_fut = shared_client().get(&word_url).send();

        // Fire both requests in parallel
        let (word_resp, sentence_tr) = tokio::join!(word_resp_fut, sentence_tr_fut);

        let resp = word_resp.map_err(|e| LumenError::FallbackApiError {
            message: e.to_string(),
        })?;

        if !resp.status().is_success() {
            return Err(LumenError::FallbackApiError {
                message: format!("HTTP {}", resp.status()),
            });
        }

        let data: MyMemoryResponse =
            resp.json()
                .await
                .map_err(|e| LumenError::FallbackApiError {
                    message: e.to_string(),
                })?;

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
    async fn translate_chunk(text: &str, lang: &str) -> String {
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
        let Ok(resp) = shared_client().get(&url).send().await else {
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
