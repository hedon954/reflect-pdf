# LumenPDF

> 为深度阅读者设计的 macOS 智能 PDF 工具——像系统预览一样流畅，但支持**上下文感知翻译**、**原生高亮 / 划线标注**与**知识永久沉淀**。

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![Rust](https://img.shields.io/badge/Rust-stable-brown)
![License MIT](https://img.shields.io/badge/License-MIT-green)

---

## 核心功能

| 功能                   | 说明                                                       |
| ---------------------- | ---------------------------------------------------------- |
| 📖 **PDF 阅读**        | PDFKit 渲染，连续滚动，工具栏实时显示文件名与页码；跨重启 / 最小化还原均恢复精确阅读位置（页码 + 纵向偏移），支持 Cmd+S 立即落库 |
| 📑 **PDF 目录（TOC）** | 左侧栏展示完整大纲（`VStack` 保证 `scrollTo` 可定位任意远端章节）；随阅读进度自动高亮并滚入可视区；启动 / 最小化还原后自动归位 |
| 🖱 **选词操作菜单**    | 划选后弹出贴近选区的菜单：**翻译 / 高亮 / 划线**           |
| 🌐 **语境感知翻译**    | 每个语境独立翻译；气泡展示语境翻译、语境解释、整句译文；**LLM 失败时在气泡底部展示具体原因**（缺少配置 / 接口报错等） |
| 🖊 **原生 PDF 标注**   | 高亮（黄）/ 划线（红，同 macOS Preview），支持跨行精确标注、Toggle 移除、部分重叠自动合并；**Cmd+Z 撤销**最近一次标注操作 |
| 📚 **单词本**          | 同一单词多语境聚合展示；保存时 PDF 原文自动高亮            |
| 🔊 **本地发音**        | AVSpeechSynthesizer，零延迟，完全离线                      |
| 🔒 **数据本地化**      | 所有数据存 SQLite，API Key 存 Keychain，无云服务依赖       |

---

## 截图

> 启动 App → 打开 PDF → 划词选择操作 → 翻译气泡 → 保存到单词本

---

## 安装方式

### 方式一：下载预编译包（推荐）

> 目前尚未发布 Release 包，请使用方式二从源码构建。

### 方式二：自行打包 DMG

适合需要分发或在多台 Mac 上使用的场景。

#### 环境要求

| 工具 | 版本要求 |
|------|---------|
| macOS | 13.0+（打包机） |
| Xcode | 15.0+（含命令行工具 `xcodebuild`） |
| Rust | stable（`rustup show` 确认） |
| `rustup target` | `aarch64-apple-darwin` + `x86_64-apple-darwin` |

> `hdiutil`（DMG 制作工具）是 macOS 内置命令，无需额外安装。

#### 本地开发包（不签名，仅自用）

```bash
# 克隆并进入项目
git clone https://github.com/yourname/lumen-pdf.git
cd lumen-pdf

# 生成 Xcode 工程（首次）
brew install xcodegen
cd LumenPDF && xcodegen generate && cd ..

# 一键打包 DMG
make dmg
# 或等价写法：
# ./scripts/package-dmg.sh
```

产物路径：`build/LumenPDF-1.0.0.dmg`

打开 DMG → 将 `LumenPDF.app` 拖入 `Applications` 文件夹即可。

> **首次打开提示"无法验证开发者"**：这是 macOS Gatekeeper 的正常提示，不是病毒警告。在 Finder 中**右键点击** `LumenPDF.app` → 选择「打开」→ 弹窗中再点击「打开」即可。此后双击直接运行，无需重复此步骤。

#### 使用 Developer ID 正式签名（可分发给他人）

前提：拥有苹果开发者账号，并在 Xcode → Settings → Accounts 中配置好证书。

```bash
# 查找你的 Team ID（10 位字母数字）
# Xcode → Settings → Accounts → 选择账号 → Team ID 列
TEAM_ID=XXXXXXXXXX make dmg
```

签名后的 DMG 可直接分发，其他用户双击即可安装，无需绕过 Gatekeeper。

若需 **Notarization（公证）**（推荐对外正式分发时使用）：

```bash
# 提交公证（替换占位符）
xcrun notarytool submit build/LumenPDF-1.0.0.dmg \
    --apple-id "your@email.com" \
    --team-id "XXXXXXXXXX" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# 公证通过后装订票据到 DMG
xcrun stapler staple build/LumenPDF-1.0.0.dmg
```

#### 指定版本号

```bash
VERSION=2.0.0 make dmg
# 产物：build/LumenPDF-2.0.0.dmg
```

### 方式三：从源码构建（开发调试）

#### 环境要求

| 工具     | 版本要求                     |
| -------- | ---------------------------- |
| macOS    | 13.0+                        |
| Xcode    | 15.0+                        |
| Rust     | stable（`rustup show` 确认） |
| Homebrew | 最新版                       |

#### 步骤

```bash
# 1. 克隆仓库
git clone https://github.com/yourname/lumen-pdf.git
cd lumen-pdf

# 2. 安装工具依赖
brew install xcodegen
rustup target add aarch64-apple-darwin x86_64-apple-darwin

# 3. 构建 Rust 后端 + 生成 UniFFI Swift 绑定
./scripts/build-rust.sh

# 4. 生成 Xcode 工程（首次或 project.yml 变更时）
cd LumenPDF && xcodegen generate && cd ..

# 5. 打开 Xcode 编译运行
open LumenPDF/LumenPDF.xcodeproj
# 选择 My Mac 目标 → ⌘R 运行
```

> **Apple Silicon 用户**：脚本自动检测架构，无需额外配置。
> **Intel 用户**：同上，脚本会选 `x86_64-apple-darwin` 目标。

---

## 首次使用设置

启动 App 后点击右上角 ⚙️ 进入「设置」。保存后**立即生效**，无需重启 App：

| 配置项       | 说明                        | 默认值                      |
| ------------ | --------------------------- | --------------------------- |
| API Base URL | OpenAI 兼容接口地址         | `https://api.openai.com/v1` |
| API Key      | 存储在系统 Keychain，不落盘 | —                           |
| 模型         | 任意 OpenAI 兼容模型        | `gpt-4o-mini`               |
| 目标语言     | LLM 输出的翻译目标语言      | `简体中文`                  |

> 不配置 LLM 也可使用：翻译会自动降级到 **MyMemory 免费 API**（无需注册，但只提供基础词义，无语境解释）。

---

## 使用指南

### 打开 PDF

点击工具栏「文库」图标 → Popover 中选择「打开 PDF」，或直接点击「打开 PDF」按钮。  
已打开的文件会记录在文库中。阅读位置（页码 + 纵向滚动）在以下时机自动保存：

- **实时滚动**：停止滚动 0.5s 后自动写入。
- **Cmd+S**：立即写入当前位置。
- **最小化前**：窗口最小化前同步保存，还原后精确恢复。
- **App 退出前**：自动同步保存，下次启动直接跳回。

### 划词翻译

1. 用鼠标划选 PDF 中的单词或短句
2. 在选区附近弹出的操作菜单中点击「**翻译**」
3. 翻译气泡展示：单词 · 音标 · 语境翻译 · 语境解释 · 整句译文 · 原文
4. 点击「保存到单词本」→ PDF 原文自动添加黄色高亮

### 高亮 / 划线

- 选中文字 → 操作菜单 → 「**高亮**」（黄）或「**划线**」（红，同 macOS Preview）
- 跨行选区精确标注：每行分别创建一个标注，无行间空白缝隙
- 再次选中相同区域点击同一按钮 → **移除标注**（Toggle）
- 选区与已有标注部分重叠 → 自动**合并**为更大范围

### 单词本

点击工具栏中间「**单词本**」Tab：

- 按单词分组，同词多语境下方展开
- 点击来源页码 → 跳转到对应 PDF 页面
- 右侧编辑（✏️）/ 删除（🗑）按钮；删除时同步移除 PDF 高亮
- 搜索框支持按单词、翻译、解释、整句译文筛选

### PDF 目录

打开含大纲的 PDF 后，左侧自动显示目录。随阅读进度自动高亮当前章节并滚入可视区；点击条目跳转对应页面。

---

## 日常开发

```bash
make build-rust      # Rust 代码有改动时重新构建 + 生成绑定
make test            # 运行 Rust 单元测试
make gen-project     # project.yml 有改动时重新生成 Xcode 项目
make dmg             # 打包为 DMG（不签名）
TEAM_ID=XXXXXX make dmg  # 打包为 DMG（Developer ID 签名）
```

---

## 技术架构

```
SwiftUI (PDFKit)
    │
    │  Mozilla UniFFI（自动生成 Swift 绑定）
    ▼
Rust — DDD 分层架构
    ├── interfaces/    UniFFI 导出 + 依赖注入
    ├── application/   用例编排（无直接 I/O）
    ├── domain/        实体 + Repository Traits（零外部依赖）
    └── infrastructure/  SQLite (rusqlite) + HTTP (reqwest)
```

翻译三级降级：**本地 SQLite 缓存** → **LLM（OpenAI 兼容）** → **MyMemory API（兜底）**

---

## 数据存储

| 数据                     | 位置                                               |
| ------------------------ | -------------------------------------------------- |
| SQLite 数据库            | `~/Library/Application Support/LumenPDF/data.db` |
| API Key                  | macOS Keychain                                     |
| 上次打开文件路径         | `UserDefaults`                                     |
| Security-Scoped Bookmark | `UserDefaults["bm_<filePath>"]`                    |

---

## 项目结构

```
lumen-pdf/
├── lumen-pdf-core/         Rust 后端（DDD）
│   └── src/
│       ├── interfaces/     UniFFI 导出
│       ├── application/    用例层
│       ├── domain/         领域层（纯逻辑，无 I/O）
│       └── infrastructure/ SQLite + HTTP 实现
├── LumenPDF/               Swift 前端
│   ├── App/                AppState（全局状态）
│   ├── Views/              SwiftUI 视图
│   ├── Services/           BridgeService / AudioService 等
│   ├── Generated/          UniFFI 自动生成（勿手改）
│   └── project.yml         xcodegen 配置
├── scripts/build-rust.sh  Rust 构建脚本
├── Makefile
└── docs/
    ├── prd/prd-2026-03-22.md   产品需求文档
    ├── tdd/tdd-2026-03-22.md   技术实现文档 v1.1（总体架构）
    ├── tdd/tdd-2026-03-24.md   技术实现文档 v1.2（2026-03-24 迭代）
    └── tdd/tdd-2026-03-25.md   技术实现文档 v1.3（2026-03-25 迭代）
```

---

## 文档

- [产品需求文档 (PRD)](docs/prd/prd-2026-03-22.md)
- [技术实现文档 v1.1 — 总体架构](docs/tdd/tdd-2026-03-22.md)
- [技术实现文档 v1.2 — 2026-03-24 迭代变更](docs/tdd/tdd-2026-03-24.md)
- [技术实现文档 v1.3 — 2026-03-25 迭代变更](docs/tdd/tdd-2026-03-25.md)

---

## License

MIT
