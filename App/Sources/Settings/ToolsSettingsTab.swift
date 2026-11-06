import SwiftUI
import HeadroomModel

/// Settings › Tools (1.1 §6.4): what Headroom reads for Claude, OpenAI Codex and GitHub Copilot, each with its
/// tracking toggle, folders and connections. Taller than a small screen with all three tools, so it scrolls in a
/// window of fixed height.
struct ToolsSettingsTab: View {
    static let height: CGFloat = 620

    let model: AppModel
    let terminal: TerminalConnection
    let copilotCLI: CopilotCLIActions?
    let grantAccess: (HeadroomFolder) -> Void
    /// First-run setup focuses on one tool, using the same connection controls as Settings.
    var onlyTool: ToolID? = nil

    private var access: AccessManager { model.access }

    var body: some View {
        Form {
            if onlyTool == nil || onlyTool == .claude { claude }
            if onlyTool == nil || onlyTool == .codex { codex }
            if onlyTool == nil || onlyTool == .copilot { copilot }
        }
        .formStyle(.grouped)
        .frame(height: onlyTool == nil ? Self.height : 360)
    }

    // MARK: Claude

    private var claude: some View {
        Section("Claude") {
            Toggle(SettingsCopy.trackClaude, isOn: Binding(get: { model.tracking.claude }, set: { model.setTrackClaude($0) }))
            ForEach(HeadroomFolder.claude) { folder in
                folderRow(folder)
            }
            TerminalConnectionRow(
                presentation: TerminalBridgePresentation(
                    state: model.bridgeState,
                    claudeFolderReadable: access.state.claudeDirectoryReadable,
                    claudeCodeInstalled: access.claudeCodeInstalled,
                    hasLeftovers: model.hasBridgeLeftovers
                ),
                isBusy: model.isChangingBridge,
                connect: terminal.connect,
                disconnect: terminal.disconnect
            )
        }
    }

    // MARK: OpenAI Codex

    private var codex: some View {
        Section {
            Toggle(SettingsCopy.trackCodex, isOn: Binding(get: { model.tracking.tracksCodex }, set: { model.setTrackCodex($0) }))
            folderRow(.codex)
            caption(SettingsCopy.codexCaption)
        } header: {
            Text("OpenAI Codex")
        }
    }

    // MARK: GitHub Copilot

    private var copilot: some View {
        Section {
            Toggle(SettingsCopy.trackCopilot, isOn: Binding(get: { model.tracking.copilot }, set: { model.setTrackCopilot($0) }))
            if model.copilot.isAvailable {
                CopilotAccountRow(account: model.copilot, now: model.now)
                if model.copilot.usage?.organizationSeat != true {
                    CopilotPlanPicker(account: model.copilot)
                }
                caption(GitHubCopy.usageCaption)
            }
            if let copilotCLI {
                CopilotCLIRow(
                    presentation: CopilotCLIPresentation(
                        state: model.copilotCLIState,
                        granted: access.hasGrant(.copilotCLI),
                        folderReadable: access.state.copilotDirectoryReadable,
                        installed: access.state.copilotCLIInstalled,
                        hasLeftovers: model.hasCopilotCLILeftovers
                    ),
                    isBusy: model.isChangingCopilotCLI,
                    connect: copilotCLI.connect,
                    disconnect: copilotCLI.disconnect
                )
                caption(SettingsCopy.copilotCLICaption)
            }
        } header: {
            Text("GitHub Copilot")
        } footer: {
            Text(access.isSandboxed
                ? SettingsCopy.toolsFooter(copilotUsage: model.copilot.isAvailable, copilotCLI: copilotCLI != nil)
                : SettingsCopy.developmentBuildFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func folderRow(_ folder: HeadroomFolder) -> some View {
        FolderAccessRow(
            folder: folder,
            presentation: FolderAccessPresentation(
                folder: folder,
                status: access.status(of: folder),
                isSandboxed: access.isSandboxed,
                desktopAppInstalled: access.state.desktopAppInstalled,
                claudeCodeInstalled: access.claudeCodeInstalled,
                codexInstalled: access.state.codexInstalled
            ),
            grant: { grantAccess(folder) }
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
