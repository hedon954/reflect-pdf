use crate::domain::pdf_document::{
    entity::{PdfDocument, UpsertPdfRequest},
    repository::PdfDocumentRepository,
};
use crate::error::ReflectError;
use super::DbPool;
use uuid::Uuid;
use chrono::Utc;

pub struct SqlitePdfDocumentRepo {
    pool: DbPool,
}

impl SqlitePdfDocumentRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

fn row_to_doc(row: &rusqlite::Row<'_>) -> rusqlite::Result<PdfDocument> {
    Ok(PdfDocument {
        id: row.get(0)?,
        file_path: row.get(1)?,
        file_name: row.get(2)?,
        total_pages: row.get::<_, i64>(3)? as u32,
        last_page: row.get::<_, i64>(4)? as u32,
        last_scroll_offset: row.get(5)?,
        opened_at: row.get(6)?,
        added_at: row.get(7)?,
    })
}

impl PdfDocumentRepository for SqlitePdfDocumentRepo {
    fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, ReflectError> {
        let conn = self.pool.get()?;
        let now = Utc::now().timestamp();

        let existing = conn.query_row(
            "SELECT id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at
             FROM pdf_documents WHERE file_path = ?1",
            rusqlite::params![req.file_path],
            row_to_doc,
        );

        match existing {
            Ok(mut doc) => {
                doc.opened_at = now;
                doc.total_pages = req.total_pages;
                conn.execute(
                    "UPDATE pdf_documents SET opened_at = ?1, total_pages = ?2 WHERE file_path = ?3",
                    rusqlite::params![now, req.total_pages, req.file_path],
                )?;
                Ok(doc)
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => {
                let id = Uuid::new_v4().to_string();
                conn.execute(
                    "INSERT INTO pdf_documents (id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at)
                     VALUES (?1, ?2, ?3, ?4, 0, 0.0, ?5, ?5)",
                    rusqlite::params![id, req.file_path, req.file_name, req.total_pages, now],
                )?;
                Ok(PdfDocument {
                    id,
                    file_path: req.file_path,
                    file_name: req.file_name,
                    total_pages: req.total_pages,
                    last_page: 0,
                    last_scroll_offset: 0.0,
                    opened_at: now,
                    added_at: now,
                })
            }
            Err(e) => Err(e.into()),
        }
    }

    fn save_reading_position(&self, file_path: &str, page: u32, scroll_offset: f64) -> Result<(), ReflectError> {
        let conn = self.pool.get()?;
        conn.execute(
            "UPDATE pdf_documents SET last_page = ?1, last_scroll_offset = ?2 WHERE file_path = ?3",
            rusqlite::params![page, scroll_offset, file_path],
        )?;
        Ok(())
    }

    fn list(&self) -> Result<Vec<PdfDocument>, ReflectError> {
        let conn = self.pool.get()?;
        let mut stmt = conn.prepare(
            "SELECT id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at
             FROM pdf_documents ORDER BY opened_at DESC",
        )?;
        let docs = stmt.query_map([], row_to_doc)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(docs)
    }

    fn delete(&self, file_path: &str) -> Result<(), ReflectError> {
        let conn = self.pool.get()?;
        conn.execute("DELETE FROM pdf_documents WHERE file_path = ?1", rusqlite::params![file_path])?;
        Ok(())
    }
}
