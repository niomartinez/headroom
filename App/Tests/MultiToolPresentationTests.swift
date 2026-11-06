import Foundation
import HeadroomModel
import HeadroomSamples
import HeadroomUI
import Testing

/// What the pill, its VoiceOver label and tooltip, and the panel get with more than Claude tracked (1.1 §6.1–§6.3),
/// and that Claude-only stays 1.0's.
@Suite struct MultiToolPresentationTests {
    private let now = SampleData.fixed.now
    private var sample: SampleData { SampleData.fixed }

    // MARK: VoiceOver and tooltip (1.1 §6.1)

    @Test func withSeveralToolsTheLabelHasASentencePerTool() {
        let snapshot = sample.multiTool
        let label = AccessibilitySummary.label(for: snapshot, moment: nil, now: now)
        let toolTip = PillModel(snapshot: snapshot, moment: nil, now: now).toolTip
        #expect(toolTip != nil)
        #expect(label.contains("Claude weekly 89%, 5-hour 14%. Codex weekly 94%. Copilot 34% of monthly credits"))
        #expect(label.hasPrefix("Headroom. "))
        #expect(label.contains("Sessions: "))
        #expect(label.hasSuffix("."))
        // The tooltip is the same limits, without the sessions.
        #expect(label.contains(String(toolTip!.dropLast())))
    }

    @Test func claudeOnlyKeepsTheOneLabelAndNoTooltip() {
        let snapshot = sample.claudeOnlyShowcase(terminalConnected: true)
        let label = AccessibilitySummary.label(for: snapshot, moment: nil, now: now)
        #expect(label.contains("Weekly limit 81% used"))
        #expect(!label.contains("Claude weekly"))
        #expect(PillModel(snapshot: snapshot, moment: nil, now: now).toolTip == nil)
    }

    @Test func missingCodexAccessIsSaid() {
        var snapshot = sample.multiTool
        snapshot.codex = ToolUsage(tool: .codex, status: .needsAccess)
        snapshot.issues = [.codexFolderUnavailable]
        #expect(AccessibilitySummary.label(for: snapshot, moment: nil, now: now).contains("Needs access to ~/.codex to see Codex"))
        snapshot.issues.insert(.claudeCodeFolderUnavailable)
        #expect(AccessibilitySummary.label(for: snapshot, moment: nil, now: now).contains("Needs access to your Claude and Codex folders"))
    }

    @Test func anEmptyListIsSaidInThePanelsWords() {
        var both = sample.multiTool
        both.sessions = []
        #expect(AccessibilitySummary.label(for: both, moment: nil, now: now).contains("No sessions running"))

        let codexOnly = sample.withoutClaude(codex: sample.codex())
        #expect(AccessibilitySummary.label(for: codexOnly, moment: nil, now: now).contains("No Codex sessions running"))

        var unreadable = sample.multiTool
        unreadable.sessions = []
        unreadable.issues = [.codexSessionsUnreadable]
        #expect(AccessibilitySummary.label(for: unreadable, moment: nil, now: now).contains("Can't read Codex sessions"))
    }

    /// Limit moments name their tool with several tools tracked; session moments name it for VoiceOver (1.1 §6.2).
    @Test func momentsNameTheirToolWithSeveralTools() {
        let tools: [ToolID] = [.claude, .codex]
        #expect(AccessibilitySummary.text(for: .toolLimitCrossed(tool: .codex, window: .weekly, percent: 90), trackedTools: tools)
            == "Codex weekly at 90%")
        #expect(AccessibilitySummary.text(for: .limitCrossed(kind: .fiveHour, percent: 90), trackedTools: tools)
            == "Claude 5-hour at 90%")
        #expect(AccessibilitySummary.text(for: .sessionFinished(sessionID: "codex:01a0", name: "ledger"), trackedTools: tools)
            == "Codex session ledger finished")
        // Claude only: 1.0's words.
        #expect(AccessibilitySummary.text(for: .limitCrossed(kind: .weekly, percent: 90)) == "Weekly limit at 90%")
        #expect(AccessibilitySummary.text(for: .sessionNeedsInput(sessionID: "a", name: "Write docs"), trackedTools: [.claude])
            == "Write docs needs your input")
    }

    // MARK: Redraws (1.1 §6.1, §6.3)

    @Test func changingRingsShowOrGaugePerToolRedrawsThePill() {
        let snapshot = sample.multiTool
        let automatic = PillDrawKey(snapshot: snapshot, moment: nil, now: now)
        #expect(PillDrawKey(snapshot: snapshot, moment: nil, now: now, tool: .codex) != automatic)
        #expect(PillDrawKey(snapshot: snapshot, moment: nil, now: now, gaugePerTool: true) != automatic)
        // Automatic already shows Claude.
        #expect(PillDrawKey(snapshot: snapshot, moment: nil, now: now, tool: .claude) == automatic)
    }

    /// With only Claude tracked the choices can't change anything: nothing to redraw.
    @Test func claudeOnlyPillsIgnoreTheChoices() {
        let snapshot = sample.claudeOnlyShowcase(terminalConnected: true)
        let plain = PillDrawKey(snapshot: snapshot, moment: nil, now: now)
        #expect(PillDrawKey(snapshot: snapshot, moment: nil, now: now, tool: .codex, gaugePerTool: true) == plain)
    }

    @Test func theHeadersToolAndTheCodexOfferRedrawThePanel() {
        let snapshot = sample.multiTool
        let plain = PanelDrawKey(snapshot: snapshot, now: now)
        #expect(PanelDrawKey(snapshot: snapshot, now: now, tool: .copilot) != plain)
        let claudeOnly = sample.claudeOnlyShowcase(terminalConnected: true)
        #expect(PanelDrawKey(snapshot: claudeOnly, now: now, showsCodexOffer: true) != PanelDrawKey(snapshot: claudeOnly, now: now))
    }

    // MARK: Sample data offer

    /// A Codex-only user has data: no "Preview with sample data".
    @Test func codexDataCountsAsData() {
        let codexOnly = sample.withoutClaude(codex: sample.codex())
        let access = AccessState(claudeDirectoryReadable: false, desktopDirectoryReadable: false, desktopAppInstalled: false)
        #expect(!SampleDataMode.foundNoClaudeData(codexOnly, access: access))
        var readable = access
        readable.codexDirectoryReadable = true
        #expect(!SampleDataMode.foundNoClaudeData(sample.withoutClaude(), access: readable))
        #expect(SampleDataMode.foundNoClaudeData(sample.withoutClaude(), access: access))
    }
}
