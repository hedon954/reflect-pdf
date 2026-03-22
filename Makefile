.PHONY: setup build-rust gen-project test clean

## 首次使用：安装工具 + 生成 Xcode 项目
setup:
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@$(MAKE) gen-project
	@$(MAKE) build-rust
	@echo "✓ 准备就绪，可在 Xcode 打开 ReflectPDF/ReflectPDF.xcodeproj"

## 仅构建 Rust（日常开发中 Rust 有改动时使用）
build-rust:
	./scripts/build-rust.sh

## 重新生成 Xcode 项目（ReflectPDF/project.yml 有改动时使用）
gen-project:
	@echo "→ 生成 Xcode 项目..."
	cd ReflectPDF && xcodegen generate

## 运行 Rust 单元测试
test:
	cd reflect-pdf-core && cargo test

## 清除构建产物
clean:
	cd reflect-pdf-core && cargo clean
	rm -rf ReflectPDF/Generated
	rm -rf build
