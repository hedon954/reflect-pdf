use reqwest::Client;
use serde::{Deserialize, Serialize};
use crate::domain::translation::{entity::TranslationResult, repository::Translator};
use crate::error::ReflectError;

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
            r#"You are a professional language tutor. Translate the word "{word}" in this context.

Context sentence: "{sentence}"

Respond with ONLY valid JSON in this exact format:
{{
  "word": "{word}",
  "phonetic": "IPA phonetic transcription",
  "part_of_speech": "noun/verb/adjective/etc",
  "context_translation": "Translation of the word in this specific context to {lang}",
  "context_explanation": "Why does it mean this here? Explain the nuance in {lang}",
  "general_definition": "General English definition"
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
}

#[async_trait::async_trait]
impl Translator for LlmTranslator {
    async fn translate(&self, word: &str, sentence: &str) -> Result<TranslationResult, ReflectError> {
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
            .map_err(|e| ReflectError::LlmApiError { message: e.to_string() })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(ReflectError::LlmApiError {
                message: format!("HTTP {status}: {text}"),
            });
        }

        let chat: ChatResponse = resp.json().await
            .map_err(|e| ReflectError::LlmApiError { message: e.to_string() })?;

        let content = chat.choices.into_iter().next()
            .map(|c| c.message.content)
            .unwrap_or_default();

        let parsed: LlmTranslationJson = serde_json::from_str(&content)
            .map_err(|e| ReflectError::SerializationError { message: e.to_string() })?;

        Ok(TranslationResult {
            word: parsed.word.unwrap_or_else(|| word.to_string()),
            phonetic: parsed.phonetic.unwrap_or_default(),
            part_of_speech: parsed.part_of_speech.unwrap_or_default(),
            context_translation: parsed.context_translation.unwrap_or_default(),
            context_explanation: parsed.context_explanation.unwrap_or_default(),
            general_definition: parsed.general_definition.unwrap_or_default(),
            source: "llm".to_string(),
        })
    }
}
