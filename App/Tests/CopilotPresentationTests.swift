import CopilotKit
import Foundation
import HeadroomModel
import HeadroomUI
import Testing

/// Settings › Tools › GitHub Copilot (1.1 §4.6, §6.4): the account row, Connect sessions's row and dialogs, and
/// the tab's copy.
@Suite struct CopilotPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: GitHub account

    @Test func notConnectedOffersConnectGitHub() {
        let row = GitHubAccountPresentation(login: nil, usage: nil, lastUpdated: nil, now: now)
        #expect(row.status == "Not connected")
        #expect(row.actions == [.connect])
        #expect(GitHubAccountPresentation.title(for: .connect) == "Connect GitHub…")
    }

    @Test func connectedSaysWhoAndWhen() {
        let usage = ToolUsage(tool: .copilot, status: .ok, account: "octocat")
        let row = GitHubAccountPresentation(login: "octocat", usage: usage, lastUpdated: now - 300, now: now)
        #expect(row.status == "Connected as @octocat · updated 5m ago")
        #expect(row.actions == [.disconnect])
        #expect(row.caption == nil)

        let fresh = GitHubAccountPresentation(login: "octocat", usage: nil, lastUpdated: nil, now: now)
        #expect(fresh.status == "Connected as @octocat")
    }

    @Test func noUsageExplainsThatGitHubHasNotReturnedData() {
        let usage = ToolUsage(tool: .copilot, status: .noIndividualUsage, account: "octocat")
        let row = GitHubAccountPresentation(login: "octocat", usage: usage, lastUpdated: now, now: now)
        #expect(row.caption == "GitHub has not returned usage for this account yet.")
    }

    @Test func anExpiredSignInOffersReconnect() {
        let usage = ToolUsage(tool: .copilot, status: .signInExpired, account: "octocat")
        let row = GitHubAccountPresentation(login: "octocat", usage: usage, lastUpdated: now, now: now)
        #expect(row.status == "Sign-in expired")
        #expect(row.actions == [.reconnect, .disconnect])
    }

    @Test func theSheetsCopyIsTheSpecs() {
        #expect(GitHubCopy.sheetTitle == "Connect GitHub")
        #expect(GitHubCopy.sheetBody == "Enter this code on GitHub to let Headroom read your Copilot usage:")
        #expect(GitHubCopy.copyAndOpen == "Copy Code and Open GitHub")
        #expect(GitHubCopy.waiting == "Waiting for GitHub…")
        #expect(GitHubCopy.connected("octocat") == "Connected as @octocat")
        #expect(DeviceFlowError.denied.message == "You declined on GitHub.")
        #expect(DeviceFlowError.expired.message == "The code expired. Try again.")
        #expect(DeviceFlowError.busy.message == "GitHub is busy. Try again in a few minutes.")
        #expect(DeviceFlowError.unavailable.message == "Sign-in with GitHub isn't available right now.")
        #expect(GitHubCopy.authorizationsURL.absoluteString == "https://github.com/settings/apps/authorizations")
    }

    // MARK: Copilot CLI

    @Test func copilotCLIRowFollowsTheBridge() {
        let notFound = CopilotCLIPresentation(state: nil, granted: false, folderReadable: false, installed: false)
        #expect(notFound.status == "Start Copilot once, then connect here")
        #expect(notFound.actions.isEmpty)

        // Sandboxed, not granted yet: Connect asks for the folder first.
        let ungranted = CopilotCLIPresentation(state: nil, granted: false, folderReadable: false, installed: true)
        #expect(ungranted.status == "Not connected")
        #expect(ungranted.actions == [.connect])

        let notConnected = CopilotCLIPresentation(state: .notInstalled, granted: true, folderReadable: true, installed: true)
        #expect(notConnected.actions == [.connect])
        #expect(CopilotCLIPresentation.title(for: .connect) == "Connect sessions…")

        let leftovers = CopilotCLIPresentation(
            state: .notInstalled, granted: true, folderReadable: true, installed: true, hasLeftovers: true
        )
        #expect(leftovers.actions == [.connect, .disconnect])

        let connected = CopilotCLIPresentation(state: .installed, granted: true, folderReadable: true, installed: true)
        #expect(connected.status == "Connected")
        #expect(connected.actions == [.disconnect])

        let outdated = CopilotCLIPresentation(state: .outdated, granted: true, folderReadable: true, installed: true)
        #expect(outdated.actions == [.update, .disconnect])

        let unreadable = CopilotCLIPresentation(state: .unreadable("Headroom can't read ~/.copilot/hooks/headroom.json"), granted: true, folderReadable: true, installed: true)
        #expect(unreadable.status.contains("can't read"))
        #expect(unreadable.actions.isEmpty)
    }

    @Test func theConnectDialogIsTheSpecsAndListsEveryChange() {
        #expect(CopilotCLIConsent.connectTitle == "Connect sessions?")
        #expect(CopilotCLIConsent.connectMessage.hasPrefix("Headroom will add ~/.copilot/hooks/headroom.json and a small script in ~/.copilot/headroom."))
        #expect(CopilotCLIConsent.connectMessage.hasSuffix("New hooks apply to sessions started after connecting."))
        #expect(CopilotCLIConsent.connectMessage.contains("never prompts"))
        let text = CopilotCLIConsent.text("Intro.", changes: [
            .init(verb: "Create", path: "~/.copilot/hooks/headroom.json", detail: "Runs the script."),
            .init(verb: "Replace", path: "~/.copilot/headroom/bridge.sh", detail: "The script."),
        ])
        #expect(text == "Intro.\n\n• Create ~/.copilot/hooks/headroom.json: Runs the script.\n• Replace ~/.copilot/headroom/bridge.sh: The script.")
        #expect(CopilotCLIConsent.text("Intro.", changes: []) == "Intro.")
        #expect(CopilotCLIState.installed.isConnected && CopilotCLIState.outdated.isConnected)
        #expect(!CopilotCLIState.notInstalled.isConnected)
    }

    // MARK: Settings copy (1.1 §6.4, §14.7)

    @Test func theToolsFooterDropsWhatDoesntShip() {
        #expect(SettingsCopy.toolsFooter(copilotUsage: true, copilotCLI: true)
            == "Headroom only reads these folders. Connect terminal and Connect sessions add files only after asking you, and Copilot usage talks to GitHub only when you connect it.")
        #expect(SettingsCopy.toolsFooter(copilotUsage: false, copilotCLI: true)
            == "Headroom only reads these folders. Connect terminal and Connect sessions add files only after asking you.")
        #expect(SettingsCopy.toolsFooter(copilotUsage: true, copilotCLI: false)
            == "Headroom only reads these folders. Connect terminal adds files only after asking you, and Copilot usage talks to GitHub only when you connect it.")
    }

    /// Headroom is about AI usage and plan limits, not just coding (1.1 §14.7).
    @Test func settingsNeverSaysAICoding() {
        let texts = [
            SettingsCopy.intro, SettingsCopy.showMomentsDetail, SettingsCopy.sampleDataDetail, SettingsCopy.ringsShowCaption,
            SettingsCopy.gaugePerToolCaption, SettingsCopy.widgetsHowTo, SettingsCopy.codexCaption,
            SettingsCopy.copilotCLICaption, SettingsCopy.nonAffiliation, GitHubCopy.usageCaption, GitHubCopy.planCaption,
            CopilotCLIConsent.connectMessage, CopilotCLIConsent.disconnectMessage,
        ]
        for text in texts {
            #expect(!text.localizedCaseInsensitiveContains("AI coding"), "\(text)")
        }
        #expect(SettingsCopy.nonAffiliation == "Headroom isn't made by or affiliated with Anthropic, OpenAI or GitHub.")
        #expect(SettingsCopy.codexCaption == "Headroom reads only Codex's session files. The folder also holds your Codex sign-in; Headroom never opens it and never contacts OpenAI.")
    }
}

/// Plan › Custom's number (1.1 §4.5): whole numbers as the user's region writes them. A misread would pass the
/// 1…1,000,000 range check and show a wrong percent, so anything unclear is no number.
@Suite struct CustomAllowanceTextTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")
    private let swiss = Locale(identifier: "de_CH")

    @Test func wholeNumbersWithTheRegionsGrouping() {
        #expect(CustomAllowanceText.value("1500", locale: english) == 1500)
        #expect(CustomAllowanceText.value("1,500", locale: english) == 1500)
        #expect(CustomAllowanceText.value(" 1,000,000 ", locale: english) == 1_000_000)
        #expect(CustomAllowanceText.value("1.500", locale: german) == 1500)
        #expect(CustomAllowanceText.value("1500", locale: german) == 1500)
        #expect(CustomAllowanceText.value("1 500", locale: french) == 1500)
        #expect(CustomAllowanceText.value("1\u{202F}500", locale: french) == 1500)
        #expect(CustomAllowanceText.value("1'500", locale: swiss) == 1500)
        #expect(CustomAllowanceText.value("١٥٠٠", locale: english) == 1500)
    }

    /// The reviewer's case: "1.500" is 1,500 in German, never 1.5; and in English it isn't a number at all.
    @Test func decimalsAndForeignSeparatorsAreNoNumber() {
        #expect(CustomAllowanceText.value("1.500", locale: english) == nil)
        #expect(CustomAllowanceText.value("1.5", locale: english) == nil)
        #expect(CustomAllowanceText.value("1,5", locale: german) == nil)
        #expect(CustomAllowanceText.value("1,500", locale: german) == nil)
        #expect(CustomAllowanceText.value("15,00", locale: english) == nil)
        #expect(CustomAllowanceText.value("1,5000", locale: english) == nil)
        #expect(CustomAllowanceText.value(",500", locale: english) == nil)
        #expect(CustomAllowanceText.value("1500 credits", locale: english) == nil)
        #expect(CustomAllowanceText.value("-5", locale: english) == nil)
        #expect(CustomAllowanceText.value("1²", locale: english) == nil)
        #expect(CustomAllowanceText.value("", locale: english) == nil)
    }

    /// onAppear shows the saved value; reading it back gives the same number in every region, so nothing is saved
    /// again with another value.
    @Test func theSavedValueReadsBack() {
        for locale in [english, german, french, swiss] {
            let text = CustomAllowanceText.text(for: 1500, locale: locale)
            #expect(text == "1500")
            #expect(CustomAllowanceText.value(text, locale: locale) == 1500)
        }
        #expect(CustomAllowanceText.text(for: nil) == "")
        // A fraction an older version saved: shown, but never read back as another number.
        #expect(CustomAllowanceText.value(CustomAllowanceText.text(for: 1.5, locale: german), locale: german) == nil)
        #expect(CustomAllowanceText.value(CustomAllowanceText.text(for: 1.5, locale: english), locale: english) == nil)
    }
}
