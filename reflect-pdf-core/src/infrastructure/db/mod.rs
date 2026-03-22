pub mod migration;
pub mod pdf_document_repo;
pub mod translation_cache_repo;
pub mod vocabulary_repo;

use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;

pub type DbPool = Pool<SqliteConnectionManager>;

pub fn create_pool(db_path: &str) -> Result<DbPool, r2d2::Error> {
    let manager = SqliteConnectionManager::file(db_path);
    Pool::new(manager)
}
