use crate::error::ReflectError;

#[derive(Debug, Clone, uniffi::Record)]
pub struct PdfDocument {
    pub id: String,
    pub file_path: String,
    pub file_name: String,
    pub total_pages: u32,
    pub last_page: u32,
    pub last_scroll_offset: f64,
    pub opened_at: i64,
    pub added_at: i64,
}

impl PdfDocument {
    pub fn validate_scroll_offset(offset: f64) -> Result<(), ReflectError> {
        if !(0.0..=1.0).contains(&offset) {
            return Err(ReflectError::DatabaseError {
                message: format!("scroll_offset {offset} out of range [0.0, 1.0]"),
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct UpsertPdfRequest {
    pub file_path: String,
    pub file_name: String,
    pub total_pages: u32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scroll_offset_within_range_is_valid() {
        assert!(PdfDocument::validate_scroll_offset(0.0).is_ok());
        assert!(PdfDocument::validate_scroll_offset(0.5).is_ok());
        assert!(PdfDocument::validate_scroll_offset(1.0).is_ok());
    }

    #[test]
    fn scroll_offset_out_of_range_returns_error() {
        assert!(PdfDocument::validate_scroll_offset(-0.1).is_err());
        assert!(PdfDocument::validate_scroll_offset(1.1).is_err());
    }
}
