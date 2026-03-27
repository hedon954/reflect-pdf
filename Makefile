.PHONY: setup build-rust gen-project test dmg clean

## 首次使用：安装工具 + 生成 Xcode 项目
setup:
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@$(MAKE) gen-project
	@$(MAKE) build-rust
	@echo "✓ 准备就绪，可在 Xcode 打开 LumenPDF/LumenPDF.xcodeproj"

## 仅构建 Rust（日常开发中 Rust 有改动时使用）
build-rust:
	./scripts/build-rust.sh

## 重新生成 Xcode 项目（LumenPDF/project.yml 有改动时使用）
gen-project:
	@echo "→ 生成 Xcode 项目..."
	cd LumenPDF && xcodegen generate

## 运行 Rust 单元测试
test:
	cd lumen-pdfcore && cargo test

## 打包为 DMG（本地开发版，不签名）
## 使用 Developer ID 签名：TEAM_ID=XXXXXXXXXX make dmg
dmg:
	./scripts/package-dmg.sh

## 清除构建产物
clean:
	cd lumen-pdfcore && cargo clean
	rm -rf LumenPDF/Generated
	rm -rf build
