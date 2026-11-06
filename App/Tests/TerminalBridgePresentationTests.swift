import SetupKit
import Testing

@Suite struct TerminalBridgePresentationTests {
    @Test func notInstalledOffersConnect() {
        let presentation = TerminalBridgePresentation(state: .notInstalled, claudeFolderReadable: true)
        #expect(presentation.status == "Not connected")
        #expect(presentation.actions == [.connect])
    }

    @Test func installedOffersDisconnect() {
        let presentation = TerminalBridgePresentation(state: .installed, claudeFolderReadable: true)
        #expect(presentation.status == "Connected")
        #expect(presentation.actions == [.disconnect])
    }

    @Test func outdatedOffersUpdateAndDisconnect() {
        let presentation = TerminalBridgePresentation(state: .outdated, claudeFolderReadable: true)
        #expect(presentation.status == "Connected, update available")
        #expect(presentation.actions == [.update, .disconnect])
    }

    @Test func unreadableSettingsExplainWhyAndOfferNothing() {
        let presentation = TerminalBridgePresentation(state: .settingsUnreadable("line 3: unexpected }"), claudeFolderReadable: true)
        #expect(presentation.status == "Can't read ~/.claude/settings.json (line 3: unexpected })")
        #expect(presentation.actions.isEmpty)
    }

    /// A Disconnect that couldn't delete everything leaves `~/.claude/headroom`, or a renamed copy,
    /// behind while settings.json no longer names the bridge. Offer Disconnect again to finish (F09).
    @Test func leftoversFromAnEarlierConnectionOfferDisconnectToo() {
        let presentation = TerminalBridgePresentation(state: .notInstalled, claudeFolderReadable: true, hasLeftovers: true)
        #expect(presentation.status == "Not connected (files left from an earlier connection)")
        #expect(presentation.actions == [.connect, .disconnect])
    }

    /// Only "not connected" has leftovers: a connected bridge's folder is its own, and Disconnect
    /// can't run while settings.json can't be read.
    @Test func leftoversChangeNothingElse() {
        let states: [BridgeInstallState?] = [nil, .installed, .outdated, .settingsUnreadable("line 3: unexpected }")]
        for state in states {
            #expect(TerminalBridgePresentation(state: state, claudeFolderReadable: true, hasLeftovers: true)
                == TerminalBridgePresentation(state: state, claudeFolderReadable: true))
        }
        #expect(TerminalBridgePresentation(state: .notInstalled, claudeFolderReadable: false, hasLeftovers: true)
            == TerminalBridgePresentation(state: .notInstalled, claudeFolderReadable: false))
    }

    @Test func missingFolderAccessComesFirst() {
        let presentation = TerminalBridgePresentation(state: .installed, claudeFolderReadable: false)
        #expect(presentation.status == "Needs access to the .claude folder")
        #expect(presentation.actions.isEmpty)
    }

    /// Without `~/.claude` there is nothing to connect and no folder to ask for.
    @Test func withoutClaudeCodeThereIsNothingToConnect() {
        let presentation = TerminalBridgePresentation(state: nil, claudeFolderReadable: false, claudeCodeInstalled: false)
        #expect(presentation.status == "Claude Code not found")
        #expect(presentation.actions.isEmpty)
    }

    @Test func unknownStateIsChecking() {
        let presentation = TerminalBridgePresentation(state: nil, claudeFolderReadable: true)
        #expect(presentation.status == "Checking…")
        #expect(presentation.actions.isEmpty)
    }

    @Test func consentExplainsExactlyWhatChanges() {
        let message = BridgeConsent.message
        #expect(message.contains("~/.claude/settings.json"))
        #expect(message.contains("statusLine"))
        #expect(message.contains("~/.claude/headroom/bridge.sh"))
        #expect(message.contains("~/.claude/settings.json.headroom-backup"))
        #expect(message.contains("New terminal sessions"))
        #expect(message.contains("never your prompts"))
    }

    /// The dialog names exactly the hooks the installer adds, so it stays right when SetupKit adds
    /// one (spec §2.5 lists PostToolUse since the first build round).
    @Test func consentNamesEveryHookTheInstallerAdds() {
        let message = BridgeConsent.message
        for event in BridgeInstaller.hookEvents {
            #expect(message.contains(event))
        }
        #expect(message.contains(BridgeConsent.list(BridgeInstaller.hookEvents)))
    }

    @Test func listsReadNaturally() {
        #expect(BridgeConsent.list([]) == "")
        #expect(BridgeConsent.list(["Stop"]) == "Stop")
        #expect(BridgeConsent.list(["Stop", "SessionEnd"]) == "Stop and SessionEnd")
        #expect(BridgeConsent.list(["SessionStart", "Stop", "SessionEnd"]) == "SessionStart, Stop and SessionEnd")
    }

    /// Claude Code snapshots hooks when a session starts, so sessions already running keep calling
    /// the deleted bridge.sh until they restart (spec §2.6).
    @Test func disconnectExplainsRunningSessionsInOneSentence() {
        #expect(BridgeDisconnectNotice.title == "Terminal disconnected")
        let message = BridgeDisconnectNotice.message
        #expect(message.contains("already running"))
        #expect(message.contains("until you restart them"))
        #expect(message.contains("harmless"))
        // Claude Code sessions in the Claude desktop app read the same settings.json (F40).
        #expect(message.hasPrefix("Claude Code sessions that are already running"))
        #expect(message.contains("in a terminal or in the Claude app"))
        #expect(message.hasSuffix("."))
        #expect(!message.dropLast().contains(". "))
    }

    /// Claude Code keeps running the bridge after Headroom.app is deleted, until the entries are
    /// removed (App Review Guideline 2.4.5, 2.5.2; docs/app-store.md §8). Say so before connecting.
    @Test func consentSaysToDisconnectBeforeDeletingHeadroom() {
        let message = BridgeConsent.message
        #expect(message.contains("Disconnect before you delete Headroom"))
        #expect(message.contains("keeps running the script"))
    }

    /// Spec §2.6 keeps the first backup ever made and never overwrites it, so on a second Connect
    /// (or an Update) the backup holds the settings from before the first Connect, not the
    /// current ones. The dialog must not promise a backup of the current settings.
    @Test func consentDescribesTheBackupThatIsActuallyKept() {
        let message = BridgeConsent.message
        #expect(!message.contains("backup of your current settings"))
        #expect(message.contains("first time"))
        #expect(message.contains("never overwrites"))
    }
}
