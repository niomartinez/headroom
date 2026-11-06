import SwiftUI

/// One folder in Settings › Folder access: what it's for, whether Headroom can read it, and a
/// Grant access button in sandboxed builds. A folder Headroom doesn't need (the Claude app's
/// folder without the Claude app) shows a note instead.
struct FolderAccessRow: View {
    let folder: HeadroomFolder
    let presentation: FolderAccessPresentation
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title)
                Text(folder.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(folder.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let note = presentation.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let status = presentation.status {
                Label(status.text, systemImage: status.symbol)
                    .font(.caption)
                    .foregroundStyle(color(for: status.tone))
                    .fixedSize()
            }
            if presentation.showsGrantButton {
                Button("Grant access", action: grant)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(for tone: FolderAccessPresentation.Tone) -> Color {
        switch tone {
        case .good: .green
        case .attention: .orange
        case .neutral: .secondary
        }
    }
}
