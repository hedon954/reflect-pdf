use std::sync::Arc;
use crate::error::LumenError;
use crate::domain::pdf_document::{
    entity::{PdfDocument, UpsertPdfRequest},
    repository::PdfDocumentRepository,
};

pub struct PdfDocumentUseCase {
    repo: Arc<dyn PdfDocumentRepository>,
}

impl PdfDocumentUseCase {
    pub fn new(repo: Arc<dyn PdfDocumentRepository>) -> Self {
        Self { repo }
    }

    pub fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, LumenError> {
        self.repo.upsert(req)
    }

    pub fn save_reading_position(&self, file_path: &str, page: u32, scroll_offset: f64) -> Result<(), LumenError> {
        self.repo.save_reading_position(file_path, page, scroll_offset)
    }

    pub fn list(&self) -> Result<Vec<PdfDocument>, LumenError> {
        self.repo.list()
    }

    pub fn delete(&self, file_path: &str) -> Result<(), LumenError> {
        self.repo.delete(file_path)
    }
}
