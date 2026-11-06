import CopilotKit
import Foundation
import HeadroomModel
import HeadroomUI

/// Headroom's GitHub App Client ID (1.1 §4.2, §4.8): project.yml's `HEADROOM_GITHUB_CLIENT_ID`, in Info.plist as
/// `HeadroomGitHubClientID`. Public, not a secret. Without one, Copilot usage is off: no Connect GitHub, no network.
enum GitHubClientID {
    static let infoKey = "HeadroomGitHubClientID"

    /// The Client ID in `info`, or nil when it is missing, empty or an unexpanded build setting.
    static func value(in info: [String: Any]?) -> String? {
        guard let raw = info?[infoKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    /// The running app's.
    static var current: String? { value(in: Bundle.main.infoDictionary) }
}

/// What this build ships (1.1 §0): F2 Copilot usage needs a Client ID; F3 Copilot CLI sessions need
/// `HEADROOM_COPILOT_CLI` (gate G2).
enum AppFeatures {
    static var copilotUsage: Bool { GitHubClientID.current != nil }

    static let copilotCLI: Bool = {
        #if HEADROOM_COPILOT_CLI
        true
        #else
        false
        #endif
    }()
}

/// Settings › Tools › GitHub Copilot › GitHub account (1.1 §4.6, §6.4).
struct GitHubAccountPresentation: Equatable {
    enum Action: Equatable {
        case connect
        case reconnect
        case disconnect
    }

    let status: String
    let actions: [Action]
    /// Under the row: why there are no numbers, when GitHub says there is nothing to read.
    let caption: String?

    /// `login` is the connected account (nil = not connected); `usage` the latest Copilot usage; `lastUpdated` when
    /// GitHub last answered.
    init(login: String?, usage: ToolUsage?, lastUpdated: Date?, now: Date, format: HeadroomFormat = HeadroomFormat()) {
        guard let login else {
            (status, actions, caption) = ("Not connected", [.connect], nil)
            return
        }
        switch usage?.status {
        case .signInExpired?:
            (status, actions, caption) = ("Sign-in expired", [.reconnect, .disconnect], nil)
        case .notConnected?:
            (status, actions, caption) = ("Not connected", [.connect], nil)
        default:
            let updated = lastUpdated.map { " · updated \(format.age(of: $0, now: now))" } ?? ""
            let organization = usage?.status == .noIndividualUsage ? GitHubCopy.organizationPlans : nil
            (status, actions, caption) = ("Connected as @\(login)\(updated)", [.disconnect], organization)
        }
    }

    static func title(for action: Action) -> String {
        switch action {
        case .connect: "Connect GitHub…"
        case .reconnect: "Reconnect…"
        case .disconnect: "Disconnect"
        }
    }
}

/// The Copilot and GitHub copy in Settings, the Connect GitHub sheet and the Disconnect notice (1.1 §4.3, §4.5, §6.4).
enum GitHubCopy {
    static let sheetTitle = "Connect GitHub"
    static let sheetBody = "Enter this code on GitHub to let Headroom read your Copilot usage:"
    static let copyAndOpen = "Copy Code and Open GitHub"
    static let waiting = "Waiting for GitHub…"
    static let requestingCode = "Asking GitHub for a code…"

    static func connected(_ login: String) -> String { "Connected as @\(login)" }

    static let organizationPlans = "GitHub has not returned usage for this account yet."
    static let planCaption = "If GitHub does not provide an allowance, pick your plan to show a percent. Check your current allowance at github.com/settings/billing."
    static let usageCaption = "Connect GitHub for monthly usage and plan limits. Headroom checks every 15 minutes using its own read-only sign-in. Organization-paid usage appears when GitHub provides your seat's quota. This does not connect session activity."

    static let disconnectedTitle = "GitHub disconnected"
    static let disconnectedMessage = "Headroom deleted its GitHub sign-in from this Mac. To also remove Headroom's access on GitHub, revoke it in your GitHub settings."
    static let openAuthorizations = "Open GitHub Settings"
    /// Where the user revokes the grant: revoking it from the app would need a client secret (1.1 §4.3).
    static let authorizationsURL = URL(string: "https://github.com/settings/apps/authorizations")!
    static let disconnectFailedTitle = "Headroom couldn't disconnect GitHub"
}

/// Settings › Tools › GitHub Copilot › Plan › Custom's text field (1.1 §4.5): a whole number of credits or requests,
/// written the way the user's region writes numbers. "1.500" is 1,500 in German, and not a number in English: a
/// separator that isn't the region's grouping separator, or groups that aren't three digits, make the text no number
/// rather than a wrong one.
enum CustomAllowanceText {
    /// The whole number in `text`, digits with or without `locale`'s grouping separator ("1,500", "1.500", "1 500");
    /// nil for anything else, including decimals.
    static func value(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var groups: [[Int]] = [[]]
        for character in trimmed {
            if let digit = decimalDigit(character) {
                groups[groups.count - 1].append(digit)
            } else if isGroupingSeparator(character, locale: locale), !groups[groups.count - 1].isEmpty {
                groups.append([])
            } else {
                return nil
            }
        }
        // "1,500,000": one to three digits, then groups of exactly three.
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard digits.count <= 15 else { return nil }
        return Double(digits.reduce(0) { $0 * 10 + $1 })
    }

    /// The field's text for a saved allowance: its digits for a whole number, which `value` reads back in any region.
    /// (An older version could save a fraction; that one is shown as the region writes it, and doesn't read back.)
    static func text(for value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return value.formatted(.number.grouping(.never).locale(locale))
    }

    /// 0–9 in any script's decimal digits (Unicode Nd); nil for anything else, "²" and "½" included.
    private static func decimalDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
              scalar.properties.numericType == .decimal
        else { return nil }
        return character.wholeNumberValue
    }

    /// `locale`'s grouping separator; a space-like one (French and others use a narrow no-break space) also accepts a
    /// plain space, and a typographic apostrophe (Swiss German) a plain one.
    private static func isGroupingSeparator(_ character: Character, locale: Locale) -> Bool {
        guard let separator = locale.groupingSeparator, !separator.isEmpty else { return false }
        if String(character) == separator { return true }
        let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}"]
        if let first = separator.first, spaces.contains(first) { return spaces.contains(character) }
        if separator == "’" { return character == "'" }
        return false
    }
}
