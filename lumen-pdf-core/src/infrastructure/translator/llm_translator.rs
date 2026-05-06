use crate::domain::translation::{
    entity::TranslationResult,
    repository::{StreamProgress, Translator},
};
use crate::error::LumenError;
use crate::infrastructure::translator::http_client::shared_client;
use crate::infrastructure::translator::streaming::{
    extract_complete_string_fields, SseAccumulator,
};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone)]
pub struct LlmConfig {
    pub base_url: String,
    pub api_key: String,
    pub model: String,
    pub target_language: String,
}

pub struct LlmTranslator {
    config: LlmConfig,
}

impl LlmTranslator {
    pub fn new(config: LlmConfig) -> Self {
        Self { config }
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

    fn build_sentence_prompt(&self, sentence: &str) -> String {
        format!(
            r#"You are a professional translator. Translate the following English text to {lang}.

Text: "{sentence}"

Rules:
1. Provide a natural, fluent translation
2. Preserve the meaning and tone of the original
3. If the text contains OCR errors or broken words, fix them in your translation

Respond with ONLY valid JSON in this exact format:
{{
  "translation": "your translation here"
}}"#,
            sentence = sentence,
            lang = self.config.target_language,
        )
    }

    /// Translate a full sentence without word-level analysis (non-streaming).
    pub async fn translate_sentence(&self, sentence: &str) -> Result<String, LumenError> {
        let body = self.build_sentence_request(sentence, false);
        let url = self.completions_url();

        let resp = shared_client()
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .json(&body)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(LumenError::LlmApiError {
                message: format!("HTTP {status}: {text}"),
            });
        }

        let chat: ChatResponse = resp.json().await.map_err(|e| LumenError::LlmApiError {
            message: e.to_string(),
        })?;

        let content = chat
            .choices
            .into_iter()
            .next()
            .map(|c| c.message.content)
            .unwrap_or_default();

        #[derive(Deserialize)]
        struct SentenceTranslationJson {
            translation: Option<String>,
        }
        let parsed: SentenceTranslationJson =
            serde_json::from_str(&content).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;

        Ok(parsed.translation.unwrap_or_default())
    }

    /// Streaming sentence translation. The callback receives partial results
    /// as soon as the `translation` field has any complete content; the final
    /// `Ok` value contains the same string as the last emitted update.
    pub async fn translate_sentence_streaming(
        &self,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<String, LumenError> {
        let body = self.build_sentence_request(sentence, true);
        let url = self.completions_url();

        let raw_buf = self
            .stream_completion(&url, &body, |raw, last_emitted| {
                let fields = extract_complete_string_fields(raw);
                let mut map: HashMap<String, String> = HashMap::new();
                for (k, v) in fields {
                    map.insert(k, v);
                }
                let translation = map.remove("translation").unwrap_or_default();
                if !translation.is_empty() && translation != *last_emitted {
                    *last_emitted = translation.clone();
                    on_progress(TranslationResult {
                        word: sentence.to_string(),
                        context_sentence_translation: translation,
                        source: "llm".to_string(),
                        ..Default::default()
                    });
                }
            })
            .await?;

        // Final, authoritative parse: the streaming extractor is intentionally
        // permissive (string fields only). We still want a strict end-of-stream
        // parse so the caller gets a guaranteed-valid translation string.
        #[derive(Deserialize)]
        struct SentenceTranslationJson {
            translation: Option<String>,
        }
        let parsed: SentenceTranslationJson =
            serde_json::from_str(&raw_buf).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;
        Ok(parsed.translation.unwrap_or_default())
    }

    fn completions_url(&self) -> String {
        format!(
            "{}/chat/completions",
            self.config.base_url.trim_end_matches('/')
        )
    }

    fn build_sentence_request(&self, sentence: &str, stream: bool) -> ChatRequest {
        ChatRequest {
            model: self.config.model.clone(),
            stream,
            messages: vec![
                Message {
                    role: "system".into(),
                    content:
                        "You are a professional translator. Always respond with valid JSON only."
                            .into(),
                },
                Message {
                    role: "user".into(),
                    content: self.build_sentence_prompt(sentence),
                },
            ],
            response_format: ResponseFormat {
                kind: "json_object".into(),
            },
        }
    }

    /// Drive an OpenAI-compatible streaming completion: fire the request,
    /// consume the SSE byte stream, and call `on_chunk` after every UTF-8
    /// safe append to the accumulating raw JSON content. Returns the full
    /// accumulated content string when the stream completes.
    async fn stream_completion<F>(
        &self,
        url: &str,
        body: &ChatRequest,
        mut on_chunk: F,
    ) -> Result<String, LumenError>
    where
        F: FnMut(&str, &mut String),
    {
        let resp = shared_client()
            .post(url)
            .bearer_auth(&self.config.api_key)
            .json(body)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(LumenError::LlmApiError {
                message: format!("HTTP {status}: {text}"),
            });
        }

        let mut byte_buf: Vec<u8> = Vec::new();
        let mut content_buf = String::new();
        let mut sse = SseAccumulator::new();
        // `on_chunk` callbacks may want to track previously-emitted state
        // across invocations without owning their own state; expose a
        // mutable string scratch they can repurpose freely.
        let mut scratch = String::new();
        let mut stream = resp.bytes_stream();

        while let Some(item) = stream.next().await {
            let bytes = item.map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;
            byte_buf.extend_from_slice(&bytes);
            // Decode the longest valid-UTF-8 prefix; keep any trailing partial
            // multi-byte char in `byte_buf` for the next iteration so we never
            // emit replacement characters mid-stream.
            let valid_len = match std::str::from_utf8(&byte_buf) {
                Ok(s) => s.len(),
                Err(e) => e.valid_up_to(),
            };
            if valid_len == 0 {
                continue;
            }
            // SAFETY: valid_len is the result of `valid_up_to` (or full length
            // when fully valid), so the prefix slice is guaranteed valid UTF-8.
            let valid_str =
                unsafe { std::str::from_utf8_unchecked(&byte_buf[..valid_len]) }.to_string();
            byte_buf.drain(..valid_len);

            let outcome = sse.feed(&valid_str);
            if !outcome.content_deltas.is_empty() {
                content_buf.push_str(&outcome.content_deltas);
                on_chunk(&content_buf, &mut scratch);
            }
            if outcome.done {
                break;
            }
        }

        Ok(content_buf)
    }
}

fn map_to_translation_result(
    map: &HashMap<String, String>,
    fallback_word: &str,
) -> TranslationResult {
    TranslationResult {
        word: map
            .get("word")
            .cloned()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| fallback_word.to_string()),
        phonetic: map.get("phonetic").cloned().unwrap_or_default(),
        part_of_speech: map.get("part_of_speech").cloned().unwrap_or_default(),
        context_translation: map.get("context_translation").cloned().unwrap_or_default(),
        context_explanation: map.get("context_explanation").cloned().unwrap_or_default(),
        general_definition: map.get("general_definition").cloned().unwrap_or_default(),
        context_sentence_translation: map
            .get("context_sentence_translation")
            .cloned()
            .unwrap_or_default(),
        source: "llm".to_string(),
        llm_error_message: String::new(),
        fallback_error_message: String::new(),
        is_complete_failure: false,
    }
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<Message>,
    response_format: ResponseFormat,
    #[serde(skip_serializing_if = "is_false")]
    stream: bool,
}

fn is_false(b: &bool) -> bool {
    !*b
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
        let url = self.completions_url();
        let body = ChatRequest {
            model: self.config.model.clone(),
            stream: false,
            messages: vec![
                Message { role: "system".into(), content: "You are a professional language tutor. Always respond with valid JSON only.".into() },
                Message { role: "user".into(), content: self.build_prompt(word, sentence) },
            ],
            response_format: ResponseFormat { kind: "json_object".into() },
        };

        let resp = shared_client()
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .json(&body)
            .send()
            .await
            .map_err(|e| LumenError::LlmApiError {
                message: e.to_string(),
            })?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(LumenError::LlmApiError {
                message: format!("HTTP {status}: {text}"),
            });
        }

        let chat: ChatResponse = resp.json().await.map_err(|e| LumenError::LlmApiError {
            message: e.to_string(),
        })?;

        let content = chat
            .choices
            .into_iter()
            .next()
            .map(|c| c.message.content)
            .unwrap_or_default();

        let parsed: LlmTranslationJson =
            serde_json::from_str(&content).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;

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
            fallback_error_message: String::new(),
            is_complete_failure: false,
        })
    }

    async fn translate_streaming(
        &self,
        word: &str,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let url = self.completions_url();
        let body = ChatRequest {
            model: self.config.model.clone(),
            stream: true,
            messages: vec![
                Message {
                    role: "system".into(),
                    content:
                        "You are a professional language tutor. Always respond with valid JSON only."
                            .into(),
                },
                Message {
                    role: "user".into(),
                    content: self.build_prompt(word, sentence),
                },
            ],
            response_format: ResponseFormat {
                kind: "json_object".into(),
            },
        };

        let mut last_keys: Vec<String> = Vec::new();
        let raw_buf = self
            .stream_completion(&url, &body, |raw, _: &mut String| {
                let fields = extract_complete_string_fields(raw);
                if fields.is_empty() {
                    return;
                }
                // Later occurrences of the same key win — robust against any
                // gateway that emits the same field twice.
                let mut map: HashMap<String, String> = HashMap::new();
                let mut current_keys: Vec<String> = Vec::new();
                for (k, v) in fields {
                    if !current_keys.contains(&k) {
                        current_keys.push(k.clone());
                    }
                    map.insert(k, v);
                }
                // Re-emitting on every chunk would flood SwiftUI with redundant
                // diffs. Emitting only when the set of completed keys grows
                // strikes the right balance between responsiveness and noise.
                if current_keys.len() == last_keys.len() {
                    return;
                }
                last_keys = current_keys;
                on_progress(map_to_translation_result(&map, word));
            })
            .await?;

        // End-of-stream: strict parse so missing optional fields default to
        // empty strings via serde and we always return a complete result.
        let parsed: LlmTranslationJson =
            serde_json::from_str(&raw_buf).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;
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
            fallback_error_message: String::new(),
            is_complete_failure: false,
        })
    }
}
