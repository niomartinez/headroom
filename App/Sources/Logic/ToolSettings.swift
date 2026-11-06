import Foundation
import HeadroomModel
import HeadroomUI

/// Which tools the user tracks (Settings › Tools, 1.1 §6.4). The poll turns it into the store's `SourceSelection`.
struct ToolTracking: Sendable, Equatable {
    /// "Track Claude", on by default.
    var claude: Bool
    /// "Track Codex"; nil until the user decides, which counts as not tracked (and the panel may offer Codex).
    var codex: Bool?
    /// "Track Copilot": GitHub usage once connected, and Copilot CLI sessions once connected.
    var copilot: Bool

    /// 1.0: Claude only.
    static let claudeOnly = ToolTracking(claude: true, codex: nil, copilot: false)

    init(claude: Bool, codex: Bool?, copilot: Bool) {
        self.claude = claude
        self.codex = codex
        self.copilot = copilot
    }

    /// The saved choices (`Preferences.registerDefaults` must have run).
    init(defaults: UserDefaults) {
        claude = defaults.bool(forKey: Preferences.trackClaude)
        codex = defaults.object(forKey: Preferences.trackCodex) as? Bool
        copilot = defaults.bool(forKey: Preferences.trackCopilot)
    }

    var tracksCodex: Bool { codex == true }
}

/// "Rings show" (1.1 §6.1, §6.4): Automatic, or a tool. The saved value stays as picked; a tool that isn't tracked (or
/// has no limits) falls back to Automatic where it is used (`RingsTool.resolve`), so turning it back on restores it.
enum RingsChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case claude
    case codex
    case copilot

    var id: String { rawValue }

    init(tool: ToolID?) {
        switch tool {
        case nil: self = .automatic
        case .claude: self = .claude
        case .codex: self = .codex
        case .copilot: self = .copilot
        }
    }

    /// The saved choice; an unknown value reads as Automatic.
    init(defaults: UserDefaults) {
        self = defaults.string(forKey: Preferences.ringsTool).flatMap(RingsChoice.init(rawValue:)) ?? .automatic
    }

    /// Nil for Automatic: what `PillView`, `PanelView` and `RingsTool.resolve` take.
    var tool: ToolID? {
        switch self {
        case .automatic: nil
        case .claude: .claude
        case .codex: .codex
        case .copilot: .copilot
        }
    }

    var title: String { tool?.shortName ?? "Automatic" }

    /// Whether the picker offers this choice for `snapshot`: Automatic always, a tool only while it is tracked and has
    /// limits (1.1 §6.4).
    func isAvailable(in snapshot: HeadroomSnapshot) -> Bool {
        guard let tool else { return true }
        return RingsTool.toolsWithLimits(in: snapshot).contains(tool)
    }
}

/// "One gauge per tool" (1.1 §6.4): offered with two or more tools tracked.
enum GaugePerTool {
    static func isAvailable(in snapshot: HeadroomSnapshot) -> Bool {
        snapshot.trackedTools.count > 1
    }
}

/// Compact keeps alerts, the active count and one gauge; full titles remain in the panel and VoiceOver.
enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case compact

    var id: String { rawValue }
    var title: String { self == .automatic ? "Automatic" : "Always compact" }

    init(defaults: UserDefaults) {
        self = defaults.string(forKey: Preferences.menuBarLayout).flatMap(Self.init(rawValue:)) ?? .automatic
    }
}

/// The panel's Codex offer (1.1 §6.3): "Codex found on this Mac. Show its limits and sessions here too?"
enum CodexOffer {
    /// Shown while the user hasn't decided whether to track Codex, Codex is installed, and sample data is off.
    static func shows(tracking: ToolTracking, codexInstalled: Bool, sampleData: Bool) -> Bool {
        tracking.codex == nil && codexInstalled && !sampleData
    }
}

/// The Settings window's tabs (1.1 §6.4).
enum SettingsTab: String, CaseIterable, Sendable {
    case general
    case tools
    case about

    /// The tab last shown; General the first time.
    init(defaults: UserDefaults) {
        self = defaults.string(forKey: Preferences.settingsTab).flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}
