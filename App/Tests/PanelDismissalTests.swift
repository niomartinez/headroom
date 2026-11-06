import Darwin
import Testing

@Suite struct PanelDismissalTests {
    private let ownPID: pid_t = 100

    @Test func anotherAppComingToTheFrontClosesThePanel() {
        #expect(PanelDismissal.closesOnActivation(of: (pid: 4242, isRegularApp: true), ownPID: ownPID))
    }

    /// Headroom itself coming forward (Settings, an alert) is not "another app".
    @Test func headroomBecomingActiveKeepsThePanel() {
        #expect(!PanelDismissal.closesOnActivation(of: (pid: ownPID, isRegularApp: false), ownPID: ownPID))
        #expect(!PanelDismissal.closesOnActivation(of: (pid: ownPID, isRegularApp: true), ownPID: ownPID))
    }

    /// Agents without a Dock icon (Control Center, which hosts menu bar items on macOS 26) can
    /// activate around a click on the pill itself; those clicks are handled by the click monitors.
    @Test func menuBarAgentsBecomingActiveKeepThePanel() {
        #expect(!PanelDismissal.closesOnActivation(of: (pid: 4242, isRegularApp: false), ownPID: ownPID))
    }

    @Test func anUnknownAppBecomingActiveClosesThePanel() {
        #expect(PanelDismissal.closesOnActivation(of: nil, ownPID: ownPID))
    }
}
