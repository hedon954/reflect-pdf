---
name: domain-unit-test
description: 为 ReflectPDF 的 Rust domain 层编写单元测试。当新增或修改 domain/service.rs、domain/entity.rs 时必须同步补充测试。测试不得依赖任何 I/O（无 SQLite、无 HTTP、无文件系统）。
---

# 领域层单元测试

## 核心原则

- 测试只在 `#[cfg(test)]` 模块中，与被测代码同文件
- **不引入** mockall、wiremock 等 mock 库；用内联 `struct Fake*` 实现 domain trait
- 异步测试用 `#[tokio::test]`
- 运行命令：`cargo test domain` （精确匹配 domain 模块路径下的测试）

---

## Fake 实现模板

### FakeCache（内存 HashMap）

```rust
struct FakeCache(Mutex<HashMap<String, TranslationResult>>);

impl FakeCache {
    fn empty() -> Arc<Self> { Arc::new(Self(Mutex::new(HashMap::new()))) }
}

impl TranslationCacheRepository for FakeCache {
    fn get(&self, word: &str, hash: &str) -> Result<Option<TranslationResult>, ReflectError> {
        Ok(self.0.lock().unwrap().get(&key(word, hash)).cloned())
    }
    fn set(&self, word: &str, hash: &str, r: &TranslationResult) -> Result<(), ReflectError> {
        self.0.lock().unwrap().insert(key(word, hash), r.clone());
        Ok(())
    }
}

fn key(word: &str, hash: &str) -> String { format!("{word}:{hash}") }
```

### FakeTranslator（成功 / 失败两种）

```rust
struct FakeTranslator { source: &'static str }

#[async_trait::async_trait]
impl Translator for FakeTranslator {
    async fn translate(&self, word: &str, _: &str) -> Result<TranslationResult, ReflectError> {
        Ok(TranslationResult {
            word: word.to_string(),
            source: self.source.to_string(),
            context_translation: "fake".to_string(),
            context_explanation: String::new(),
            general_definition: "fake".to_string(),
            ..Default::default()
        })
    }
}

struct AlwaysFailTranslator;
#[async_trait::async_trait]
impl Translator for AlwaysFailTranslator {
    async fn translate(&self, _: &str, _: &str) -> Result<TranslationResult, ReflectError> {
        Err(ReflectError::LlmApiError("simulated failure".to_string()))
    }
}
```

### FakeVocabularyRepository

```rust
struct FakeVocabRepo(Mutex<Vec<VocabularyEntry>>);

impl VocabularyRepository for FakeVocabRepo {
    fn save(&self, entry: &VocabularyEntry) -> Result<String, ReflectError> {
        self.0.lock().unwrap().push(entry.clone());
        Ok(entry.id.clone())
    }
    fn find_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, ReflectError> {
        Ok(self.0.lock().unwrap().iter().find(|e| e.id == id).cloned())
    }
    fn list_all(&self) -> Result<Vec<VocabularyEntry>, ReflectError> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn delete(&self, id: &str) -> Result<(), ReflectError> {
        self.0.lock().unwrap().retain(|e| e.id != id);
        Ok(())
    }
}
```

---

## TranslationDomainService 必测场景

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    use std::collections::HashMap;

    fn make_service(
        llm: impl Translator + 'static,
        fallback: impl Translator + 'static,
    ) -> (TranslationDomainService, Arc<FakeCache>) {
        let cache = FakeCache::empty();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(llm),
            Arc::new(fallback),
        );
        (svc, cache)
    }

    fn req() -> TranslationRequest {
        TranslationRequest {
            word: "emergent".to_string(),
            sentence: "The model shows emergent behavior.".to_string(),
            pdf_path: "/tmp/test.pdf".to_string(),
            page_index: 0,
            selection_bounds: SelectionBounds { x: 0.0, y: 0.0, width: 10.0, height: 2.0 },
        }
    }

    // ① 缓存命中时不调用任何翻译器
    #[tokio::test]
    async fn cache_hit_skips_translators() {
        let (svc, cache) = make_service(AlwaysFailTranslator, AlwaysFailTranslator);
        // 预热缓存
        cache.set("emergent", &sha256("The model shows emergent behavior."),
            &TranslationResult { source: "llm".into(), ..Default::default() }).unwrap();

        let result = svc.translate(&req()).await.unwrap();
        assert_eq!(result.source, "cache");
    }

    // ② LLM 成功 → 写入缓存，source = "llm"
    #[tokio::test]
    async fn llm_success_writes_cache() {
        let (svc, cache) = make_service(
            FakeTranslator { source: "llm" },
            AlwaysFailTranslator,
        );
        let result = svc.translate(&req()).await.unwrap();
        assert_eq!(result.source, "llm");

        // 缓存已写入
        let hash = sha256("The model shows emergent behavior.");
        assert!(cache.get("emergent", &hash).unwrap().is_some());
    }

    // ③ LLM 失败 → 兜底翻译，source = "fallback"，不写缓存
    #[tokio::test]
    async fn llm_failure_uses_fallback_without_caching() {
        let (svc, cache) = make_service(
            AlwaysFailTranslator,
            FakeTranslator { source: "fallback" },
        );
        let result = svc.translate(&req()).await.unwrap();
        assert_eq!(result.source, "fallback");

        // 兜底结果不写缓存
        let hash = sha256("The model shows emergent behavior.");
        assert!(cache.get("emergent", &hash).unwrap().is_none());
    }

    // ④ LLM 和兜底都失败 → 返回 Err
    #[tokio::test]
    async fn both_fail_returns_error() {
        let (svc, _) = make_service(AlwaysFailTranslator, AlwaysFailTranslator);
        assert!(svc.translate(&req()).await.is_err());
    }
}
```

---

## 实体/值对象测试

在 `entity.rs` 的 `#[cfg(test)]` 块中测试约束条件：

```rust
// pdf_document/entity.rs
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scroll_offset_is_normalized() {
        // 业务约束：last_scroll_offset 必须在 [0.0, 1.0]
        let doc = PdfDocument { last_scroll_offset: 1.5, ..Default::default() };
        assert!(doc.is_valid_scroll_offset() == false);
    }
}
```

---

## 检查清单

- [ ] 每个 `domain/*/service.rs` 都有 `#[cfg(test)] mod tests`
- [ ] 测试覆盖：缓存命中 / LLM 成功 / LLM 失败兜底 / 双失败
- [ ] 所有 Fake 实现均在测试模块内，不暴露到生产代码
- [ ] `cargo test domain` 全部通过
- [ ] 不依赖任何 I/O（无文件、无网络、无 SQLite）
