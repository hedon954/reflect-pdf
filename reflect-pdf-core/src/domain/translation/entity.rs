/// The source of a translation result.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum TranslationSource {
    Cache,
    Llm,
    Fallback,
}

impl TranslationSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            TranslationSource::Cache => "cache",
            TranslationSource::Llm => "llm",
            TranslationSource::Fallback => "fallback",
        }
    }
}

impl std::fmt::Display for TranslationSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl TryFrom<&str> for TranslationSource {
    type Error = ();
    fn try_from(s: &str) -> Result<Self, Self::Error> {
        match s {
            "cache" => Ok(TranslationSource::Cache),
            "llm" => Ok(TranslationSource::Llm),
            "fallback" => Ok(TranslationSource::Fallback),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TranslationRequest {
    pub word: String,
    pub sentence: String,
}

#[derive(Debug, Clone, Default, uniffi::Record, serde::Serialize, serde::Deserialize)]
pub struct TranslationResult {
    pub word: String,
    pub phonetic: String,
    pub part_of_speech: String,
    pub context_translation: String,
    pub context_explanation: String,
    pub general_definition: String,
    pub source: String,
}
