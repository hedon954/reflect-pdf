#!/usr/bin/env bash
# 构建 Rust dylib（当前架构）并生成 UniFFI Swift 绑定
# 用途：日常开发使用；CI 和 Release 使用 GitHub Actions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATE_DIR="$SCRIPT_DIR/../reflect-pdf-core"
OUT_DIR="$SCRIPT_DIR/../ReflectPDF/Generated"

# 检测当前架构
ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    TARGET="aarch64-apple-darwin"
else
    TARGET="x86_64-apple-darwin"
fi

echo "→ [1/3] 构建 Rust ($TARGET, debug)..."
cd "$CRATE_DIR"
cargo build --target "$TARGET"

# 使用 cargo metadata 获取实际的 target 目录（兼容 CARGO_TARGET_DIR 等自定义路径）
TARGET_DIR="$(cargo metadata --no-deps --format-version 1 | python3 -c "import sys,json; print(json.load(sys.stdin)['target_directory'])")"
DYLIB_PATH="$TARGET_DIR/$TARGET/debug/libreflect_pdf_core.dylib"

echo "→ [2/3] 生成 UniFFI Swift 绑定..."
echo "   dylib: $DYLIB_PATH"
mkdir -p "$OUT_DIR"
cargo run --bin uniffi-bindgen generate \
    --library "$DYLIB_PATH" \
    --language swift \
    --out-dir "$OUT_DIR"

echo "→ [3/3] 复制 dylib 并修正 install_name..."
cp "$DYLIB_PATH" "$OUT_DIR/"
# 将 install_name 改为 @rpath 相对路径，确保 Xcode 链接时不硬编码本机绝对路径
install_name_tool -id "@rpath/libreflect_pdf_core.dylib" "$OUT_DIR/libreflect_pdf_core.dylib"

echo "✓ 完成。产物位于 ReflectPDF/Generated/"
