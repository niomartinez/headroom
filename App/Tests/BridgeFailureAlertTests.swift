import SetupKit
import Testing

/// What Connect / Disconnect terminal say when they can't do their job (spec §2.6).
@Suite struct BridgeFailureAlertTests {
    private static let outsideTarget = "/Users/tester/dotfiles/claude/settings.json"

    /// A settings.json that links outside the granted folder is fine as it is: the sandbox just
    /// can't open it. The alert must not tell the user to fix or remove it (F10).
    @Test func aSettingsFileOutsideTheGrantIsNotCalledBroken() {
        let error = BridgeInstallError.settingsOutsideGrant(target: Self.outsideTarget)
        let text = BridgeFailureAlert.message(for: error)
        #expect(text == error.localizedDescription)
        #expect(text.contains(Self.outsideTarget))
        #expect(!text.contains("Fix or remove"))
    }

    @Test func anUnreadableSettingsFileIsExplained() {
        let text = BridgeFailureAlert.message(for: BridgeInstallError.settingsUnreadable("line 3: unexpected }"))
        #expect(text == "~/.claude/settings.json couldn't be read (line 3: unexpected }). Nothing was changed. Fix or remove the file, then try again.")
    }

    @Test func aFailedWriteShowsItsReason() {
        let reason = "Headroom couldn't delete ~/.claude/headroom: Permission denied"
        #expect(BridgeFailureAlert.message(for: BridgeInstallError.writeFailed(reason)) == reason)
    }

    /// Settings offers no button while settings.json can't be read, and the panel's Connect
    /// terminal can't hide itself (HeadroomUI draws it). It explains why instead of asking to change
    /// a file Headroom can't change, and says nothing about fixing a file that may be fine (F10).
    @Test func connectExplainsUnreadableSettingsInsteadOfAsking() {
        let reason = "settings.json links to \(Self.outsideTarget), outside the folders Headroom can access"
        let message = BridgeFailureAlert.connectUnavailableMessage(for: .settingsUnreadable(reason))
        #expect(message == "Headroom can't read ~/.claude/settings.json (\(reason)), so it can't add its status line and hooks. Nothing was changed.")
    }

    @Test func connectIsAvailableInEveryOtherState() {
        let states: [BridgeInstallState?] = [nil, .notInstalled, .installed, .outdated]
        for state in states {
            #expect(BridgeFailureAlert.connectUnavailableMessage(for: state) == nil)
        }
    }

    @Test func titlesNameTheAction() {
        #expect(BridgeFailureAlert.connectTitle == "Headroom couldn't connect the terminal")
        #expect(BridgeFailureAlert.disconnectTitle == "Headroom couldn't disconnect the terminal")
    }
}
