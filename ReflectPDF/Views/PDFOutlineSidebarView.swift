import SwiftUI
import PDFKit

struct PDFOutlineSidebarView: View {
    let document: PDFKit.PDFDocument
    @EnvironmentObject private var appState: AppState

    /// Page index of the deepest outline item that starts on or before the current page.
    private var activePageIndex: Int {
        guard let root = document.outlineRoot else { return -1 }
        var best = -1
        func traverse(_ item: PDFOutline) {
            for i in 0 ..< item.numberOfChildren {
                guard let child = item.child(at: i) else { continue }
                if let page = child.destination?.page {
                    let idx = document.index(for: page)
                    if idx != NSNotFound && idx <= appState.currentPageIndex && idx > best {
                        best = idx
                    }
                }
                traverse(child)
            }
        }
        traverse(root)
        return best
    }

    var body: some View {
        Group {
            if let root = document.outlineRoot, root.numberOfChildren > 0 {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            OutlineChildren(item: root, doc: document,
                                            activePageIndex: activePageIndex, depth: 0)
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: activePageIndex) { newIndex in
                        guard newIndex >= 0 else { return }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("此 PDF 无目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Recursive children

private struct OutlineChildren: View {
    let item: PDFOutline
    let doc: PDFKit.PDFDocument
    let activePageIndex: Int
    let depth: Int

    var body: some View {
        ForEach(0 ..< item.numberOfChildren, id: \.self) { i in
            if let child = item.child(at: i) {
                OutlineRow(item: child, doc: doc,
                           activePageIndex: activePageIndex, depth: depth)
            }
        }
    }
}

// MARK: - Single row

private struct OutlineRow: View {
    let item: PDFOutline
    let doc: PDFKit.PDFDocument
    let activePageIndex: Int
    let depth: Int

    @State private var isExpanded = true

    private var myPageIndex: Int {
        guard let page = item.destination?.page else { return -1 }
        let idx = doc.index(for: page)
        return idx == NSNotFound ? -1 : idx
    }

    private var isActive: Bool { myPageIndex == activePageIndex && myPageIndex >= 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Expand/collapse chevron
                if item.numberOfChildren > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14)
                }

                // Tapping the label navigates
                Button { navigate() } label: {
                    HStack {
                        Text(item.label ?? "")
                            .font(depth == 0 ? .callout.weight(.medium) : .caption)
                            .foregroundStyle(isActive ? Color.accentColor : (depth == 0 ? Color.primary : Color.secondary))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .background(
                isActive
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            // ID used by ScrollViewReader to scroll to active item
            .id(myPageIndex)

            if item.numberOfChildren > 0 && isExpanded {
                OutlineChildren(item: item, doc: doc,
                                activePageIndex: activePageIndex, depth: depth + 1)
            }
        }
    }

    private func navigate() {
        guard let page = item.destination?.page else { return }
        let pageIndex = doc.index(for: page)
        guard pageIndex != NSNotFound else { return }
        NotificationCenter.default.post(
            name: .outlineNavigate,
            object: nil,
            userInfo: ["pageIndex": pageIndex, "filePath": doc.documentURL?.path ?? ""]
        )
    }
}

extension Notification.Name {
    static let outlineNavigate = Notification.Name("outlineNavigate")
}
