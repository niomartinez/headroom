import CoreGraphics
import Foundation
import ImageIO
import Testing

/// The golden rule (1.1 §0.1 invariant 1, §11.3, amended by §14.8): with only Claude tracked, the pill and panel
/// render as 1.0 plus Nio's feedback: the ring key, the taller (24 pt) pill with its rings on one centre, the
/// needs-you rest state and row marks, and the click-to-open hover. `Golden/` holds `headroom-render`'s Claude-only
/// review scenes, re-captured once by S9 after those changes: 1.0's scenes plus the feedback scenes
/// (`panel-ring-key-*`, `pill-needs-you-*`, `panel-needs-you-*`, `panel-open-hover-*`, `pill-height-*`). This test
/// runs the `headroom-render` built next to the test bundle into a temporary folder and compares each golden scene
/// pixel for pixel, tolerance 0. Scenes that are not in `Golden/` (the multi-tool and widget ones) are not compared.
///
/// Renders depend on the Mac's fonts, so the goldens are re-captured (`headroom-render` into a folder, copying only
/// the scenes named above, each as its most frequent render over several runs) only on purpose: after an intended
/// Claude-only change, or on a new macOS whose text rendering changed, and never to make this test pass.
@Suite(.serialized) struct GoldenRenderTests {
    /// Anything to find the test bundle by: SwiftPM builds `headroom-render` into the same folder.
    final class BundleMarker {}

    static let goldenDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden", isDirectory: true)

    /// ImageRenderer's antialiasing isn't always bit-identical from one run to the next: one scene
    /// (`pill-waiting`) came out with 6 pixels one level off in about one run in five, from the same
    /// binary. So a scene that differs is rendered again, up to `attempts` times in all, and passes when
    /// any render equals its golden exactly. A real change differs every time.
    static let attempts = 5

    @Test func claudeOnlyScenesArePixelIdenticalToTheGoldens() throws {
        let golden = try FileManager.default.contentsOfDirectory(at: Self.goldenDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!golden.isEmpty, "no golden renders in \(Self.goldenDirectory.path)")

        var mismatches: [String: String] = [:]
        var pending = golden
        for _ in 0..<Self.attempts where !pending.isEmpty {
            let rendered = try Self.renderReviewScenes()
            defer { try? FileManager.default.removeItem(at: rendered) }
            pending = try pending.filter { goldenFile in
                let name = goldenFile.lastPathComponent
                let renderedFile = rendered.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: renderedFile.path) else {
                    mismatches[name] = "headroom-render no longer renders this scene"
                    return true
                }
                let expected = try #require(RGBAImage(contentsOf: goldenFile), "\(name): golden unreadable")
                let actual = try #require(RGBAImage(contentsOf: renderedFile), "\(name): render unreadable")
                mismatches[name] = actual.difference(from: expected)
                return mismatches[name] != nil
            }
        }
        let report = pending.map { "\($0.lastPathComponent): \(mismatches[$0.lastPathComponent] ?? "differs")" }
        #expect(report.isEmpty, "Claude-only scenes changed:\n\(report.joined(separator: "\n"))")
    }

    /// Runs `headroom-render <temp dir>` and returns the folder.
    private static func renderReviewScenes() throws -> URL {
        let buildDirectory = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        let tool = buildDirectory.appendingPathComponent("headroom-render")
        try #require(
            FileManager.default.isExecutableFile(atPath: tool.path),
            "headroom-render isn't built next to the tests (\(tool.path)); run `swift build` first"
        )
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-golden-\(UUID().uuidString)", isDirectory: true)
        let process = Process()
        process.executableURL = tool
        process.arguments = [output.path]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "headroom-render failed (\(process.terminationStatus)): \(message)")
        return output
    }
}

/// A PNG decoded to premultiplied RGBA8 in sRGB, for exact comparison.
struct RGBAImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Nil when every pixel is equal; otherwise what differs.
    func difference(from other: RGBAImage) -> String? {
        guard width == other.width, height == other.height else {
            return "size \(width)×\(height) px, golden \(other.width)×\(other.height) px"
        }
        guard bytes != other.bytes else { return nil }
        var changed = 0
        var first: (x: Int, y: Int)?
        for pixel in 0..<(width * height) {
            let i = pixel * 4
            if bytes[i..<(i + 4)] != other.bytes[i..<(i + 4)] {
                changed += 1
                if first == nil { first = (pixel % width, pixel / width) }
            }
        }
        let at = first.map { " (first at x \($0.x), y \($0.y))" } ?? ""
        return "\(changed) of \(width * height) pixels differ\(at)"
    }
}
