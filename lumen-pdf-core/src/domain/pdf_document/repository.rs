use crate::error::LumenError;
use super::entity::{PdfDocument, UpsertPdfRequest};

pub trait PdfDocumentRepository: Send + Sync {
    fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, LumenError>;
    fn save_reading_position(&self, file_path: &str, page: u32, scroll_offset: f64) -> Result<(), LumenError>;
    fn list(&self) -> Result<Vec<PdfDocument>, LumenError>;
    fn delete(&self, file_path: &str) -> Result<(), LumenError>;
}
