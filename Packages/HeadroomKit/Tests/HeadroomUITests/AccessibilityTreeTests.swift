import AppKit
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// The panel's accessibility tree as VoiceOver gets it: the real view hosted in an off-screen
/// window, read in-process. SwiftUI builds the tree only for an assistive client, so the app
/// flags itself as one (`AXEnhancedUserInterface`, what VoiceOver sets).
@MainActor @Suite(.serialized) struct AccessibilityTreeTests {
    let now = Fixture.now

    struct Node: Equatable, CustomStringConvertible {
        var role: String
        var label: String?
        var value: String?
        var help: String?

        var description: String {
            [role, label.map { "label=\($0)" }, value.map { "value=\($0)" }, help.map { "help=\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    @Test func rowsSpeakTheirStateAndSectionsAreHeadings() throws {
        let sessions = [
            Fixture.session(
                "w1", .working, name: "Refactor invoice export", path: "/Users/me/code/ledger",
                context: Fixture.context(720_000, of: 1_000_000, model: "claude-opus-5-5")
            ),
            Fixture.session(
                "t1", .waitingForInput, name: "Rename keys", path: "/Users/me/code/harbor", origin: .terminal,
                context: Fixture.context(130_000, of: 200_000, model: "claude-opus-5-5")
            ),
            Fixture.session("i1", .idle, name: "Sketch copy"),
        ]
        let plan = PlanUsage(
            fiveHour: Fixture.reading(.fiveHour, 14, resetsAt: now.addingTimeInterval(45 * 60), estimated: true),
            weekly: Fixture.reading(.weekly, 89, resetsAt: Fixture.date(2026, 9, 27, 19, 0))
        )
        let nodes = try tree(of: PanelView(snapshot: Fixture.snapshot(plan: plan, sessions: sessions), now: now, actions: .none))
        let texts = nodes.filter { $0.role != "AXGroup" }

        let headings = texts.filter { $0.role == "AXHeading" }.compactMap(\.label)
        #expect(headings == ["Working", "Needs you", "Idle"], "\(texts)")

        let rows = texts.filter { $0.label?.hasSuffix(", working") == true || $0.label?.hasSuffix(", needs input") == true
            || $0.label?.hasSuffix(", idle") == true }
        #expect(rows == [
            Node(role: "AXStaticText", label: "Refactor invoice export, ledger, working", value: "context 72% full",
                 help: "720k of 1M tokens · claude-opus-5-5"),
            Node(role: "AXStaticText", label: "Rename keys, harbor, terminal, needs input", value: "context 65% full",
                 help: "130k of 200k tokens · claude-opus-5-5"),
            Node(role: "AXStaticText", label: "Sketch copy, idle", value: nil, help: nil),
        ], "\(texts)")

        let limits = texts.filter { $0.label?.hasSuffix(" limit") == true }
        #expect(limits.map(\.label) == ["Weekly limit", "5-hour limit"], "\(texts)")
        // The panel formats in the machine's time zone, so only the weekly value's start is fixed.
        let weekly = limits.first?.value ?? ""
        #expect(weekly.hasPrefix("89% used, resets ") && !weekly.contains("~") && !weekly.contains("about"), "\(weekly)")
        #expect(limits.last?.value == "14% used, resets in about 45 minutes", "\(texts)")
    }

    /// 1.1 §14.3: a row the app can open is a button whose hint (the tooltip) says where to; the rest stay text.
    @Test func openableRowsAreButtonsWithAHint() throws {
        let sessions = [
            Fixture.session("w1", .working, name: "Refactor invoice export", path: "/Users/me/code/ledger"),
            Fixture.session("i1", .idle, name: "Sketch copy"),
        ]
        let actions = PanelActions(sessionOpenTitle: { $0 == "w1" ? "Open in Claude" : nil })
        let nodes = try tree(of: PanelView(snapshot: Fixture.snapshot(plan: .empty, sessions: sessions), now: now, actions: actions))
        let rows = nodes.filter { $0.label?.hasSuffix(", working") == true || $0.label?.hasSuffix(", idle") == true }
        #expect(rows.map(\.role) == ["AXButton", "AXStaticText"], "\(rows)")
        #expect(rows.map(\.help) == ["Open in Claude", nil], "\(rows)")
    }

    /// 1.1 §14.4: waiting rows offer "Dismiss" to VoiceOver, dismissed ones "Show in Needs you again", and say which.
    @Test func needsYouRowsHaveTheirActions() throws {
        let sessions = [
            Fixture.session("t1", .waitingForInput, name: "harbor", origin: .terminal),
            Fixture.session("t2", .idle, name: "atlas", origin: .terminal),
            Fixture.session("i1", .idle, name: "Sketch copy"),
        ]
        let view = PanelView(
            snapshot: Fixture.snapshot(plan: .empty, sessions: sessions), now: now, actions: .none,
            unseenIDs: ["t1"], dismissedIDs: ["t2"]
        )
        let (nodes, actions) = try treeWithActions(of: view)
        let labels = nodes.compactMap(\.label)
        #expect(labels.contains("harbor, terminal, needs input, new"), "\(labels)")
        #expect(labels.contains("atlas, terminal, needs input, dismissed"), "\(labels)")
        #expect(actions["harbor, terminal, needs input, new"] == ["Dismiss"])
        #expect(actions["atlas, terminal, needs input, dismissed"] == ["Show in Needs you again"])
        #expect(actions["Sketch copy, idle"] ?? [] == [])
    }

    @Test func missingNumbersSayWhy() throws {
        let nodes = try tree(of: PanelView(snapshot: Fixture.snapshot(plan: .empty), now: now, actions: .none))
        let limits = nodes.filter { $0.label?.hasSuffix(" limit") == true }
        #expect(limits.map(\.value) == ["no data yet", "no data yet"], "\(nodes.filter { $0.role != "AXGroup" })")
    }

    @Test func multiToolPanelSpeaksEachTool() throws {
        let sessions = [
            Fixture.toolSession("a", .working, tool: .claude, name: "ledger"),
            Fixture.toolSession("b", .idle, tool: .codex, name: "website"),
        ]
        let snapshot = Fixture.tools(codex: Fixture.codex(), copilot: Fixture.copilot(status: .notConnected), sessions: sessions)
        let nodes = try tree(of: PanelView(snapshot: snapshot, now: now, actions: .none))
        let texts = nodes.filter { $0.role != "AXGroup" }

        #expect(texts.filter { $0.role == "AXHeading" }.compactMap(\.label) == ["Claude", "Working", "Idle"], "\(texts)")
        let codex = try #require(texts.first { $0.label == "Codex limits" }, "\(texts)")
        #expect(codex.value?.hasPrefix("weekly 94% used, resets ") == true, "\(codex)")
        #expect(codex.value?.contains("; 5-hour 20% used, resets in 1 hour 10 minutes") == true, "\(codex)")
        #expect(nodes.contains { $0.label == "Copilot limits" }, "\(nodes)")
        #expect(nodes.contains { $0.role == "AXButton" && $0.label == "Settings…" }, "\(nodes)")
        #expect(texts.contains { $0.label == "website, Codex, idle" }, "\(texts)")
    }

    // MARK: Helpers

    /// `visit` is called once per labelled element of the final tree, with the element and its label.
    private func tree(of view: some View, visit: ((NSObject, String) -> Void)? = nil) throws -> [Node] {
        // What an assistive client sets; without it SwiftUI leaves the tree empty. (Called by
        // selector: the only setter is deprecated, and there is no protocol method for it.)
        let app = NSApplication.shared
        _ = app.perform(NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: NSNumber(value: true), with: "AXEnhancedUserInterface")

        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        var nodes: [Node] = []
        // The tree fills in over a few run loop turns.
        for _ in 0..<30 where !nodes.contains(where: { $0.label?.hasSuffix(" limit") == true }) {
            host.layoutSubtreeIfNeeded()
            _ = host.accessibilityChildren()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            nodes = flatten(host)
        }
        if let visit { _ = flatten(host, visit: visit) }
        return nodes
    }

    /// The tree plus each labelled element's custom action names ("Dismiss").
    private func treeWithActions(of view: some View) throws -> (nodes: [Node], actions: [String: [String]]) {
        var actions: [String: [String]] = [:]
        let nodes = try tree(of: view) { object, label in
            let selector = NSSelectorFromString("accessibilityCustomActions")
            guard object.responds(to: selector),
                  let custom = object.perform(selector)?.takeUnretainedValue() as? [NSAccessibilityCustomAction]
            else { return }
            actions[label, default: []] += custom.map(\.name)
        }
        return (nodes, actions)
    }

    private func flatten(_ element: Any, depth: Int = 0, visit: ((NSObject, String) -> Void)? = nil) -> [Node] {
        guard depth < 40, let object = element as? NSObject else { return [] }
        func string(_ selector: String) -> String? {
            let selector = NSSelectorFromString(selector)
            guard object.responds(to: selector) else { return nil }
            let value = object.perform(selector)?.takeUnretainedValue()
            return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        let node = Node(
            role: string("accessibilityRole") ?? "?",
            label: string("accessibilityLabel"),
            value: string("accessibilityValue"),
            help: string("accessibilityHelp")
        )
        let childrenSelector = NSSelectorFromString("accessibilityChildren")
        let children = object.responds(to: childrenSelector)
            ? (object.perform(childrenSelector)?.takeUnretainedValue() as? [Any]) ?? []
            : []
        if let visit, let label = node.label { visit(object, label) }
        return [node] + children.flatMap { flatten($0, depth: depth + 1, visit: visit) }
    }
}
