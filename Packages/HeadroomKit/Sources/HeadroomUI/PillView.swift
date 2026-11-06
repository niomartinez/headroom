import HeadroomModel
import SwiftUI

/// The menu bar pill (spec §1.1, 1.1 §6.1). `moment` non-nil → the widened moment layout; `attention` → the
/// needs-you rest state (1.1 §14.4). `tool` is the "Rings show" choice (nil = Automatic) and `gaugePerTool` "One
/// gauge per tool"; with only Claude tracked the pill is 1.0's. `height` is the pill's height (1.1 §14.6): the app
/// passes the menu bar's height minus about 6 pt (`PillMetrics.height(forMenuBar:)`); renders and store screenshots
/// use `PillMetrics.standardHeight` (24). The default is 1.0's 22 pt, which fits any menu bar.
///
/// For the status item driven by `PillMotion` (1.1 §14.6): `textOpacity` draws everything but the gauge at that
/// opacity (slid a little while it fades) and the pill adds no animation of its own, since the app animates; nil
/// keeps the pill's own spring between layouts (1.0). `fillsWidth` makes the capsule fill the width it is given
/// (the item's length, which the app steps) and clip what doesn't fit yet; off, the pill is exactly as wide as its
/// content (renders).
public struct PillView: View {
    public let snapshot: HeadroomSnapshot
    public let moment: Moment?
    public let now: Date
    public let tool: ToolID?
    public let gaugePerTool: Bool
    public let attention: NeedsYouAttention?
    public let dismissedIDs: Set<String>
    public let height: CGFloat
    public let textOpacity: Double?
    public let fillsWidth: Bool
    /// The native status item owns its background so text/layout transactions cannot fade it.
    public let drawsBackground: Bool
    /// Native image rendering separates the steady gauges from fading text.
    public let gaugeOpacity: Double
    /// The live menu bar gives session names the same space in announcements and at rest.
    /// Status suffixes get their own space, so "needs you" never squeezes the name.
    public let sessionNameWidth: CGFloat?
    /// Live menu-bar gauges keep their percent visible while the title changes.
    public let keepsBadgeVisible: Bool
    /// The native compositor draws the completion check on its display clock; reserve its slot and show only the name.
    public let drawsCompletionSeparately: Bool
    public let differentiateWithoutColor: Bool?
    /// Show only the leading status/count; gauge selection remains controlled by `gaugePerTool`.
    public let compact: Bool

    public init(
        snapshot: HeadroomSnapshot,
        moment: Moment?,
        now: Date,
        tool: ToolID? = nil,
        gaugePerTool: Bool = false,
        attention: NeedsYouAttention? = nil,
        dismissedIDs: Set<String> = [],
        height: CGFloat = PillMetrics.minimumHeight,
        textOpacity: Double? = nil,
        fillsWidth: Bool = false,
        drawsBackground: Bool = true,
        gaugeOpacity: Double = 1,
        sessionNameWidth: CGFloat? = nil,
        keepsBadgeVisible: Bool = false,
        drawsCompletionSeparately: Bool = false,
        differentiateWithoutColor: Bool? = nil,
        compact: Bool = false
    ) {
        self.snapshot = snapshot
        self.moment = moment
        self.now = now
        self.tool = tool
        self.gaugePerTool = gaugePerTool
        self.attention = attention
        self.dismissedIDs = dismissedIDs
        self.height = height
        self.textOpacity = textOpacity
        self.fillsWidth = fillsWidth
        self.drawsBackground = drawsBackground
        self.gaugeOpacity = gaugeOpacity
        self.sessionNameWidth = sessionNameWidth
        self.keepsBadgeVisible = keepsBadgeVisible
        self.drawsCompletionSeparately = drawsCompletionSeparately
        self.differentiateWithoutColor = differentiateWithoutColor
        self.compact = compact
    }

    public var body: some View {
        PillContent(
            model: PillModel(
                snapshot: snapshot, moment: moment, now: now, tool: tool, gaugePerTool: gaugePerTool,
                attention: attention, dismissedIDs: dismissedIDs, height: height
            ),
            textOpacity: textOpacity,
            fillsWidth: fillsWidth,
            drawsBackground: drawsBackground,
            gaugeOpacity: gaugeOpacity,
            sessionNameWidth: sessionNameWidth,
            keepsBadgeVisible: keepsBadgeVisible,
            drawsCompletionSeparately: drawsCompletionSeparately,
            differentiateWithoutColor: differentiateWithoutColor,
            compact: compact
        )
    }
}

/// A black capsule: dot, count, ring gauge and tightest-limit number; while a moment is announced: symbol, text and
/// ring gauge; at rest while someone needs you: symbol, name, gauge and number. 22 pt tall in 1.0, taller with the
/// menu bar (`PillMetrics`).
///
/// With `fillsWidth` the capsule fills the width it is given when that is wider than its content, and clips the
/// content when it is narrower: the app steps the status item's length while the content changes, so the capsule
/// always follows the item, never the other way round (1.1 §14.6).
struct PillContent: View {
    let model: PillModel
    var textOpacity: Double? = nil
    var fillsWidth = false
    var drawsBackground = true
    var gaugeOpacity: Double = 1
    var sessionNameWidth: CGFloat? = nil
    var keepsBadgeVisible = false
    var drawsCompletionSeparately = false
    var differentiateWithoutColor: Bool? = nil
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The spring that widens the pill for a moment and narrows it again; none with Reduce Motion,
    /// so the layout changes at once.
    static func momentAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.78)
    }

    private var metrics: PillMetrics { model.metrics }
    /// The fading content's opacity and slide (1.1 §14.6): new text slides in from 3 pt to the left.
    private var fade: Double { textOpacity ?? 1 }
    private var slide: CGFloat { CGFloat(1 - fade) * -3 * metrics.scale }

    var body: some View {
        HStack(spacing: metrics.spacing) {
            leading
                .opacity(fade)
                .offset(x: slide)

            if model.isGaugePerTool {
                ToolGauges(model: model, fade: fade, gaugeOpacity: gaugeOpacity, keepsBadgeVisible: keepsBadgeVisible)
            } else {
                RingGauge(gauge: model.gauge, style: metrics.gaugeStyle)
                    .overlay {
                        if model.marksGaugeTool, let tool = model.tool {
                            GaugeToolIcon(
                                tool: tool, gauge: model.gauge, style: metrics.gaugeStyle,
                                background: HeadroomTheme.pillBackground
                            )
                        }
                    }
                    .opacity(gaugeOpacity)

                // Stale data dims only the rings (spec §1.1): the number stays at full contrast.
                if model.moment == nil || keepsBadgeVisible, let badge = model.badge {
                    Self.badgeText(badge)
                        .opacity(fade)
                }
            }
        }
        .font(.system(size: metrics.fontSize, weight: .medium).monospacedDigit())
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.height)
        .fixedSize()
        .modifier(FillsWidth(isOn: fillsWidth))
        .background(Capsule().fill(drawsBackground ? HeadroomTheme.pillBackground : .clear))
        .modifier(ClipsToCapsule(isOn: fillsWidth))
        .modifier(OwnPillAnimation(
            isOn: textOpacity == nil, animation: Self.momentAnimation(reduceMotion: reduceMotion), value: model.mode
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    /// What comes before the gauge: the moment, the needs-you rest state, or the dot and count.
    @ViewBuilder private var leading: some View {
        if compact {
            HStack(spacing: metrics.dotSpacing) {
                if let moment = model.moment {
                    if drawsCompletionSeparately, moment.tone == .finished {
                        Color.clear.frame(width: metrics.fontSize + 2, height: metrics.fontSize)
                    } else {
                        Image(systemName: moment.symbol)
                            .foregroundStyle(HeadroomTheme.color(for: moment.tone))
                    }
                } else if model.attention != nil {
                    Image(systemName: Symbols.needsYou)
                        .foregroundStyle(HeadroomTheme.waiting)
                } else {
                    PulsingDot(state: model.dot, diameter: metrics.dotDiameter, differentiateWithoutColor: differentiateWithoutColor)
                }
                if let count = model.count {
                    Text("\(count)").foregroundStyle(HeadroomTheme.primaryText)
                }
            }
        } else if let moment = model.moment {
            if drawsCompletionSeparately, moment.tone == .finished {
                Color.clear.frame(width: metrics.fontSize + 2, height: metrics.fontSize)
                Text(moment.name ?? moment.text)
                    .foregroundStyle(HeadroomTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: sessionNameWidth, alignment: .leading)
            } else {
                Image(systemName: moment.symbol)
                    .font(.system(size: metrics.fontSize, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.color(for: moment.tone))
                    .transition(.opacity)
                MomentText(moment: moment, maxNameWidth: sessionNameWidth)
                    .frame(maxWidth: moment.name != nil && sessionNameWidth != nil ? nil : metrics.maxMomentTextWidth,
                           alignment: .leading)
                    .transition(.opacity)
            }
        } else if let attention = model.attention {
            AttentionText(attention: attention, metrics: metrics,
                          maxNameWidth: sessionNameWidth ?? model.maxAttentionNameWidth)
                .transition(.opacity)
        } else {
            HStack(spacing: metrics.dotSpacing) {
                PulsingDot(state: model.dot, diameter: metrics.dotDiameter, differentiateWithoutColor: differentiateWithoutColor)
                if let count = model.count {
                    Text("\(count)").foregroundStyle(HeadroomTheme.primaryText)
                }
            }
            .transition(.opacity)
        }
    }
}

/// In the status item: as wide as the item, whatever the content needs, with the content at the leading edge.
private struct FillsWidth: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        } else {
            content
        }
    }
}

/// The pill's own spring between layouts, only when the app doesn't drive the motion. Off, the modifier is left out
/// altogether: an `.animation(nil, value:)` would replace the app's `withAnimation` for the step where the layout
/// changes, and the gauge would jump instead of sliding while the item's length moves (1.1 §14.10).
private struct OwnPillAnimation<Value: Equatable>: ViewModifier {
    let isOn: Bool
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        if isOn {
            content.animation(animation, value: value)
        } else {
            content
        }
    }
}

/// Content that doesn't fit the stepped width yet is cut at the capsule's edge instead of spilling past it.
private struct ClipsToCapsule: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.clipShape(Capsule())
        } else {
            content
        }
    }
}

extension PillContent {
    /// One gauge per tool, 5 pt apart at 22 pt, each dimmed on its own tool's staleness, with its own warning
    /// percentage immediately after it.
    struct ToolGauges: View {
        let model: PillModel
        var fade: Double = 1
        var gaugeOpacity: Double = 1
        var keepsBadgeVisible = false

        var body: some View {
            let metrics = model.metrics
            HStack(spacing: metrics.toolGaugeSpacing) {
                ForEach(Array(model.toolGauges.enumerated()), id: \.element.tool) { index, toolGauge in
                    RingGauge(gauge: toolGauge.gauge, style: metrics.gaugeStyle)
                        .overlay {
                            GaugeToolIcon(
                                tool: toolGauge.tool, gauge: toolGauge.gauge, style: metrics.gaugeStyle,
                                background: HeadroomTheme.pillBackground
                            )
                        }
                        .opacity(gaugeOpacity)
                    if model.moment == nil || keepsBadgeVisible, let badge = toolGauge.badge {
                        PillContent.badgeText(badge)
                            .opacity(fade)
                            // A little more room before the next gauge, so the number reads as this gauge's.
                            .padding(.trailing, index < model.toolGauges.count - 1 ? (2 * metrics.scale).rounded() : 0)
                    }
                }
            }
        }
    }

    static func badgeText(_ badge: PercentBadge) -> some View {
        Text(badge.text)
            .foregroundStyle(HeadroomTheme.color(for: badge.severity))
            .transition(.opacity)
    }
}

/// The needs-you rest state (1.1 §14.4): the amber symbol and the session's name, capped so the pill stays narrow
/// next to a notch, or "2 need you".
struct AttentionText: View {
    let attention: NeedsYouAttention
    let metrics: PillMetrics
    let maxNameWidth: CGFloat

    var body: some View {
        HStack(spacing: (5 * metrics.scale).rounded()) {
            Image(systemName: Symbols.needsYou)
                .font(.system(size: metrics.fontSize, weight: .semibold))
                .foregroundStyle(HeadroomTheme.waiting)
            if let name = attention.name {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxNameWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let status = attention.status {
                Text(status)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(HeadroomTheme.primaryText)
    }
}

/// A moment's text on one line. When it is too wide only the session name is cut, so
/// "… needs you" / "… finished" always stays readable.
struct MomentText: View {
    let moment: MomentDisplay
    var maxNameWidth: CGFloat? = nil

    var body: some View {
        if let parts = moment.parts {
            HStack(spacing: 0) {
                Text(parts.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxNameWidth, alignment: .leading)
                Text(" \(parts.status)")
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .foregroundStyle(HeadroomTheme.primaryText)
        } else {
            Text(moment.text)
                .foregroundStyle(HeadroomTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
