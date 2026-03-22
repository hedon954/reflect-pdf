use crate::domain::vocabulary::{
    entity::{VocabularyEntry, SaveVocabularyRequest},
    repository::VocabularyRepository,
};
use crate::error::ReflectError;
use super::DbPool;
use uuid::Uuid;
use chrono::Utc;

pub struct SqliteVocabularyRepo {
    pool: DbPool,
}

impl SqliteVocabularyRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

fn row_to_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<VocabularyEntry> {
    Ok(VocabularyEntry {
        id: row.get(0)?,
        word: row.get(1)?,
        sentence: row.get(2)?,
        sentence_hash: row.get(3)?,
        pdf_path: row.get(4)?,
        pdf_name: row.get(5)?,
        page_index: row.get::<_, i64>(6)? as u32,
        selection_bounds: row.get(7)?,
        phonetic: row.get(8)?,
        part_of_speech: row.get(9)?,
        context_translation: row.get(10)?,
        context_explanation: row.get(11)?,
        general_definition: row.get(12)?,
        translation_source: row.get(13)?,
        annotation_id: row.get(14)?,
        created_at: row.get(15)?,
    })
}

const SELECT_COLS: &str = "id, word, sentence, sentence_hash, pdf_path, pdf_name,
    page_index, selection_bounds, phonetic, part_of_speech,
    context_translation, context_explanation, general_definition,
    translation_source, annotation_id, created_at";

impl VocabularyRepository for SqliteVocabularyRepo {
    fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, ReflectError> {
        let conn = self.pool.get()?;
        let id = Uuid::new_v4().to_string();
        let now = Utc::now().timestamp();
        conn.execute(
            "INSERT INTO vocabulary_entries
             (id, word, sentence, sentence_hash, pdf_path, pdf_name, page_index,
              selection_bounds, phonetic, part_of_speech, context_translation,
              context_explanation, general_definition, translation_source, annotation_id, created_at)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16)",
            rusqlite::params![
                id, req.word, req.sentence, req.sentence_hash,
                req.pdf_path, req.pdf_name, req.page_index,
                req.selection_bounds, req.phonetic, req.part_of_speech,
                req.context_translation, req.context_explanation,
                req.general_definition, req.translation_source,
                req.annotation_id, now,
            ],
        )?;
        Ok(VocabularyEntry {
            id,
            word: req.word,
            sentence: req.sentence,
            sentence_hash: req.sentence_hash,
            pdf_path: req.pdf_path,
            pdf_name: req.pdf_name,
            page_index: req.page_index,
            selection_bounds: req.selection_bounds,
            phonetic: req.phonetic,
            part_of_speech: req.part_of_speech,
            context_translation: req.context_translation,
            context_explanation: req.context_explanation,
            general_definition: req.general_definition,
            translation_source: req.translation_source,
            annotation_id: req.annotation_id,
            created_at: now,
        })
    }

    fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, ReflectError> {
        let conn = self.pool.get()?;
        let result = conn.query_row(
            &format!("SELECT {SELECT_COLS} FROM vocabulary_entries WHERE id = ?1"),
            rusqlite::params![id],
            row_to_entry,
        );
        match result {
            Ok(e) => Ok(Some(e)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn get_by_word_and_hash(&self, word: &str, sentence_hash: &str) -> Result<Option<VocabularyEntry>, ReflectError> {
        let conn = self.pool.get()?;
        let result = conn.query_row(
            &format!("SELECT {SELECT_COLS} FROM vocabulary_entries WHERE LOWER(word) = LOWER(?1) AND sentence_hash = ?2"),
            rusqlite::params![word, sentence_hash],
            row_to_entry,
        );
        match result {
            Ok(e) => Ok(Some(e)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn list(&self) -> Result<Vec<VocabularyEntry>, ReflectError> {
        let conn = self.pool.get()?;
        let mut stmt = conn.prepare(
            &format!("SELECT {SELECT_COLS} FROM vocabulary_entries ORDER BY created_at DESC"),
        )?;
        let entries = stmt.query_map([], row_to_entry)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(entries)
    }

    fn delete(&self, id: &str) -> Result<(), ReflectError> {
        let conn = self.pool.get()?;
        conn.execute("DELETE FROM vocabulary_entries WHERE id = ?1", rusqlite::params![id])?;
        Ok(())
    }

    fn update_annotation_id(&self, id: &str, annotation_id: &str) -> Result<(), ReflectError> {
        let conn = self.pool.get()?;
        conn.execute(
            "UPDATE vocabulary_entries SET annotation_id = ?1 WHERE id = ?2",
            rusqlite::params![annotation_id, id],
        )?;
        Ok(())
    }
}
