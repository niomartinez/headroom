import HeadroomModel
import SwiftUI

/// A short, optional first-run setup. All grants and connection confirmations use Settings' existing actions.
struct OnboardingView: View {
    let model: AppModel
    let terminal: TerminalConnection
    let copilotCLI: CopilotCLIActions?
    let navigation: SettingsNavigation
    let grantAccess: (HeadroomFolder) -> Void
    let close: () -> Void

    @State private var selectedTool: ToolID?
    @State private var hasChosenTool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTool.map { "Connect \($0.shortName)" } ?? "Welcome to Headroom")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(selectedTool == nil
                     ? "See AI limits and session activity in your menu bar. Choose a tool to get started; you can add more anytime."
                     : "Connect what you use below. Each connection is optional, and you can change it in Settings → Tools.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            if let selectedTool {
                ToolsSettingsTab(model: model, terminal: terminal, copilotCLI: copilotCLI,
                                 grantAccess: grantAccess, onlyTool: selectedTool)
            } else {
                VStack(spacing: 12) {
                    choice(.claude, detail: "Plan limits and Claude Code sessions", symbol: "asterisk")
                    choice(.codex, detail: "Plan limits and sessions from the app or CLI", symbol: "chevron.left.forwardslash.chevron.right")
                    choice(.copilot, detail: "GitHub usage and desktop or CLI sessions", symbol: "sparkles")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text(selectedTool == .copilot
                     ? "Connect session activity to see completions. After connecting, start a new Copilot session. GitHub sign-in only connects usage."
                     : "Click Headroom in the menu bar to see your sessions. Open Headroom from Applications to return to Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if selectedTool != nil {
                        Button("Add another tool") { self.selectedTool = nil }
                        Spacer()
                        Button("Done") { finish(sample: false) }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Set up later") { finish(sample: false) }
                        Spacer()
                        Button("Try sample data") { finish(sample: true) }
                    }
                }
            }
            .padding(24)
        }
    }

    private func choice(_ tool: ToolID, detail: String, symbol: String) -> some View {
        Button {
            selectedTool = tool
            if !hasChosenTool, navigation.isFirstRun {
                // Start with the user's choice, rather than the legacy Claude-only default.
                model.setTrackClaude(tool == .claude)
                model.setTrackCodex(tool == .codex)
                model.setTrackCopilot(tool == .copilot)
            }
            hasChosenTool = true
            switch tool {
            case .claude: model.setTrackClaude(true)
            case .codex: model.setTrackCodex(true)
            case .copilot: model.setTrackCopilot(true)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.fullName).fontWeight(.semibold)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Set up \(tool.fullName). \(detail)")
    }

    private func finish(sample: Bool) {
        if sample { model.setShowSampleData(true) }
        navigation.finishOnboarding()
        close()
    }
}
