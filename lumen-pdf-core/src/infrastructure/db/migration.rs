use crate::error::LumenError;
use rusqlite::Connection;

pub fn run(conn: &Connection) -> Result<(), LumenError> {
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS vocabulary_entries (
            id                  TEXT PRIMARY KEY,
            word                TEXT NOT NULL,
            sentence            TEXT NOT NULL,
            sentence_hash       TEXT NOT NULL,
            pdf_path            TEXT NOT NULL,
            pdf_name            TEXT NOT NULL,
            page_index          INTEGER NOT NULL,
            selection_bounds    TEXT NOT NULL DEFAULT '',
            phonetic            TEXT NOT NULL DEFAULT '',
            part_of_speech      TEXT NOT NULL DEFAULT '',
            context_translation TEXT NOT NULL DEFAULT '',
            context_explanation TEXT NOT NULL DEFAULT '',
            general_definition  TEXT NOT NULL DEFAULT '',
            context_sentence_translation TEXT NOT NULL DEFAULT '',
            translation_source  TEXT NOT NULL DEFAULT '',
            annotation_id       TEXT,
            created_at          INTEGER NOT NULL,
            query_count         INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS translation_cache (
            id            TEXT PRIMARY KEY,
            word          TEXT NOT NULL,
            sentence_hash TEXT NOT NULL,
            response_json TEXT NOT NULL,
            source        TEXT NOT NULL DEFAULT 'llm',
            created_at    INTEGER NOT NULL,
            hit_count     INTEGER NOT NULL DEFAULT 0,
            UNIQUE(word, sentence_hash)
        );

        CREATE TABLE IF NOT EXISTS pdf_documents (
            id                 TEXT PRIMARY KEY,
            file_path          TEXT NOT NULL UNIQUE,
            file_name          TEXT NOT NULL,
            total_pages        INTEGER NOT NULL DEFAULT 0,
            last_page          INTEGER NOT NULL DEFAULT 0,
            last_scroll_offset REAL    NOT NULL DEFAULT 0.0,
            opened_at          INTEGER NOT NULL,
            added_at           INTEGER NOT NULL
        );
    ",
    )?;

    // Add query_count to existing databases (ignore error if column already exists)
    let _ = conn.execute_batch(
        "ALTER TABLE vocabulary_entries ADD COLUMN query_count INTEGER NOT NULL DEFAULT 0;",
    );
    let _ = conn.execute_batch(
        "ALTER TABLE vocabulary_entries ADD COLUMN context_sentence_translation TEXT NOT NULL DEFAULT '';"
    );

    Ok(())
}
