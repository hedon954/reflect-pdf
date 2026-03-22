import SwiftUI

struct LibrarySidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(appState.library, id: \.id, selection: $appState.selectedDocument) { doc in
            LibraryRow(doc: doc)
                .tag(doc)
                .contextMenu {
                    Button(role: .destructive) {
                        appState.removeFromLibrary(doc)
                    } label: {
                        Label("从文库移除", systemImage: "trash")
                    }
                }
        }
        .listStyle(.sidebar)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                    DispatchQueue.main.async {
                        appState.openPDF(url: url)
                    }
                }
            }
            return true
        }
    }
}

private struct LibraryRow: View {
    let doc: PdfDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(doc.fileName)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(2)

            if doc.totalPages > 0 {
                Text("P\(doc.lastPage + 1) / \(doc.totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
