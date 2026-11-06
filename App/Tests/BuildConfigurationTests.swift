import Foundation
import HeadroomShare
import Testing

/// The build's switches as the repository sets them (1.1 §4.8, §5.2, §8): the GitHub Client ID, the entitlement
/// variants it selects, and the URL scheme the widgets open. Reads project.yml, the xcconfigs, the Info.plists and
/// the entitlements files next to these tests; scripts/verify-build.sh checks the signed result.
@Suite struct BuildConfigurationTests {
    /// The repository, from this file's place in it (App/Tests).
    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.repository.appendingPathComponent(path), encoding: .utf8)
    }

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repository.appendingPathComponent(path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// project.yml's `HEADROOM_GITHUB_CLIENT_ID`.
    private func clientID() throws -> String {
        let line = try #require(try text("project.yml").split(separator: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("HEADROOM_GITHUB_CLIENT_ID:")
        })
        return line.split(separator: ":", maxSplits: 1)[1]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static let network = "com.apple.security.network.client"
    private static let groups = "com.apple.security.application-groups"

    /// F2 ships (gate G1 passed): the public Client ID of "Headroom for Mac" (1.1 §4.2).
    @Test func theGitHubClientIDIsSet() throws {
        #expect(try clientID() == "Iv23liEA5ZycifEXDZCT")
        let info = try plist("App/Info.plist")
        #expect(info[GitHubClientID.infoKey] as? String == "$(HEADROOM_GITHUB_CLIENT_ID)")
    }

    /// network.client if and only if a Client ID is set: the Client ID selects the variants without "-Offline".
    @Test func theEntitlementsMatchTheClientID() throws {
        let hasClientID = try !clientID().isEmpty
        let variants = try text("Config/Headroom-Variants.xcconfig")
        #expect(variants.contains("HEADROOM_NETWORK_SUFFIX_ = -Offline"))
        #expect(variants.contains("HEADROOM_NETWORK_SUFFIX = $(HEADROOM_NETWORK_SUFFIX_$(HEADROOM_GITHUB_CLIENT_ID))"))
        #expect(try text("project.yml").contains(
            "CODE_SIGN_ENTITLEMENTS: App/Headroom$(HEADROOM_GROUP_SUFFIX)$(HEADROOM_NETWORK_SUFFIX).entitlements"
        ))

        // The variants a set Client ID picks carry the network; the offline ones never do.
        for name in ["Headroom", "Headroom-NoGroup"] {
            let entitlements = try plist("App/\(name).entitlements")
            #expect((entitlements[Self.network] as? Bool == true) == hasClientID, "\(name)")
        }
        for name in ["Headroom-Offline", "Headroom-NoGroup-Offline"] {
            #expect(try plist("App/\(name).entitlements")[Self.network] == nil, "\(name)")
        }
        // The group only in the group variants; the widget extension never gets the network.
        #expect(try plist("App/Headroom.entitlements")[Self.groups] != nil)
        #expect(try plist("App/Headroom-NoGroup.entitlements")[Self.groups] == nil)
        for name in ["HeadroomWidgets", "HeadroomWidgets-NoGroup"] {
            #expect(try plist("Widgets/\(name).entitlements")[Self.network] == nil, "\(name)")
        }
        // Debug is unsandboxed and claims nothing.
        #expect(try plist("App/Headroom-Debug.entitlements").isEmpty)
    }

    @Test func theClientIDIsReadFromInfoPlist() {
        #expect(GitHubClientID.value(in: [GitHubClientID.infoKey: "Iv23liEXAMPLE"]) == "Iv23liEXAMPLE")
        #expect(GitHubClientID.value(in: [GitHubClientID.infoKey: " "]) == nil)
        #expect(GitHubClientID.value(in: [GitHubClientID.infoKey: "$(HEADROOM_GITHUB_CLIENT_ID)"]) == nil)
        #expect(GitHubClientID.value(in: [:]) == nil)
        #expect(GitHubClientID.value(in: nil) == nil)
    }

    /// Copilot CLI (F3) is compiled into the app like the package (1.1 §4.9).
    @Test func copilotCLIShips() throws {
        #expect(AppFeatures.copilotCLI)
        #expect(try text("Packages/HeadroomKit/Package.swift").contains(#".define("HEADROOM_COPILOT_CLI")"#))
    }

    // MARK: URLs (1.1 §5.2, §5.6)

    @Test func theAppClaimsTheWidgetsScheme() throws {
        let types = try #require(try plist("App/Info.plist")["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == ["$(HEADROOM_URL_SCHEME)"])
        #expect(try plist("App/Info.plist")["HeadroomURLScheme"] as? String == "$(HEADROOM_URL_SCHEME)")
        #expect(try plist("Widgets/Info.plist")["HeadroomURLScheme"] as? String == "$(HEADROOM_URL_SCHEME)")
        // A package/test host with no app configuration retains the production URL.
        #expect(WidgetShare.openPanelURL.absoluteString == "com.niomartinez.headroom://panel")
    }

    @Test func onlyThePanelURLOpensThePanel() {
        #expect(AppURL.action(for: WidgetShare.openPanelURL) == .openPanel)
        #expect(AppURL.action(for: URL(string: "COM.NIOMARTINEZ.HEADROOM://Panel")!) == .openPanel)
        #expect(AppURL.action(for: URL(string: "com.niomartinez.headroom://settings")!) == nil)
        #expect(AppURL.action(for: URL(string: "headroom://panel")!) == nil)
        #expect(AppURL.action(for: URL(string: "https://headroom.niomartinez.com/panel")!) == nil)
    }
}
