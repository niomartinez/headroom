import SwiftUI

/// Settings › Terminal: the bridge's state and Connect / Update / Disconnect (spec §2.6).
struct TerminalConnectionRow: View {
    let presentation: TerminalBridgePresentation
    let isBusy: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminal sessions")
                    Text(presentation.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                ForEach(presentation.actions, id: \.self) { action in
                    Button(title(for: action)) { perform(action) }
                        .disabled(isBusy)
                }
            }
            Text("Lets Headroom see sessions you run with claude in a terminal, and exact limit reset times. Connect adds a status line and hooks to ~/.claude/settings.json, backing the file up the first time. New terminal sessions pick it up.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(for action: TerminalBridgePresentation.Action) -> String {
        switch action {
        case .connect: "Connect…"
        case .update: "Update…"
        case .disconnect: "Disconnect"
        }
    }

    private func perform(_ action: TerminalBridgePresentation.Action) {
        switch action {
        case .connect, .update: connect()
        case .disconnect: disconnect()
        }
    }
}
