use crate::domain::translation::{entity::TranslationResult, repository::TranslationCacheRepository};
use crate::error::ReflectError;
use super::DbPool;
use uuid::Uuid;
use chrono::Utc;

pub struct SqliteTranslationCacheRepo {
    pool: DbPool,
}

impl SqliteTranslationCacheRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

impl TranslationCacheRepository for SqliteTranslationCacheRepo {
    fn get(&self, word: &str, sentence_hash: &str) -> Result<Option<TranslationResult>, ReflectError> {
        let conn = self.pool.get()?;
        let result = conn.query_row(
            "SELECT response_json FROM translation_cache WHERE word = ?1 AND sentence_hash = ?2",
            rusqlite::params![word, sentence_hash],
            |row| row.get::<_, String>(0),
        );

        match result {
            Ok(json) => {
                conn.execute(
                    "UPDATE translation_cache SET hit_count = hit_count + 1 WHERE word = ?1 AND sentence_hash = ?2",
                    rusqlite::params![word, sentence_hash],
                ).ok();
                let r: TranslationResult = serde_json::from_str(&json)
                    .map_err(|e| ReflectError::SerializationError { message: e.to_string() })?;
                Ok(Some(r))
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn set(&self, word: &str, sentence_hash: &str, result: &TranslationResult) -> Result<(), ReflectError> {
        let conn = self.pool.get()?;
        let json = serde_json::to_string(result)?;
        conn.execute(
            "INSERT INTO translation_cache (id, word, sentence_hash, response_json, source, created_at, hit_count)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)
             ON CONFLICT(word, sentence_hash) DO UPDATE SET response_json = excluded.response_json, source = excluded.source",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                word,
                sentence_hash,
                json,
                result.source,
                Utc::now().timestamp(),
            ],
        )?;
        Ok(())
    }
}
