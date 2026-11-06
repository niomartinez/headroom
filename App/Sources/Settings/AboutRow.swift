import AppKit
import SwiftUI

/// Settings › About: version and the non-affiliation notice (spec §1.3, 1.1 §6.4).
struct AboutRow: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(marketing) (\(build))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Headroom")
                    .font(.headline)
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(SettingsCopy.nonAffiliation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
