# ReflectPDF

> 为深度学习者设计的智能 PDF 阅读工具。像预览那样流畅，像人脑一样有上下文地理解每一个陌生词汇，并将知识以网状记忆永久沉淀。

## 核心特性

- **上下文感知翻译**：划选词汇后，自动提取所在完整句子，由 LLM 解释"在当前语境中为什么是这个意思"，而非词典释义
- **一键入册 + PDF 高亮**：翻译后点击保存，词汇 + 句子 + 解释三元组存入本地单词本，同时在 PDF 原文高亮
- **网状记忆关联**：再次查同一词汇时，自动召回历史学习记录，并对比当前语境与历史语境的异同
- **本地缓存，零重复调用**：点击已高亮词汇直接读取本地缓存，不消耗 API Token
- **原生流畅体验**：基于 PDFKit，选词精准，对标 macOS 预览的渲染性能

## 技术架构

```
SwiftUI + PDFKit（前端）
        ↕ UniFFI（自动生成 Swift 绑定）
Rust + Tokio + SQLite + Reqwest（后端）
```

- **前端**：Swift + PDFKit 负责 PDF 渲染、划词交互、高亮 Annotation
- **桥接**：Mozilla UniFFI 自动生成类型安全的 Swift ↔ Rust 绑定
- **后端**：Rust 负责缓存查询、LLM 调用、数据持久化

## 文档

- [产品需求文档 (PRD)](docs/prd/prd-2026-03-22.md)
- [技术实现文档 (TDD)](docs/tdd/tdd-2026-03-22.md)

## 开发环境

```bash
# 安装 Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin

# 安装 UniFFI Swift 绑定生成工具
cargo install uniffi-bindgen-swift

# 构建 Rust 后端并生成 Swift 绑定
./scripts/build-rust.sh
```

需要 Xcode 14.0+ 和 macOS 13.0+。

## 版本规划

| 版本 | 主要功能 |
|------|---------|
| V1.0 (MVP) | PDF 渲染、上下文 AI 翻译、保存高亮、本地缓存 |
| V1.1 | 历史记忆召回与差异分析、单词本视图、全文搜索 |
| V1.2 | 遗忘曲线复习、Anki 导出 |
| V2.0 | 知识图谱可视化、iCloud 同步 |
