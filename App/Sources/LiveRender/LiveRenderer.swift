import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

/// `Headroom --render-live <dir>`: polls real data like the menu bar app for
/// `LiveRender.settleDuration`, then renders the live pill (plus the moment it's showing or has
/// queued) and panel through `ImageRenderer`, writes the snapshot as JSON, and quits. No status
/// item, no panel window, no Settings or onboarding.
@MainActor
final class LiveRenderer {
    enum RenderError: Error, CustomStringConvertible {
        case renderFailed(String)
        case encodingFailed(String)

        var description: String {
            switch self {
            case let .renderFailed(file): "ImageRenderer produced no image for \(file)"
            case let .encodingFailed(file): "couldn't encode \(file) as PNG"
            }
        }
    }

    /// Mid-gray, so the black pill stands out (as in `headroom-render`).
    private static let canvas = Color(.sRGB, white: 0.5, opacity: 1)
    /// The working pulse frozen part-way, so its ring is visible in a still image.
    private static let pulsePhase = 0.35

    private let directory: URL
    private let access: AccessManager
    private let model: AppModel

    init(directory: URL, defaults: UserDefaults = .standard) {
        Preferences.registerDefaults(in: defaults)
        self.directory = directory
        access = AccessManager(defaults: defaults)
        // Real data only, even with "Show sample data" on; no widget file, no GitHub request.
        model = AppModel(access: access, defaults: defaults, liveRender: true)
    }

    func start() {
        // Exits by itself even if a poll or the rendering hangs.
        let timeout = LiveRender.timeout
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: Double(timeout.components.seconds))
            FileHandle.standardError.write(Data("Headroom --render-live: timed out\n".utf8))
            exit(2)
        }
        // A directory that can't be written (a sandboxed build outside its container) fails now,
        // not after the wait.
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Headroom --render-live: \(error.localizedDescription)\n".utf8))
            exit(73) // EX_CANTCREAT
        }
        access.activate()
        model.start()
        Task {
            try? await Task.sleep(for: LiveRender.settleDuration)
            let succeeded = render()
            model.stop()
            if succeeded {
                NSApplication.shared.terminate(nil)
            } else {
                exit(1)
            }
        }
    }

    func stop() {
        model.stop()
    }

    private func render() -> Bool {
        // As the menu bar shows them: dismissed waits read as idle and the needs-you rest state (1.1 §14.4), from the
        // marks the menu bar app saved; "Rings show" and "One gauge per tool" (1.1 §6.1); the menu bar's height (§14.6).
        let presentation = model.presentation
        let snapshot = presentation.snapshot
        let dismissedIDs = presentation.dismissedIDs
        let attention = model.pillAttention
        let now = model.now
        let moment = model.momentToRender
        let tool = model.ringsChoice.tool
        let gaugePerTool = model.gaugePerTool
        let height = StatusItemMotion.pillHeight(menuBarHeight: NSScreen.main.map { $0.frame.maxY - $0.visibleFrame.maxY })
        let pill = { (moment: Moment?) in
            PillView(
                snapshot: snapshot, moment: moment, now: now, tool: tool, gaugePerTool: gaugePerTool, attention: attention,
                dismissedIDs: dismissedIDs, height: height
            )
        }
        do {
            try writePNG(pill(nil), named: LiveRender.pillFile)
            let momentFile = directory.appendingPathComponent(LiveRender.momentPillFile)
            if let moment {
                try writePNG(pill(moment), named: LiveRender.momentPillFile)
            } else if FileManager.default.fileExists(atPath: momentFile.path) {
                try FileManager.default.removeItem(at: momentFile)
            }
            try writePNG(
                PanelView(
                    snapshot: snapshot, now: now, actions: .none, tool: tool, showsCodexOffer: model.showsCodexOffer,
                    dismissedIDs: dismissedIDs
                ),
                named: LiveRender.panelFile
            )
            let json = directory.appendingPathComponent(LiveRender.snapshotFile)
            try LiveRender.snapshotJSON(model.snapshot).write(to: json, options: .atomic)
            print(json.path)
            return true
        } catch {
            FileHandle.standardError.write(Data("Headroom --render-live: \(error)\n".utf8))
            return false
        }
    }

    private func writePNG(_ content: some View, named name: String) throws {
        let framed = content
            .padding(24)
            .background(Self.canvas)
            .environment(\.frozenPulsePhase, Self.pulsePhase)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = LiveRender.scale
        guard let image = renderer.cgImage else { throw RenderError.renderFailed(name) }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed(name)
        }
        let url = directory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        print(url.path)
    }
}
