import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

/// The pill in the menu bar (spec §1.1). The status button displays a native full-color image with
/// normal and Retina representations, and the item's length follows the
/// pill's fitting width. With more than Claude tracked, the button's tooltip lists every tool's limits
/// (1.1 §6.1).
///
/// 1.1 §14: the pill rests on "(!) harbor" while a wait is unseen, with dismissed waits left out of the dot and count
/// (§14.4); it is as tall as the menu bar allows (the status item's window height minus about 6 pt, at least 22 pt);
/// and it moves fully visible content while resizing in one display-synchronized transition, with updates coalesced (§14.6).
@MainActor
final class StatusItemController: NSObject {
    private typealias Motion = PillMotion<PillInputs>

    /// Called with the status item button on click, to toggle the panel under it.
    var onClick: ((NSStatusBarButton) -> Void)?

    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var frames: [PillImageFrame] = []
    private var currentFrame: PillImageFrame?
    private var currentInputs: PillInputs?
    private var pulse: Task<Void, Never>?
    /// Native buttons leave a small inset around their image.
    private static let imagePadding: CGFloat = 4
    private let lengthAnimator: StatusItemLengthAnimator
    /// Draws `PillMotion`'s steps one after another.
    private lazy var stepper = PillStepper<PillInputs>(
        draw: { [weak self] step, completion in self?.draw(step, completion: completion) },
        reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    )
    private var displayedMoment: Moment?
    private var displayedMode: PillModel.Mode = .normal
    /// The pill is re-rendered only when what it draws changed, not on every 2 s poll.
    private var drawn = ChangeGate<PillDrawKey>()
    private var accessibilityLabel = ChangeGate<String>()
    private var toolTip = ChangeGate<String?>()
    /// Menu bar height changes; the controller lives as long as the app.
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        lengthAnimator = StatusItemLengthAnimator(statusItem: statusItem)
        super.init()

        statusItem.autosaveName = "HeadroomPill"
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(buttonPressed(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        observeContinuously { [weak self] in
            self?.update()
        }
        observeDisplayChanges()
    }

    /// Keeps the button highlighted while the panel is open, like a menu.
    func setHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    /// The button, while the pill is actually on screen: not hidden behind the notch, removed from the menu bar, or
    /// tucked away by a menu bar manager. The widgets' "open the panel" falls back to Settings otherwise (1.1 §5.6).
    var visibleButton: NSStatusBarButton? {
        guard statusItem.isVisible, let button = statusItem.button, let window = button.window,
              window.screen != nil, window.occlusionState.contains(.visible)
        else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? button : nil
    }

    @objc private func buttonPressed(_ sender: NSStatusBarButton) {
        onClick?(sender)
    }

    /// Runs after every poll (the observed properties change each time), and when the menu bar's height may have
    /// changed; does nothing unless the pill or its VoiceOver label would actually change.
    private func update() {
        let presentation = model.presentation
        let snapshot = presentation.snapshot
        let moment = model.currentMoment
        let visibleMoment = PillInputs.menuBarMoment(moment)
        let now = model.now
        let attention = model.pillAttention
        let inputs = PillInputs(
            snapshot: snapshot, moment: visibleMoment, now: now, tool: model.ringsChoice.tool, gaugePerTool: model.gaugePerTool,
            attention: attention, dismissedIDs: presentation.dismissedIDs,
            height: StatusItemMotion.sharedPillHeight(menuBarHeights: NSScreen.screens.map {
                $0.frame.maxY - $0.visibleFrame.maxY
            }),
            maximumWidth: maximumPillWidth,
            compact: model.menuBarLayout == .compact
        )

        let label = AccessibilitySummary.label(
            for: snapshot, moment: visibleMoment, now: now, sampleData: model.sampleData.isOn, attention: attention,
            dismissedIDs: presentation.dismissedIDs
        )
        if accessibilityLabel.admit(label) {
            statusItem.button?.setAccessibilityLabel(label)
        }
        let key = PillDrawKey(inputs)
        let hint = inputs.compact ? key.model.accessibilityLabel : key.model.toolTip
        if toolTip.admit(hint) {
            statusItem.button?.toolTip = hint
        }
        let mode = key.model.mode
        announce(moment: moment, attention: attention, mode: mode, trackedTools: snapshot.trackedTools)
        guard drawn.last != key, let frame = imageFrame(for: inputs) else { return }
        _ = drawn.admit(key)
        let width = frame.size.width + Self.imagePadding
        stepper.show(Motion.Target(content: inputs, mode: mode, width: width, animationID: inputs.completionID))
    }

    /// Grow into the menu-bar lane without crossing a notch or the screen edge. Keep the image shared across
    /// monitors: the narrowest connected lane determines its budget, rather than changing it with keyboard focus.
    /// The native item's right edge already accounts for the status items after it. On unnotched displays,
    /// reserve the leading quarter for application menus; AppKit does not expose another app's menu width.
    private var maximumPillWidth: CGFloat? {
        guard let window = statusItem.button?.window, let screen = window.screen,
              window.frame.width > 0 else { return nil }
        let trailingSpace = max(0, screen.frame.maxX - window.frame.maxX)
        return StatusItemMotion.widthBudget(lanes: NSScreen.screens.map { display in
            let laneWidth = display.auxiliaryTopRightArea?.width ?? display.frame.width * 0.75
            return floor(max(1, laneWidth - trailingSpace - Self.imagePadding - 12))
        })
    }

    private func imageFrame(for inputs: PillInputs) -> PillImageFrame? {
        let key = PillDrawKey(inputs)
        if let cached = frames.first(where: { $0.key == key }) { return cached }
        guard let frame = PillImageFrame(inputs: inputs,
            differentiateWithoutColor: NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor)
        else { return nil }
        frames.append(frame)
        if frames.count > 3 { frames.removeFirst() }
        return frame
    }

    /// The capsule, title and trailing gauges share one progress value and a stable native image canvas.
    private func draw(_ step: Motion.Step, completion: @escaping @MainActor () -> Void) {
        guard let frame = imageFrame(for: step.content) else { completion(); return }
        let previous = currentFrame ?? frame
        currentFrame = frame
        currentInputs = step.content
        pulse?.cancel()
        pulse = nil
        lengthAnimator.animate(to: step.width, duration: step.duration) { [weak self] width, progress in
            guard let self else { return }
            if progress >= 1 {
                self.refreshImage()
            } else {
                self.statusItem.button?.image = frame.transitionImage(
                    from: previous, width: width - Self.imagePadding,
                    canvasWidth: self.statusItem.length - Self.imagePadding, progress: progress
                )
            }
        } completion: { [weak self] in
            completion()
            self?.startPulseIfNeeded()
        }
    }

    private func refreshImage() {
        guard let currentFrame else { return }
        statusItem.button?.image = currentFrame.image(
            width: statusItem.length - Self.imagePadding, textOpacity: 1,
            pulseDate: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Date()
        )
    }

    private func startPulseIfNeeded() {
        guard pulse == nil, currentFrame?.pulses == true, !lengthAnimator.isAnimating,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        pulse = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                // The backing window's occlusion state does not describe copies on other menu bars.
                if self.statusItem.isVisible {
                    self.refreshImage()
                }
            }
        }
    }

    /// Moments are visual; VoiceOver users hear them too. So is the needs-you rest state when no moment said it first
    /// (a wait found at launch, or with a moment for it already gone).
    private func announce(moment: Moment?, attention: NeedsYouAttention?, mode: PillModel.Mode, trackedTools: [ToolID]) {
        if moment != displayedMoment {
            displayedMoment = moment
            if let moment {
                announce(AccessibilitySummary.text(for: moment, trackedTools: trackedTools))
            }
        }
        if mode == .attention, displayedMode == .normal, moment?.needsInputSessionID == nil, let attention {
            announce(attention.spoken)
        }
        displayedMode = mode
    }

    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    /// Focus can move the status window between displays. Its height must not resize the replicas on other bars.
    private func observeDisplayChanges() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pulse?.cancel()
                self.pulse = nil
                self.frames.removeAll()
                if let inputs = self.currentInputs, let frame = self.imageFrame(for: inputs) {
                    self.currentFrame = frame
                    self.refreshImage()
                    self.startPulseIfNeeded()
                }
                self.drawn.reset()
                self.update()
            }
        })
    }
}
