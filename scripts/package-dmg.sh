#!/usr/bin/env bash
# 将 LumenPDF 打包为可分发的 .dmg 文件
#
# 用法：
#   ./scripts/package-dmg.sh                    # 本地开发包（不签名）
#   TEAM_ID=XXXXXXXXXX ./scripts/package-dmg.sh # 使用 Developer ID 签名
#
# 产物：build/LumenPDF-<version>.dmg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
CRATE_DIR="$ROOT_DIR/lumen-pdf-core"
XCODE_DIR="$ROOT_DIR/LumenPDF"
BUILD_DIR="$ROOT_DIR/build"
GENERATED_DIR="$XCODE_DIR/Generated"

APP_NAME="LumenPDF"
BUNDLE_ID="com.LumenPDF.app"
VERSION="${VERSION:-1.0.0}"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"

# 是否使用 Developer ID 签名（仅当提供了 TEAM_ID 时）
TEAM_ID="${TEAM_ID:-}"

echo "╔══════════════════════════════════════════╗"
echo "║   LumenPDF DMG 打包脚本                ║"
echo "╚══════════════════════════════════════════╝"
echo "版本: $VERSION"
echo "产物: $DMG_PATH"
echo ""

# ── 0. 确保 xcodebuild 指向完整 Xcode（而非 CommandLineTools）───────────────
XCODE_APP="/Applications/Xcode.app"
CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null)"
if [[ "$CURRENT_DEV_DIR" == *"CommandLineTools"* ]]; then
    if [ -d "$XCODE_APP/Contents/Developer" ]; then
        echo "→ [0/5] 切换 Xcode 开发者目录（需要 sudo）..."
        sudo xcode-select -s "$XCODE_APP/Contents/Developer"
        echo "   ✓ 已切换至 $XCODE_APP/Contents/Developer"
    else
        echo "✗ 未找到 $XCODE_APP，请先安装 Xcode（App Store）"
        exit 1
    fi
fi

# ── 1. 构建 Universal Rust dylib ─────────────────────────────────────────────
echo "→ [1/6] 构建 Universal Rust dylib..."
cd "$CRATE_DIR"

rustup target add aarch64-apple-darwin x86_64-apple-darwin 2>/dev/null || true

cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin

TARGET_DIR="$(cargo metadata --no-deps --format-version 1 \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['target_directory'])")"

ARM_DYLIB="$TARGET_DIR/aarch64-apple-darwin/release/liblumen_pdf_core.dylib"
X86_DYLIB="$TARGET_DIR/x86_64-apple-darwin/release/liblumen_pdf_core.dylib"
UNIVERSAL_DYLIB="$TARGET_DIR/liblumen_pdf_core.dylib"

lipo -create "$ARM_DYLIB" "$X86_DYLIB" -output "$UNIVERSAL_DYLIB"
echo "   ✓ Universal dylib: $UNIVERSAL_DYLIB"

# 将 install_name 改为 @rpath 相对路径，否则链接后二进制会硬编码构建机器的绝对路径
install_name_tool -id "@rpath/liblumen_pdf_core.dylib" "$UNIVERSAL_DYLIB"
echo "   ✓ install_name → @rpath/liblumen_pdf_core.dylib"

# 生成 UniFFI Swift 绑定（使用 arm64 release 产物）
echo "→ [2/6] 生成 UniFFI Swift 绑定..."
mkdir -p "$GENERATED_DIR"
cargo run --bin uniffi-bindgen generate \
    --library "$ARM_DYLIB" \
    --language swift \
    --out-dir "$GENERATED_DIR"
cp "$UNIVERSAL_DYLIB" "$GENERATED_DIR/liblumen_pdf_core.dylib"
echo "   ✓ 绑定已生成至 $GENERATED_DIR"

# 重新生成 Xcode 项目（确保包含新生成的 Swift 文件）
echo "→ [2.5/5] 重新生成 Xcode 项目..."
cd "$XCODE_DIR"
xcodegen generate
cd "$ROOT_DIR"
echo "   ✓ Xcode 项目已更新"

# ── 3. xcodebuild archive ────────────────────────────────────────────────────
echo "→ [3/6] xcodebuild archive..."
mkdir -p "$BUILD_DIR"

SIGN_ARGS=()
if [ -n "$TEAM_ID" ]; then
    SIGN_ARGS=(
        CODE_SIGN_STYLE=Manual
        CODE_SIGN_IDENTITY="Developer ID Application"
        DEVELOPMENT_TEAM="$TEAM_ID"
    )
    echo "   签名模式: Developer ID（TEAM_ID=$TEAM_ID）"
else
    SIGN_ARGS=(
        CODE_SIGN_IDENTITY="-"
        CODE_SIGNING_REQUIRED=NO
        CODE_SIGNING_ALLOWED=NO
    )
    echo "   签名模式: 不签名（本地开发）"
fi

xcodebuild archive \
    -project "$XCODE_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    "${SIGN_ARGS[@]}"

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "✗ archive 失败，请检查 Xcode 输出"
    exit 1
fi
echo "   ✓ Archive: $ARCHIVE_PATH"

# ── 3. 导出 .app ─────────────────────────────────────────────────────────────
echo "→ [4/6] 导出 .app..."
rm -rf "$EXPORT_DIR"

if [ -n "$TEAM_ID" ]; then
    # 使用 Developer ID 导出选项
    EXPORT_PLIST=$(mktemp /tmp/export-options.XXXXXX.plist)
    cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_PLIST"
    rm -f "$EXPORT_PLIST"
else
    # 直接从 archive 复制 .app（跳过 exportArchive，避免签名校验）
    mkdir -p "$EXPORT_DIR"
    cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"
fi

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "✗ 未找到 $APP_PATH"
    exit 1
fi
echo "   ✓ .app: $APP_PATH"

# ── 4.5: 将 dylib 嵌入 app bundle 并修正引用 ─────────────────────────────────
echo "→ [5/6] 嵌入 dylib 到 Contents/Frameworks/..."
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

mkdir -p "$FRAMEWORKS_DIR"
cp "$UNIVERSAL_DYLIB" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"

# 如果二进制的 LC_LOAD_DYLIB 仍是绝对路径（xcodebuild 时 install_name 未生效），强制改为 @rpath
OLD_REF=$(otool -L "$BINARY" | awk '/liblumen_pdf_core/{print $1}' | head -1)
if [[ -n "$OLD_REF" && "$OLD_REF" != "@rpath/liblumen_pdf_core.dylib" ]]; then
    install_name_tool -change "$OLD_REF" "@rpath/liblumen_pdf_core.dylib" "$BINARY"
    echo "   ✓ 修正 binary 引用: $OLD_REF → @rpath/liblumen_pdf_core.dylib"
fi

# 确保 rpath 包含 @executable_path/../Frameworks（多次 add 会静默报错，用 || true 忽略）
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY" 2>/dev/null || true

# 重新签名（修改二进制后必须重签，否则 Gatekeeper 会拒绝）
if [ -n "$TEAM_ID" ]; then
    SIGN_IDENTITY="Developer ID Application: $TEAM_ID"
else
    SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/liblumen_pdf_core.dylib"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
echo "   ✓ 已重签名"

# ── 4. 制作 DMG（hdiutil，macOS 内置）───────────────────────────────────────
echo "→ [6/6] 制作 DMG..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
# 添加指向 /Applications 的符号链接，方便拖入安装
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✓ 打包完成！                            ║"
echo "╚══════════════════════════════════════════╝"
echo "DMG: $DMG_PATH"
echo ""
if [ -z "$TEAM_ID" ]; then
    echo "提示：已使用 ad-hoc 签名（sign -），可在同机运行。"
    echo "若需分发给他人（不同机器），请提供 TEAM_ID 使用 Developer ID 正式签名："
    echo "  TEAM_ID=XXXXXXXXXX ./scripts/package-dmg.sh"
fi
