use crate::error::ReflectError;
use super::entity::{PdfDocument, UpsertPdfRequest};

pub trait PdfDocumentRepository: Send + Sync {
    fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, ReflectError>;
    fn save_reading_position(&self, file_path: &str, page: u32, scroll_offset: f64) -> Result<(), ReflectError>;
    fn list(&self) -> Result<Vec<PdfDocument>, ReflectError>;
    fn delete(&self, file_path: &str) -> Result<(), ReflectError>;
}
