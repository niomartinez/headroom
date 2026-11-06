import AppKit
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// The system accessibility display settings (spec §1.1): Reduce Motion and Differentiate Without Color.
@MainActor @Suite struct AccessibilitySettingsTests {
    // MARK: Reduce Motion

    @Test func momentAnimationHonoursReduceMotion() {
        #expect(PillContent.momentAnimation(reduceMotion: true) == nil)
        #expect(PillContent.momentAnimation(reduceMotion: false) == .spring(response: 0.45, dampingFraction: 0.78))
    }

    // MARK: Differentiate Without Color

    /// The working and waiting dots are green and amber of almost the same luminance, so without
    /// color the waiting dot needs its own shape.
    @Test func onlyTheWaitingDotChangesShapeWithoutColor() {
        #expect(PulsingDot.mark(for: .waiting, differentiateWithoutColor: true) == .ring)
        #expect(PulsingDot.mark(for: .waiting, differentiateWithoutColor: false) == .disc)
        for state in [DotState.working, .idle] {
            #expect(PulsingDot.mark(for: state, differentiateWithoutColor: true) == .disc)
            #expect(PulsingDot.mark(for: state, differentiateWithoutColor: false) == .disc)
        }
    }

    @Test func waitingDotIsHollowWithoutColor() throws {
        let plain = try render(PulsingDot(state: .waiting, diameter: 7), differentiateWithoutColor: false)
        let ring = try render(PulsingDot(state: .waiting, diameter: 7), differentiateWithoutColor: true)
        #expect(plain.width == ring.width && plain.height == ring.height)

        // The disc is amber all the way through; the ring keeps its amber edge around an empty middle.
        let center = (x: plain.width / 2, y: plain.height / 2)
        #expect(pixel(plain, center.x, center.y).alpha > 0.9)
        #expect(pixel(ring, center.x, center.y).alpha < 0.1)
        let edge = pixel(ring, 1, center.y)
        #expect(edge.alpha > 0.5 && edge.red > edge.blue, "the ring keeps the waiting color")
    }

    @Test func otherDotsKeepTheirDiscWithoutColor() throws {
        for state in [DotState.working, .idle] {
            let plain = try render(PulsingDot(state: state, diameter: 7), differentiateWithoutColor: false, reduceMotion: true)
            let setting = try render(PulsingDot(state: state, diameter: 7), differentiateWithoutColor: true, reduceMotion: true)
            #expect(pixel(setting, setting.width / 2, setting.height / 2).alpha > 0.9, "\(state)")
            #expect(pixels(plain) == pixels(setting), "\(state)")
        }
    }

    // MARK: Helpers

    private struct RGBA: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
    }

    /// Renders at 4× so a 7 pt dot is 28 pixels across.
    private func render(_ view: some View, differentiateWithoutColor: Bool, reduceMotion: Bool = false) throws -> CGImage {
        let renderer = ImageRenderer(
            content: view
                .environment(\._accessibilityDifferentiateWithoutColor, differentiateWithoutColor)
                .environment(\._accessibilityReduceMotion, reduceMotion)
        )
        renderer.scale = 4
        return try #require(renderer.cgImage)
    }

    /// Every pixel as premultiplied RGBA bytes in sRGB, top row first.
    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    /// The pixel at column `x`, row `y` (from the top), unpremultiplied.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
        let bytes = pixels(image)
        let offset = (y * image.width + x) * 4
        let alpha = Double(bytes[offset + 3]) / 255
        func channel(_ i: Int) -> Double { alpha > 0 ? Double(bytes[offset + i]) / 255 / alpha : 0 }
        return RGBA(red: channel(0), green: channel(1), blue: channel(2), alpha: alpha)
    }
}
