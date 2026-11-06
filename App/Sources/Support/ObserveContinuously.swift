import Observation

/// Runs `apply` now, and again every time an observable property it read changes.
/// For AppKit code that mirrors `@Observable` state (SwiftUI views track it themselves).
@MainActor
func observeContinuously(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in
            observeContinuously(apply)
        }
    }
}
