use reqwest::Client;
use serde::{Deserialize, Serialize};
use crate::domain::translation::{entity::TranslationResult, repository::Translator};
use crate::error::LumenError;

#[derive(Clone)]
pub struct LlmConfig {
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub target_language: String,
}

pub struct LlmTranslator {
    client: Client,
    config: LlmConfig,
}

impl LlmTranslator {
    pub fn new(config: LlmConfig) -> Self {
        Self { client: Client::new(), config }
    }

    fn build_prompt(&self, word: &str, sentence: &str) -> String {
        format!(
            r#"You are a professional language tutor. The user selected the word "{word}" while reading a PDF.

Context sentence: "{sentence}"

IMPORTANT: The selected text may contain OCR errors, line-break hyphens (e.g. "investi-\ngating"), or extra whitespace due to PDF extraction. In the "word" field, output the correctly spelled, properly joined word.

Respond with ONLY valid JSON in this exact format:
{{
  "word": "correctly spelled word (fix any hyphenation, OCR errors, or typos from PDF extraction)",
  "phonetic": "IPA phonetic transcription",
  "part_of_speech": "noun/verb/adjective/adverb/etc",
  "context_translation": "Translation of the word in this specific context to {lang}",
  "context_explanation": "Why does it mean this here? Explain the nuance in {lang}",
  "general_definition": "General English definition of the word",
  "context_sentence_translation": "Full translation of the ENTIRE context sentence above to {lang} (not just the word)"
}}"#,
            word = word,
            sentence = sentence,
            lang = self.config.target_language,
        )
    }
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    response_format: ResponseFormat,
}

#[derive(Serialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Serialize)]
struct ResponseFormat {
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<Choice>,
}

#[derive(Deserialize)]
struct Choice {
    message: MessageContent,
}

#[derive(Deserialize)]
struct MessageContent {
    content: String,
}

#[derive(Deserialize)]
struct LlmTranslationJson {
    word: Option<String>,
    phonetic: Option<String>,
    part_of_speech: Option<String>,
    context_translation: Option<String>,
    context_explanation: Option<String>,
    general_definition: Option<String>,
    context_sentence_translation: Option<String>,
}

#[async_trait::async_trait]
impl Translator for LlmTranslator {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, LumenError> {
        let url = format!("{}/chat/completions", self.config.base_url.trim_end_matches('/'));
        let body = ChatRequest {
            model: self.config.model.clone(),
            messages: vec![
                Message { role: "system".into(), content: "You are a professional language tutor. Always respond with valid JSON only.".into() },
                Message { role: "user".into(), content: self.build_prompt(word, sentence) },
            ],
            response_format: ResponseFormat { kind: "json_object".into() },
        };

        let resp = self.client
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .json(&body)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError { message: e.to_string() })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(LumenError::LlmApiError {
                message: format!("HTTP {status}: {text}"),
            });
        }

        let chat: ChatResponse = resp.json().await
            .map_err(|e| LumenError::LlmApiError { message: e.to_string() })?;

        let content = chat.choices.into_iter().next()
            .map(|c| c.message.content)
            .unwrap_or_default();

        let parsed: LlmTranslationJson = serde_json::from_str(&content)
            .map_err(|e| LumenError::SerializationError { message: e.to_string() })?;

        Ok(TranslationResult {
            word: parsed.word.unwrap_or_else(|| word.to_string()),
            phonetic: parsed.phonetic.unwrap_or_default(),
            part_of_speech: parsed.part_of_speech.unwrap_or_default(),
            context_translation: parsed.context_translation.unwrap_or_default(),
            context_explanation: parsed.context_explanation.unwrap_or_default(),
            general_definition: parsed.general_definition.unwrap_or_default(),
            context_sentence_translation: parsed.context_sentence_translation.unwrap_or_default(),
            source: "llm".to_string(),
            llm_error_message: String::new(),
        })
    }
}
