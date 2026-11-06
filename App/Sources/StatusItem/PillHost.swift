import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

/// The native status button receives a full-color image, not a hosted subview. AppKit replicates images correctly
/// onto inactive menu bars. Both pixel densities have the same point size, so moving focus never scales the text.
@MainActor
struct PillImageFrame {
    let key: PillDrawKey
    let size: NSSize
    let gaugeX: CGFloat
    private let text: NSImage
    private let gauges: NSImage
    private let model: PillModel

    init?(inputs: PillInputs, differentiateWithoutColor: Bool) {
        key = PillDrawKey(inputs)
        let model = inputs.model
        var compact = inputs.compact
        var nameWidth = model.metrics.maxMomentTextWidth
        func content(textOpacity: Double, gaugeOpacity: Double) -> some View {
            PillView(
                snapshot: inputs.snapshot, moment: inputs.moment, now: inputs.now, tool: inputs.tool,
                gaugePerTool: inputs.gaugePerTool && !inputs.compact, attention: inputs.attention, dismissedIDs: inputs.dismissedIDs,
                height: inputs.height, textOpacity: textOpacity, drawsBackground: false,
                gaugeOpacity: gaugeOpacity, sessionNameWidth: nameWidth,
                keepsBadgeVisible: true, drawsCompletionSeparately: true,
                differentiateWithoutColor: differentiateWithoutColor, compact: compact
            )
            .environment(\.colorScheme, .dark)
            .environment(\.frozenPulsePhase, 1)
        }
        // Measure the fully visible layout; opacity must never change its allocated width.
        func measure() -> CGSize {
            let renderer = ImageRenderer(content: content(textOpacity: 1, gaugeOpacity: 1))
            var measured = CGSize.zero
            renderer.render { size, _ in measured = size }
            return measured
        }
        // Measure the fixed icon/gauge/padding cost, then give the name all remaining native space.
        // This is done before animation: the title never reflows a second time after the capsule expands.
        if let maximumWidth = inputs.maximumWidth, maximumWidth.isFinite {
            nameWidth = 0
            let fixedWidth = measure().width
            nameWidth = max(0, floor(maximumWidth - fixedWidth))
            // Shorten the title before sacrificing any selected tool gauges. The width estimate cannot tell
            // whether macOS actually has room for this item, so Automatic never hides a requested gauge.
            if fixedWidth > maximumWidth || ((model.moment != nil || model.attention != nil)
                && nameWidth < model.metrics.fontSize * 4) {
                compact = true
            }
        }
        self.model = model
        let measured = measure()
        guard measured.width.isFinite, measured.width > 0 else { return nil }
        let size = NSSize(width: ceil(measured.width), height: model.metrics.height)
        guard let text = Self.render(content(textOpacity: 1, gaugeOpacity: 0), size: size),
              let gauges = Self.render(content(textOpacity: 0, gaugeOpacity: 1), size: size)
        else { return nil }
        self.size = size
        self.text = text
        self.gauges = gauges
        gaugeX = Self.firstPaintedColumn(in: gauges)
    }

    private static func render(_ content: some View, size: NSSize) -> NSImage? {
        let image = NSImage(size: size)
        for scale: CGFloat in [1, 2] {
            let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height, alignment: .leading))
            renderer.scale = scale
            guard let bitmap = renderer.cgImage else { return nil }
            let representation = NSBitmapImageRep(cgImage: bitmap)
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = false
        return image
    }

    /// Locate the gauge group once, so it can slide between layouts without stretching any glyphs or rings.
    private static func firstPaintedColumn(in image: NSImage) -> CGFloat {
        guard let bitmap = image.representations.first as? NSBitmapImageRep else { return 0 }
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                return CGFloat(x)
            }
        }
        return 0
    }

    var pulses: Bool { model.mode == .normal && model.dot == .working }

    /// Only compositing runs during motion and the working pulse; SwiftUI renders only when content changes.
    func image(width: CGFloat, textOpacity: Double, gaugeOffset: CGFloat = 0, pulseDate: Date? = nil) -> NSImage {
        let size = NSSize(width: width.isFinite ? max(1, ceil(width)) : size.width, height: size.height)
        let image = Self.composite(size: size) { bounds in
            let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            capsule.addClip()
            NSColor(HeadroomTheme.pillBackground).setFill()
            capsule.fill()
            if pulses, let pulseDate, textOpacity > 0 {
                let metrics = model.metrics
                let phase = PulsingDot.phase(at: pulseDate)
                let diameter = PulsingDot.ringDiameter(metrics.dotDiameter, phase: phase)
                let center = NSPoint(x: metrics.horizontalPadding + metrics.dotDiameter / 2,
                                     y: bounds.midY)
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                     width: diameter, height: diameter))
                ring.lineWidth = PulsingDot.ringLineWidth
                NSColor(HeadroomTheme.working).withAlphaComponent(PulsingDot.ringOpacity(phase: phase) * textOpacity).setStroke()
                ring.stroke()
            }
            gauges.draw(at: NSPoint(x: gaugeOffset, y: 0), from: .zero, operation: .sourceOver, fraction: 1)
            text.draw(at: NSPoint(x: -3 * model.metrics.scale * (1 - textOpacity), y: 0),
                      from: .zero, operation: .sourceOver, fraction: textOpacity)
            if textOpacity > 0 { drawCompletion(at: .zero, progress: 1, opacity: textOpacity) }
        }
        image.isTemplate = false
        return image
    }

    /// Reveals the incoming content at full opacity while moving the capsule and trailing group on one clock.
    /// Clipping follows the capsule; nothing waits for a later fade. The image canvas stays fixed throughout.
    func transitionImage(from previous: PillImageFrame, width: CGFloat, canvasWidth: CGFloat, progress: Double) -> NSImage {
        let canvas = NSSize(width: ceil(canvasWidth), height: size.height)
        let progress = min(max(progress, 0), 1)
        let image = Self.composite(size: canvas) { bounds in
            let scale = abs(NSGraphicsContext.current?.cgContext.ctm.a ?? 1)
            func aligned(_ x: CGFloat) -> CGFloat { (x * scale).rounded() / scale }
            let width = aligned(min(max(width, 1), bounds.width))
            let origin = NSPoint(x: bounds.maxX - width, y: 0)
            let capsule = NSBezierPath(roundedRect: NSRect(origin: origin, size: NSSize(width: width, height: bounds.height)),
                                       xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            capsule.addClip()
            NSColor(HeadroomTheme.pillBackground).setFill()
            capsule.fill()
            let gauge = aligned(previous.gaugeX + (gaugeX - previous.gaugeX) * progress)

            func draw(_ frame: PillImageFrame) {
                NSGraphicsContext.saveGraphicsState()
                // The percent belongs to the trailing group, so it moves with its gauge instead of its title.
                let leadingWidth = max(0, min(gauge, frame.gaugeX) - frame.model.metrics.spacing)
                NSBezierPath(rect: NSRect(x: origin.x, y: 0, width: leadingWidth, height: bounds.height)).addClip()
                frame.text.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
                // The capsule uses ease-out; the hand-drawn stroke uses a gentle ease-in/out on that same clock.
                let time = 1 - cbrt(1 - progress)
                let checkProgress = previous.key.moment == key.moment ? 1 : time * time * (3 - 2 * time)
                frame.drawCompletion(at: origin, progress: checkProgress)
                NSGraphicsContext.restoreGraphicsState()

                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: origin.x + gauge, y: 0, width: bounds.width, height: bounds.height)).addClip()
                let trailing = NSPoint(x: aligned(origin.x + gauge - frame.gaugeX), y: 0)
                frame.gauges.draw(at: trailing, from: .zero, operation: .sourceOver, fraction: 1)
                frame.text.draw(at: trailing, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
            draw(self)
        }
        image.isTemplate = false
        return image
    }

    /// Inactive menu bars can show a cached copy without drawing the original button. Hand AppKit finished
    /// pixels at both densities, rather than a lazy drawing handler that needs the backing window to repaint.
    private static func composite(size: NSSize, draw: (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: size)
        for scale: CGFloat in [1, 2] {
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.clear(CGRect(origin: .zero, size: size))
            draw(NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        return image
    }

    /// A two-segment check, drawn by distance with round ends. No circle, scaling, or delayed icon swap.
    nonisolated private func drawCompletion(at origin: NSPoint, progress: Double, opacity: Double = 1) {
        guard model.moment?.tone == .finished, progress > 0 else { return }
        let metrics = model.metrics
        let side = metrics.fontSize
        let x = origin.x + metrics.horizontalPadding + 1
        let y = origin.y + (size.height - side) / 2
        let points = [NSPoint(x: x + side * 0.08, y: y + side * 0.48),
                      NSPoint(x: x + side * 0.37, y: y + side * 0.20),
                      NSPoint(x: x + side * 0.94, y: y + side * 0.83)]
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = lengths.reduce(0, +) * min(max(progress, 0), 1)
        let path = NSBezierPath()
        path.move(to: points[0])
        for index in lengths.indices {
            let fraction = min(remaining / lengths[index], 1)
            let start = points[index], end = points[index + 1]
            path.line(to: NSPoint(x: start.x + (end.x - start.x) * fraction,
                                 y: start.y + (end.y - start.y) * fraction))
            remaining -= lengths[index]
            if remaining <= 0 { break }
        }
        path.lineWidth = 1.8 * metrics.scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor(HeadroomTheme.color(for: .finished)).withAlphaComponent(opacity).setStroke()
        path.stroke()
    }
}
