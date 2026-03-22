---
name: build-rust
description: 构建 ReflectPDF 的 Rust 后端并重新生成 UniFFI Swift 绑定。当 Rust 代码有改动、UDL 有更新、或 Swift 侧报"符号找不到"错误时使用。
---

# 构建 Rust 后端 & 生成 Swift 绑定

## 快速构建（开发阶段）

```bash
./scripts/build-rust.sh
```

构建产物输出到 `ReflectPDF/Generated/`。

## 手动步骤（调试用）

```bash
cd reflect-pdf-core

# 1. 编译（仅当前架构，速度快）
cargo build --target aarch64-apple-darwin

# 2. 生成 Swift 绑定
cargo run --bin uniffi-bindgen generate \
    --library target/aarch64-apple-darwin/debug/libreflect_pdf_core.dylib \
    --language swift \
    --out-dir ../ReflectPDF/Generated

# 3. 复制 dylib
cp target/aarch64-apple-darwin/debug/libreflect_pdf_core.dylib \
   ../ReflectPDF/Generated/
```

## 发布构建（Universal Binary）

```bash
cd reflect-pdf-core
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

lipo -create \
    target/aarch64-apple-darwin/release/libreflect_pdf_core.dylib \
    target/x86_64-apple-darwin/release/libreflect_pdf_core.dylib \
    -output ../ReflectPDF/Generated/libreflect_pdf_core.dylib
```

## 常见问题

| 问题 | 解决 |
|------|------|
| `uniffi-bindgen not found` | `cargo install uniffi-bindgen-swift` |
| Swift 报 `unresolved identifier` | 重新运行 `build-rust.sh`，确认 `Generated/` 已更新 |
| `cargo clippy` 报错 | 先修 clippy 警告再构建（CI 会 `-D warnings`） |
| dylib 签名问题 | 开发时不需要签名；发布时由 Xcode Archive 统一签名 |
