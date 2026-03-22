import SwiftUI

struct TranslationBubble: View {
    let request: TranslationBubbleRequest
    let isLoading: Bool
    let onSave: (TranslationResult) -> Void
    let onDismiss: () -> Void

    @StateObject private var audio = AudioService()
    @State private var isSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(request.result?.word ?? request.word)
                            .font(.title2.bold())

                        if let phonetic = request.result?.phonetic, !phonetic.isEmpty {
                            Text("[\(phonetic)]")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        if let pos = request.result?.partOfSpeech, !pos.isEmpty {
                            Text(pos)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }

                    if let source = request.result?.source, source == "fallback" {
                        Label("基础翻译", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    // Pronounce button
                    Button {
                        audio.speak(request.result?.word ?? request.word)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Divider()

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("翻译中…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            } else if let result = request.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !result.contextTranslation.isEmpty {
                            Section("语境翻译") {
                                Text(result.contextTranslation)
                                    .font(.body)
                            }
                        }

                        if !result.contextExplanation.isEmpty {
                            Section("语境解释") {
                                Text(result.contextExplanation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !result.generalDefinition.isEmpty {
                            Section("通用释义") {
                                Text(result.generalDefinition)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Context sentence
                        Section("上下文") {
                            Text(request.sentence)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .italic()
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 280)

                Divider()

                // Footer actions
                HStack {
                    Spacer()
                    if request.existingEntryId != nil {
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            onSave(result)
                            isSaved = true
                        } label: {
                            Label(isSaved ? "已保存" : "保存到单词本", systemImage: isSaved ? "checkmark" : "bookmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaved)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else {
                Text("翻译失败，请重试")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .frame(width: 380)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { onDismiss() })
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content()
        }
    }
}
