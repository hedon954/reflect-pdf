use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum ReflectError {
    #[error("Config not initialized — call initialize() first")]
    ConfigNotInitialized,

    #[error("Database error: {message}")]
    DatabaseError { message: String },

    #[error("LLM API error: {message}")]
    LlmApiError { message: String },

    #[error("Fallback API error: {message}")]
    FallbackApiError { message: String },

    #[error("Serialization error: {message}")]
    SerializationError { message: String },

    #[error("Not found: {message}")]
    NotFound { message: String },
}

impl From<rusqlite::Error> for ReflectError {
    fn from(e: rusqlite::Error) -> Self {
        Self::DatabaseError { message: e.to_string() }
    }
}

impl From<r2d2::Error> for ReflectError {
    fn from(e: r2d2::Error) -> Self {
        Self::DatabaseError { message: e.to_string() }
    }
}

impl From<serde_json::Error> for ReflectError {
    fn from(e: serde_json::Error) -> Self {
        Self::SerializationError { message: e.to_string() }
    }
}
