---
name: add-uniffi-api
description: 为 LumenPDF 添加一个新的跨语言 API（UniFFI 桥接）。当需要新增 Rust → Swift 接口、新增 UDL 函数或数据类型、或扩展 BridgeService 时使用。
---

# 添加 UniFFI 跨语言 API

## 完整流程（4 步）

### Step 1 — UDL 定义

编辑 `lumen-pdf-core/src/interfaces/lumen_pdf_lib.udl`：

- 在 `namespace lumen_pdf_lib { }` 中添加函数声明
- 需要时在下方添加新的 `dictionary` 类型

```udl
// 同步函数示例
[Throws=LumenError]
MyResult do_something(string input);

// 异步函数示例
[Async, Throws=LumenError]
MyResult do_something_async(MyRequest request);

// 数据类型
dictionary MyRequest {
  string word;
  u32 page_index;
};
```

### Step 2 — Rust 实现

编辑 `lumen-pdf-core/src/interfaces/api.rs`：

```rust
#[uniffi::export]                              // 同步
pub fn do_something(input: String) -> Result<MyResult, LumenError> {
    let pool = POOL.get().ok_or(LumenError::ConfigNotInitialized)?;
    MyUseCase::new(pool.clone()).execute(input)
}

#[uniffi::export(async_runtime = "tokio")]     // 异步
pub async fn do_something_async(request: MyRequest) -> Result<MyResult, LumenError> {
    ...
}
```

如需新的 DDD 模块：

- `domain/my_entity/entity.rs` — 实体定义（`#[uniffi::Record]`）
- `domain/my_entity/repository.rs` — trait 定义（无外部依赖）
- `application/my_entity/use_case.rs` — 用例编排
- `infrastructure/db/my_entity_repo.rs` — SQLite 实现

### Step 3 — 重新构建

```bash
./scripts/build-rust.sh
```

脚本会自动编译 Rust dylib 并更新 `LumenPDF/Generated/` 下的 Swift 绑定。

### Step 4 — Swift 封装

编辑 `LumenPDF/Services/BridgeService.swift`，添加对应的 Swift 方法：

```swift
func doSomething(_ input: String) throws -> MyResult {
    return try LumenPDFLib.doSomething(input: input)
}

func doSomethingAsync(_ request: MyRequest) async throws -> MyResult {
    return try await LumenPDFLib.doSomethingAsync(request: request)
}
```

## 检查清单

- [ ] UDL 函数签名与 Rust `#[uniffi::export]` 函数签名匹配
- [ ] 新增的 `dictionary` 字段类型均为 UniFFI 支持类型
- [ ] 异步函数 UDL 标注 `[Async]`，Rust 标注 `async_runtime = "tokio"`
- [ ] `build-rust.sh` 成功运行，无编译错误
- [ ] `Generated/` 文件已更新（勿手动修改）
- [ ] `BridgeService.swift` 已添加对应封装
