import Foundation

/// Maps UniFFI `LumenError` to user-visible Chinese messages for the translation bubble.
enum TranslationErrorFormatter {
    static func userMessage(from error: Error) -> String {
        if let re = error as? LumenError {
            switch re {
            case .ConfigNotInitialized:
                return "LLM 未就绪：请先在「设置」中填写 API Base URL、API Key 与模型，保存后再试。"
            case .DatabaseError(let message):
                return "数据库错误：\(message)"
            case .LlmApiError(let message):
                return "LLM 接口调用失败：\(message)"
            case .FallbackApiError(let message):
                return "兜底翻译接口（MyMemory）失败：\(message)"
            case .SerializationError(let message):
                return "译文解析失败（JSON 格式）：\(message)"
            case .NotFound(let message):
                return "未找到：\(message)"
            }
        }
        return "翻译失败：\(error.localizedDescription)"
    }
}
