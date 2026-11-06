import AppKit
import CopilotKit
import HeadroomModel
import Observation

/// Copilot usage as the app shows and schedules it (1.1 §4.3–§4.7, §6.4): the connected login, the latest usage, the
/// Plan picker, the Connect GitHub sheet and the 15-minute timer. `CopilotService` does the talking to GitHub and is
/// the only thing that touches the tokens.
///
/// Polls only while Copilot is tracked, GitHub is connected and sample data is off (`update(tracked:sampleData:)`).
/// Without a Client ID (a build without Copilot usage) there is nothing to connect and no network code runs.
@MainActor
@Observable
final class CopilotAccount {
    /// The Connect GitHub sheet (1.1 §6.4); nil while it isn't shown.
    enum SignIn: Equatable {
        case requestingCode
        /// `opened`: the user copied the code and GitHub opened, so the sheet says "Waiting for GitHub…".
        case code(userCode: String, verificationURI: URL, opened: Bool)
        case failed(String)
        case connected(String)
    }

    /// A Client ID is compiled in (F2): Settings offers Connect GitHub.
    let isAvailable: Bool
    /// The connected GitHub login; nil = not connected.
    private(set) var login: String?
    /// The latest usage from GitHub, or what a failure keeps; nil before the first answer since connecting.
    private(set) var usage: ToolUsage?
    /// When GitHub last answered: "updated 5m ago".
    private(set) var lastUpdated: Date?
    private(set) var plan: CopilotPlan
    private(set) var customAllowance: Double?
    private(set) var signIn: SignIn?
    /// A Disconnect is running.
    private(set) var isDisconnecting = false

    /// Called on the main actor after a sign-in succeeds (the app then tracks Copilot).
    @ObservationIgnored var onConnected: (() -> Void)?

    @ObservationIgnored private let service: CopilotService?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tracked = false
    @ObservationIgnored private var sampleData = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    /// `clientID` nil = no Copilot usage in this build. `service` nil = no network even with a Client ID (`--render-live`
    /// runs beside the menu bar app, whose service alone may refresh the tokens): Copilot shows its connection only.
    init(clientID: String?, defaults: UserDefaults, service: CopilotService?) {
        isAvailable = clientID != nil
        self.defaults = defaults
        self.service = clientID == nil ? nil : service
        login = defaults.string(forKey: Preferences.copilotLogin)
        plan = defaults.string(forKey: Preferences.copilotPlan).flatMap(CopilotPlan.init(rawValue:)) ?? .notSure
        customAllowance = defaults.object(forKey: Preferences.copilotCustomAllowance) as? Double
    }

    /// The app's: `CopilotService.live` with the Info.plist Client ID, the saved login and plan.
    static func live(defaults: UserDefaults, networking: Bool) -> CopilotAccount {
        let clientID = GitHubClientID.current
        let service = clientID.flatMap { clientID -> CopilotService? in
            guard networking else { return nil }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            return CopilotService.live(
                clientID: clientID,
                appVersion: version,
                login: defaults.string(forKey: Preferences.copilotLogin),
                plan: defaults.string(forKey: Preferences.copilotPlan).flatMap(CopilotPlan.init(rawValue:)) ?? .notSure,
                customAllowance: defaults.object(forKey: Preferences.copilotCustomAllowance) as? Double
            )
        }
        return CopilotAccount(clientID: clientID, defaults: defaults, service: service)
    }

    /// Copilot's usage for the snapshot while Copilot is tracked (1.1 §4.6): nil without a Client ID (the store then
    /// counts Copilot as tracked for its CLI sessions only, if those are connected), `.notConnected` without a login,
    /// else the latest usage, or an empty reading ("No usage data yet") until GitHub first answers.
    var snapshotUsage: ToolUsage? {
        guard isAvailable else { return nil }
        guard let login else { return ToolUsage(tool: .copilot, status: .notConnected) }
        return usage ?? ToolUsage(tool: .copilot, status: .ok, planName: plan.presetName, account: login)
    }

    // MARK: Scheduling (1.1 §4.7)

    /// Whether Copilot is tracked, and whether sample data shows: polls run only while tracked, connected and real.
    func update(tracked: Bool, sampleData: Bool) {
        self.tracked = tracked
        self.sampleData = sampleData
        reschedule()
    }

    /// Tracked, connected, real, and not waiting for a new sign-in (an expired one only asks again at Reconnect).
    private var isActive: Bool {
        service != nil && tracked && !sampleData && login != nil && usage?.status != .signInExpired
    }

    /// The panel opened: a reading more than 5 minutes old is fetched again.
    func panelOpened() {
        poll(.panelOpened)
    }

    /// The Mac woke from sleep: fetch once.
    func didWake() {
        poll(.wake)
    }

    /// The panel's Refresh button: fetch once, whatever the reading's age.
    func refreshNow() {
        poll(.manual)
    }

    private func poll(_ trigger: CopilotPollPolicy.Trigger) {
        guard isActive else { return }
        Task { await pollNow(trigger) }
    }

    private func pollNow(_ trigger: CopilotPollPolicy.Trigger) async {
        guard isActive, let service else { return }
        guard let outcome = await service.poll(trigger, now: Date()) else { return }
        apply(outcome)
    }

    private func apply(_ outcome: CopilotService.PollOutcome) {
        // A sign-out that finished meanwhile: nothing to show.
        guard login != nil || outcome.fetchedLogin != nil else { return }
        if outcome.usage.status == .notConnected {
            // The Keychain item is gone: connected no more.
            forgetLogin()
            return
        }
        if let fetched = outcome.fetchedLogin, fetched != login {
            login = fetched
            defaults.set(fetched, forKey: Preferences.copilotLogin)
        }
        usage = outcome.usage
        if outcome.succeeded {
            lastUpdated = Date()
        }
        reschedule()
    }

    /// The longest the timer sleeps at once: a later due time is waited out in steps (the policy then says whether to
    /// poll), so no due time can overflow the sleep.
    static let longestSleep: TimeInterval = CopilotPollPolicy.maximumBackoff

    /// Runs the timer while active, polling at `CopilotPollPolicy.nextTimerPoll` (now, for a first poll); `first`
    /// polls at once with that trigger instead (a sign-in).
    private func reschedule(first: CopilotPollPolicy.Trigger? = nil) {
        guard isActive, let service else {
            timer?.cancel()
            timer = nil
            return
        }
        if first != nil {
            timer?.cancel()
            timer = nil
        }
        guard timer == nil else { return }
        timer = Task { [weak self] in
            var trigger = first
            while !Task.isCancelled {
                if trigger == nil {
                    let due = await service.nextTimerPoll(now: Date())
                    try? await Task.sleep(for: .seconds(min(max(1, due.timeIntervalSinceNow), Self.longestSleep)))
                }
                guard !Task.isCancelled, let self else { return }
                await self.pollNow(trigger ?? .timer)
                trigger = nil
            }
        }
    }

    // MARK: Plan (1.1 §4.5)

    func setPlan(_ plan: CopilotPlan) {
        guard plan != self.plan else { return }
        self.plan = plan
        defaults.set(plan.rawValue, forKey: Preferences.copilotPlan)
        applyPlan()
    }

    /// Custom's number: kept only within 1–1,000,000 (`CopilotPlan.customAllowanceRange`).
    @discardableResult
    func setCustomAllowance(_ value: Double?) -> Bool {
        guard let value, CopilotPlan.customAllowanceRange.contains(value) else { return false }
        customAllowance = value
        defaults.set(value, forKey: Preferences.copilotCustomAllowance)
        applyPlan()
        return true
    }

    /// The shown reading with the new allowance at once; the service keeps it for the next polls.
    private func applyPlan() {
        usage = usage.map { CopilotUsageMapping.applying(plan: plan, customAllowance: customAllowance, to: $0) }
        guard let service else { return }
        let (plan, custom) = (plan, customAllowance)
        Task { _ = await service.setPlan(plan, customAllowance: custom) }
    }

    // MARK: Connect GitHub (1.1 §4.3, §6.4)

    /// Shows the sheet and asks GitHub for a code, then waits in the background for the user to approve it.
    func beginSignIn() {
        guard let service else { return }
        signInTask?.cancel()
        signIn = .requestingCode
        signInTask = Task { [weak self] in
            do {
                let code = try await service.requestCode(now: Date())
                guard let self, !Task.isCancelled else { return }
                self.signIn = .code(userCode: code.userCode, verificationURI: code.verificationURI, opened: false)
                let login = try await service.signIn(with: code)
                guard !Task.isCancelled else { return }
                self.connected(as: login)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.signIn = .failed((error as? DeviceFlowError ?? .failed).message)
            }
        }
    }

    /// "Copy Code and Open GitHub": the code on the clipboard, GitHub's device page in the browser.
    func copyCodeAndOpenGitHub() {
        guard case let .code(userCode, uri, _) = signIn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(userCode, forType: .string)
        NSWorkspace.shared.open(uri)
        signIn = .code(userCode: userCode, verificationURI: uri, opened: true)
    }

    /// Cancel, or Done after connecting: closes the sheet and stops waiting.
    func endSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signIn = nil
    }

    private func connected(as login: String) {
        signInTask = nil
        self.login = login
        defaults.set(login, forKey: Preferences.copilotLogin)
        usage = nil
        lastUpdated = nil
        signIn = .connected(login)
        // Tracks Copilot (starting the timer), then fetches at once, whatever the backoff.
        onConnected?()
        reschedule(first: .signedIn)
    }

    // MARK: Disconnect (1.1 §4.3)

    /// Deletes the Keychain item and the login, then offers GitHub's page where the grant is revoked.
    func disconnect() {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        Task {
            defer { isDisconnecting = false }
            do {
                try await service?.signOut()
            } catch {
                Self.showAlert(GitHubCopy.disconnectFailedTitle, message: String(describing: error))
                return
            }
            forgetLogin()
            Self.offerRevoking()
        }
    }

    private func forgetLogin() {
        login = nil
        usage = nil
        lastUpdated = nil
        defaults.removeObject(forKey: Preferences.copilotLogin)
        reschedule()
    }

    private static func offerRevoking() {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = GitHubCopy.disconnectedTitle
        alert.informativeText = GitHubCopy.disconnectedMessage
        alert.addButton(withTitle: GitHubCopy.openAuthorizations)
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(GitHubCopy.authorizationsURL)
        }
    }

    private static func showAlert(_ title: String, message: String) {
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
