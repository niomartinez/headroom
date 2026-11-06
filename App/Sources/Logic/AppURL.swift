import Foundation
import HeadroomShare

/// URLs Headroom opens with (1.1 §5.2, §5.6): its own scheme, `com.niomartinez.headroom`, unique because other
/// "Headroom" apps exist. Every widget opens `com.niomartinez.headroom://panel`.
enum AppURL {
    enum Action: Equatable {
        /// Open the panel under the pill, or Settings when the pill isn't visible.
        case openPanel
    }

    /// What `url` asks for; nil for anything Headroom doesn't know, which is ignored.
    static func action(for url: URL) -> Action? {
        guard let scheme = url.scheme?.lowercased(), scheme == WidgetShare.openPanelURL.scheme?.lowercased() else {
            return nil
        }
        switch url.host?.lowercased() {
        case WidgetShare.openPanelURL.host?.lowercased(): return .openPanel
        default: return nil
        }
    }
}
