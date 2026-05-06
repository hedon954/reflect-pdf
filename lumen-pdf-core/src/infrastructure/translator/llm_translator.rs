use crate::domain::translation::{
    entity::{SentenceChunk, TranslationResult},
    repository::{StreamProgress, Translator},
};
use crate::error::LumenError;
use crate::infrastructure::translator::http_client::shared_client;
use crate::infrastructure::translator::streaming::{
    extract_complete_string_fields, extract_streaming_string_value, SseAccumulator,
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
            r#"You are a professional translator and language tutor. Translate the following English text to {lang} and, if it is a long or complex sentence, also break it down so the reader can understand each fragment.

Text: "{sentence}"

Rules:
1. Provide a natural, fluent translation in `translation`.
2. Preserve meaning and tone of the original; fix OCR errors / broken words if present.
3. Decide whether the sentence is "long or complex":
   - SHORT / SIMPLE (≤10 words, no clauses, plain SVO) → set `breakdown` to an empty array `[]`.
   - LONG / COMPLEX (multiple clauses, inversion, parallel structure, complex adverbials, etc.) → split it into 2–5 logical fragments.
4. For each fragment in `breakdown`, output an object with EXACTLY these fields:
   - `original`: the English fragment, copied verbatim from the source.
   - `translation`: that fragment's translation in {lang}.
   - `explanation`: in {lang}, briefly explain word choices / contextual meaning. ≤2 sentences.
   - `grammar`: ONLY fill this when the fragment contains a grammatically noteworthy structure (subordinate clause, inversion, subjunctive mood, parallel structure, participle clause, nested complex structures, etc.). Leave it as an EMPTY STRING for plain SVO fragments. Be concise — 1 to 3 sentences in {lang}, naming the structure and explaining its role.

Respond with ONLY valid JSON in this exact format:
{{
  "translation": "<full translation in {lang}>",
  "breakdown": [
    {{
      "original": "<English fragment>",
      "translation": "<{lang} translation of the fragment>",
      "explanation": "<{lang} explanation>",
      "grammar": "<{lang} grammar analysis OR empty string>"
    }}
  ]
}}"#,
            sentence = sentence,
            lang = self.config.target_language,
        )
    }

    /// Translate a full sentence without word-level analysis (non-streaming).
    /// Returns a `TranslationResult` with `context_sentence_translation` and
    /// (when applicable) `sentence_breakdown` filled in.
    pub async fn translate_sentence(
        &self,
        sentence: &str,
    ) -> Result<TranslationResult, LumenError> {
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

        let parsed: SentencePromptJson =
            serde_json::from_str(&content).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;

        Ok(parsed.into_result(sentence))
    }

    /// Streaming sentence translation.
    ///
    /// During the stream, `on_progress` is invoked **whenever a new character
    /// of the `translation` field arrives** — this gives the UI a real
    /// "watch the translation get written" effect (vs v1.0.4 which only
    /// emitted once the closing quote arrived).
    ///
    /// At end of stream, a strict JSON parse populates `sentence_breakdown`
    /// from the LLM response. The fully populated `TranslationResult` is
    /// returned and is also emitted as the final progress update.
    pub async fn translate_sentence_streaming(
        &self,
        sentence: &str,
        mut on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        let body = self.build_sentence_request(sentence, true);
        let url = self.completions_url();

        let raw_buf = self
            .stream_completion(&url, &body, |raw, last_emitted| {
                // Stream the `translation` field character by character. Other
                // fields (`breakdown`) only appear at the end and are handled
                // after the stream closes.
                let Some(current) = extract_streaming_string_value(raw, "translation") else {
                    return;
                };
                if current != *last_emitted {
                    *last_emitted = current.clone();
                    on_progress(TranslationResult {
                        word: sentence.to_string(),
                        context_sentence_translation: current,
                        source: "llm".to_string(),
                        ..Default::default()
                    });
                }
            })
            .await?;

        // Final, authoritative parse: the streaming extractor is permissive
        // (string-only). At end of stream we run a strict JSON parse so we
        // can extract `breakdown` and guarantee a clean final result.
        let parsed: SentencePromptJson =
            serde_json::from_str(&raw_buf).map_err(|e| LumenError::SerializationError {
                message: e.to_string(),
            })?;
        let final_result = parsed.into_result(sentence);
        // Emit a terminal progress event so the UI gets the breakdown without
        // having to wait for the outer caller to wire it.
        on_progress(final_result.clone());
        Ok(final_result)
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
        sentence_breakdown: Vec::new(),
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

/// Wire format the LLM produces in sentence mode: a translation plus an
/// optional breakdown array for long / complex sentences.
#[derive(Deserialize)]
struct SentencePromptJson {
    translation: Option<String>,
    #[serde(default)]
    breakdown: Vec<SentenceChunkJson>,
}

#[derive(Deserialize)]
struct SentenceChunkJson {
    original: Option<String>,
    translation: Option<String>,
    explanation: Option<String>,
    #[serde(default)]
    grammar: String,
}

impl SentencePromptJson {
    /// Materialize into a fully-populated `TranslationResult` for sentence
    /// mode. `original_sentence` is stored in `word` so callers can correlate
    /// the result with the user's selection (consistent with v1.0.4).
    fn into_result(self, original_sentence: &str) -> TranslationResult {
        let breakdown: Vec<SentenceChunk> = self
            .breakdown
            .into_iter()
            .map(|c| SentenceChunk {
                original: c.original.unwrap_or_default(),
                translation: c.translation.unwrap_or_default(),
                explanation: c.explanation.unwrap_or_default(),
                grammar: c.grammar,
            })
            // Drop entirely-empty chunks defensively in case the model emits
            // a stray `{}` placeholder when it decides not to break down.
            .filter(|c| !c.original.is_empty() || !c.translation.is_empty())
            .collect();

        TranslationResult {
            word: original_sentence.to_string(),
            context_sentence_translation: self.translation.unwrap_or_default(),
            source: "llm".to_string(),
            sentence_breakdown: breakdown,
            ..Default::default()
        }
    }
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
            sentence_breakdown: Vec::new(),
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
            sentence_breakdown: Vec::new(),
        })
    }
}
