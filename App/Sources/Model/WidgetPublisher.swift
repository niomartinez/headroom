import Foundation
import HeadroomModel
import HeadroomShare
import OSLog
import WidgetKit

/// Hands the widgets what they show (1.1 §5.4): a scrubbed copy of the snapshot in the App Group container, and a
/// timeline reload when `WidgetReloadGate` allows one. The app is the only writer of that file; the widget extension
/// only reads it. Runs off the main thread. AppModel calls `publish` after each applied poll and when sample data
/// shows; `--render-live` never does. Without an App Group (Debug and ad-hoc builds) it does nothing at all.
actor WidgetPublisher {
    private let fileURL: URL?
    private let reload: @Sendable () -> Void
    private var gate = WidgetReloadGate()
    /// What the file holds now; nil before the first write since launch, or after a failed one.
    private var written: WidgetSignature?
    /// A failed write was logged; the next is logged only after one works again.
    private var loggedFailure = false
    private let logger = Logger(subsystem: "com.niomartinez.headroom", category: "widgets")

    /// `fileURL` nil = no App Group: publishing is a no-op.
    init(
        fileURL: URL? = WidgetShare.fileURL(),
        reload: @escaping @Sendable () -> Void = WidgetPublisher.reloadTimelines
    ) {
        self.fileURL = fileURL
        self.reload = reload
    }

    /// `pillTool` is the app's resolved "Rings show" tool (the widgets' Automatic); `showsNames` is Settings ›
    /// General › "Show session names in widgets".
    func publish(_ snapshot: HeadroomSnapshot, isSample: Bool, pillTool: ToolID?, showsNames: Bool, now: Date) {
        guard let fileURL else { return }
        let signature = WidgetSignature(
            snapshot: snapshot, isSample: isSample, pillTool: pillTool, showsSessionNames: showsNames
        )
        if gate.shouldWrite(previous: written, current: signature, now: now) {
            let file = WidgetSnapshotFile.scrubbing(
                snapshot, writtenAt: now, isSample: isSample, pillTool: pillTool, showsSessionNames: showsNames
            )
            do {
                try file.write(to: fileURL)
                written = signature
                loggedFailure = false
            } catch {
                // Tried again in a minute, as a first write; no reload for a file that isn't there.
                written = nil
                gate.writeFailed(now: now)
                if !loggedFailure {
                    loggedFailure = true
                    // The error's text names the container path, so only its domain and code are public.
                    let error = error as NSError
                    logger.error("Couldn't write the widget file: \(error.domain, privacy: .public) \(error.code)")
                }
                return
            }
        }
        // Nothing written yet (a write failed and waits to be tried again): nothing to reload.
        guard written != nil else { return }
        if gate.shouldReload(now: now) { reload() }
    }

    /// The Mac woke from sleep: the next publish writes and reloads right away.
    func noteWake() {
        gate.noteWake()
    }

    /// Both kinds: they read the same file.
    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.limitsKind)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShare.sessionsKind)
    }
}
