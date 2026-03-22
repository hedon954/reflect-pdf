# ReflectPDF

智能 PDF 阅读工具：像 macOS 预览一样流畅，支持**上下文感知翻译**和**知识永久沉淀**。

## 核心功能

- **PDF 阅读**：基于 PDFKit，缩放、连续滚动，自动恢复上次阅读位置
- **智能划词翻译**：提取所在完整句子 → LLM 给出语境解释，而非词典释义
- **单词本**：保存词汇 + 句子 + 解释三元组，PDF 原文自动高亮
- **发音**：系统本地 TTS，零延迟、离线可用
- **三级降级**：本地缓存 → LLM → MyMemory 免费 API

## 技术架构

```
SwiftUI (PDFKit) ──UniFFI──▶ Rust (DDD) ──▶ SQLite
                              ├── domain/       (实体 + Traits)
                              ├── application/  (用例编排)
                              └── infrastructure/ (SQLite + HTTP)
```

## 快速开始

**依赖**：macOS 13+、Xcode 15+、Rust stable、Homebrew

```bash
# 首次设置（安装工具 + 构建 Rust + 生成 Xcode 项目）
make setup

# 然后在 Xcode 打开
open ReflectPDF/ReflectPDF.xcodeproj
```

## 日常开发

```bash
make build-rust      # Rust 代码有改动时
make test            # 运行 Rust 单元测试
make gen-project     # project.yml 有改动时重新生成 Xcode 项目
```

## 设置 LLM

启动 App 后进入「设置」页面：
- **API Base URL**：OpenAI 兼容接口地址（默认 `https://api.openai.com/v1`）
- **API Key**：存储在系统 Keychain，不会写入磁盘
- **模型**：默认 `gpt-4o-mini`

## 项目结构

```
reflect-pdf/
├── reflect-pdf-core/      Rust 后端（DDD）
│   └── src/
│       ├── interfaces/    UniFFI 导出
│       ├── application/   用例层
│       ├── domain/        领域层（纯逻辑，无 I/O）
│       └── infrastructure/ SQLite + HTTP 实现
├── ReflectPDF/            Swift 前端
│   ├── App/
│   ├── Views/
│   ├── Services/
│   └── Generated/         UniFFI 自动生成（勿手改）
├── scripts/build-rust.sh  Rust 构建脚本
├── project.yml            xcodegen 配置
└── Makefile
```

## 数据存储

所有数据本地存储于 `~/Library/Application Support/ReflectPDF/data.db`（SQLite），API Key 存 Keychain。
