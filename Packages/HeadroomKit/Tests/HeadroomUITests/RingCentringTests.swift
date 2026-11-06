import CoreGraphics
import Foundation
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// Nio's note 4 (1.1 §14.6): "the inner ring looks off-centre when it turns orange or red". Measured from pixels: in
/// 1.0 each ring was a circle in a frame of its own size, centred in the gauge. The inner ring's 7 pt frame sits on
/// a half point (5.5 pt into the 18 pt gauge), and the layout rounds each frame to the pixel grid on its own, so at
/// 1x and 3x the inner ring was drawn 0.5 px right of and below the outer ring's centre (0.2–0.4 px at 2x in a
/// taller pill, whose gauge isn't 18 pt). Colored, the arcs make that visible. Now every ring is drawn in the
/// gauge's own square around its centre (`RingShape`), and both rings share one centre to within a few hundredths
/// of a pixel.
///
/// Each ring's centre is found by fitting a circle to its pixels (weighted by how bright they are), which is
/// unbiased for an arc with a gap and for any mix of colors, unlike a centroid.
@MainActor @Suite struct RingCentringTests {
    /// How far apart the two rings' centres may be.
    static let tolerance = 0.25

    struct Bitmap {
        let width: Int
        let height: Int
        let rgba: [UInt8]

        /// Premultiplied, so the brightest channel is how much a colored stroke covers the pixel (over black or
        /// transparent), scaled by the color's own brightness.
        func weight(_ x: Int, _ y: Int) -> Double {
            let i = (y * width + x) * 4
            return Double(max(rgba[i], rgba[i + 1], rgba[i + 2])) / 255
        }
    }

    static func render(_ view: some View, scale: CGFloat) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        let image = try #require(renderer.cgImage)
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Bitmap(width: width, height: height, rgba: bytes)
    }

    /// The centre of the circle best fitting the weighted pixels (Kåsa's algebraic fit), in pixels.
    static func fitCentre(_ points: [(x: Double, y: Double, w: Double)]) -> (x: Double, y: Double)? {
        guard let first = points.first else { return nil }
        // Relative to one of the points, for well-conditioned sums.
        let (ox, oy) = (first.x, first.y)
        var (sxx, sxy, syy, sx, sy, s, sxz, syz, sz) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        for point in points {
            let (x, y, w) = (point.x - ox, point.y - oy, point.w)
            let z = x * x + y * y
            sxx += w * x * x; sxy += w * x * y; syy += w * y * y
            sx += w * x; sy += w * y; s += w
            sxz += w * x * z; syz += w * y * z; sz += w * z
        }
        // [sxx sxy sx; sxy syy sy; sx sy s] · [D E F] = −[sxz syz sz]; centre = (−D/2, −E/2).
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, s]]
        let b = [-sxz, -syz, -sz]
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-12 else { return nil }
        func replacing(_ column: Int) -> [[Double]] {
            m.enumerated().map { row, values in values.enumerated().map { $0.offset == column ? b[row] : $0.element } }
        }
        let dCoefficient = det(replacing(0)) / d
        let eCoefficient = det(replacing(1)) / d
        return (ox - dCoefficient / 2, oy - eCoefficient / 2)
    }

    /// Both rings' fitted centres, from the pixels inside `crop` (pixels), split at `split` pixels from the gauge's
    /// centre: first taken as the crop's middle, then as the outer ring's fitted centre, since the gauge may sit a
    /// pixel off where the layout says.
    static func ringCentres(
        _ bitmap: Bitmap, crop: CGRect, split: Double
    ) throws -> (outer: (x: Double, y: Double), inner: (x: Double, y: Double)) {
        let first = try ringCentres(bitmap, crop: crop, split: split, around: (Double(crop.midX), Double(crop.midY)))
        return try ringCentres(bitmap, crop: crop, split: split, around: first.outer)
    }

    private static func ringCentres(
        _ bitmap: Bitmap, crop: CGRect, split: Double, around centre: (x: Double, y: Double)
    ) throws -> (outer: (x: Double, y: Double), inner: (x: Double, y: Double)) {
        let (cx, cy) = centre
        var outer: [(x: Double, y: Double, w: Double)] = []
        var inner: [(x: Double, y: Double, w: Double)] = []
        for y in max(0, Int(crop.minY))..<min(bitmap.height, Int(crop.maxY.rounded(.up))) {
            for x in max(0, Int(crop.minX))..<min(bitmap.width, Int(crop.maxX.rounded(.up))) {
                let w = bitmap.weight(x, y)
                guard w > 0 else { continue }
                let (px, py) = (Double(x) + 0.5, Double(y) + 0.5)
                let distance = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
                if distance >= split { outer.append((px, py, w)) } else { inner.append((px, py, w)) }
            }
        }
        return (
            try #require(fitCentre(coverage(outer, around: centre))),
            try #require(fitCentre(coverage(inner, around: centre)))
        )
    }

    /// Brightness turned into coverage: each pixel over the brightest one at its angle, so the bright arc and the
    /// dim track count alike and only the ring's shape decides the fit.
    private static func coverage(
        _ points: [(x: Double, y: Double, w: Double)], around centre: (x: Double, y: Double)
    ) -> [(x: Double, y: Double, w: Double)] {
        let bins = 72
        func bin(_ point: (x: Double, y: Double, w: Double)) -> Int {
            let angle = atan2(point.y - centre.y, point.x - centre.x) + .pi
            return min(bins - 1, Int(angle / (2 * .pi) * Double(bins)))
        }
        var brightest = [Double](repeating: 0, count: bins)
        for point in points { brightest[bin(point)] = max(brightest[bin(point)], point.w) }
        return points.map { ($0.x, $0.y, $0.w / max(brightest[bin($0)], 1e-9)) }
    }

    static func distance(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Radius at which pixels change from the inner ring to the outer: the middle of the gap between them.
    static func split(_ style: RingGauge.Style, pixelsPerPoint: CGFloat) -> Double {
        let innerEdge = style.innerRadius + style.lineWidth / 2
        let outerEdge = style.outerRadius - style.lineWidth / 2
        return Double((innerEdge + outerEdge) / 2 * style.scale * pixelsPerPoint)
    }

    static let heights: [CGFloat] = [22, 24, 30]
    static let scales: [CGFloat] = [1, 2, 3]
    /// Warning, critical, and only one ring colored.
    nonisolated static let plans: [(weekly: Double, fiveHour: Double)] = [(88, 88), (97, 97), (42, 88), (88, 42)]

    /// The pill as the menu bar shows it: no sessions (a gray dot, no count), the rings, the number.
    @Test(arguments: plans.indices)
    func pillRingsShareOneCentre(plan index: Int) throws {
        let plan = Self.plans[index]
        let snapshot = Fixture.snapshot(plan: Fixture.plan(weekly: plan.weekly, fiveHour: plan.fiveHour))
        for height in Self.heights {
            let metrics = PillMetrics(height: height)
            let style = metrics.gaugeStyle
            for scale in Self.scales {
                let bitmap = try Self.render(PillView(snapshot: snapshot, moment: nil, now: Fixture.now, height: height), scale: scale)
                // The gauge follows the dot: padding, dot, spacing. Half the spacing around it keeps the dot and the
                // number out.
                let x = metrics.horizontalPadding + metrics.dotDiameter + metrics.spacing
                let margin = metrics.spacing / 2
                let crop = CGRect(
                    x: (x - margin) * scale, y: (metrics.height - style.size) / 2 * scale - margin * scale,
                    width: (style.size + 2 * margin) * scale, height: (style.size + 2 * margin) * scale
                )
                let centres = try Self.ringCentres(bitmap, crop: crop, split: Self.split(style, pixelsPerPoint: scale))
                let apart = Self.distance(centres.outer, centres.inner)
                #expect(
                    apart <= Self.tolerance,
                    "weekly \(plan.weekly)%, 5-hour \(plan.fiveHour)%, \(height) pt pill at \(scale)x: centres \(apart) px apart"
                )
            }
        }
    }

    /// The gauge anywhere in a row, at fractional positions too: the whole gauge may snap to the pixel grid, but
    /// its rings move together.
    @Test(arguments: [0.0, 0.25, 0.3, 0.5, 0.75])
    func gaugeRingsShareOneCentreAtAnyOffset(offset: Double) throws {
        let gauge = GaugeModel(
            outer: .init(fraction: 0.88, severity: .warning), inner: .init(fraction: 0.97, severity: .critical), isStale: false
        )
        for size in [18.0, 20, 24] {
            let style = RingGauge.Style.pill(size: size)
            for scale in Self.scales {
                let view = HStack(spacing: 0) {
                    Color.clear.frame(width: offset, height: 1)
                    RingGauge(gauge: gauge, style: style)
                }
                .padding(2)
                let bitmap = try Self.render(view, scale: scale)
                let crop = CGRect(x: (2 + offset) * scale, y: 2 * scale, width: size * scale, height: size * scale)
                let centres = try Self.ringCentres(bitmap, crop: crop, split: Self.split(style, pixelsPerPoint: scale))
                let apart = Self.distance(centres.outer, centres.inner)
                #expect(apart <= Self.tolerance, "\(size) pt gauge at +\(offset) pt, \(scale)x: centres \(apart) px apart")
            }
        }
    }

    /// The panel's 72 pt gauge and the compact rows' 24 pt one, whose view boxes don't match their sizes.
    @Test(arguments: [RingGauge.Style.panel, .compact])
    func panelGaugesShareOneCentre(style: RingGauge.Style) throws {
        let gauge = GaugeModel(
            outer: .init(fraction: 0.42, severity: .normal), inner: .init(fraction: 0.88, severity: .warning), isStale: false
        )
        for scale in Self.scales {
            let bitmap = try Self.render(RingGauge(gauge: gauge, style: style).padding(3), scale: scale)
            let crop = CGRect(x: 3 * scale, y: 3 * scale, width: style.size * scale, height: style.size * scale)
            let centres = try Self.ringCentres(bitmap, crop: crop, split: Self.split(style, pixelsPerPoint: scale))
            #expect(Self.distance(centres.outer, centres.inner) <= Self.tolerance, "\(style.size) pt at \(scale)x")
        }
    }

    /// The fit itself: a synthetic arc with a gap gives back its centre.
    @Test func circleFitFindsTheCentreOfAnArc() throws {
        let points = stride(from: 0.0, to: 300, by: 2).map { degrees -> (x: Double, y: Double, w: Double) in
            let angle = degrees * .pi / 180
            return (10.25 + 7 * cos(angle), 11.75 + 7 * sin(angle), degrees < 150 ? 1 : 0.3)
        }
        let centre = try #require(Self.fitCentre(points))
        #expect(abs(centre.x - 10.25) < 1e-6 && abs(centre.y - 11.75) < 1e-6)
    }
}
