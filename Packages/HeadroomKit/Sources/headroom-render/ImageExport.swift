import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Writes SwiftUI views to PNG files through `ImageRenderer`.
@MainActor
enum ImageExport {
    enum ExportError: Error, CustomStringConvertible {
        case renderFailed(String)
        case encodingFailed(String)
        case wrongSize(String, expected: CGSize, actual: CGSize)

        var description: String {
            switch self {
            case let .renderFailed(name): "\(name): ImageRenderer produced no image"
            case let .encodingFailed(name): "\(name): couldn't encode the PNG"
            case let .wrongSize(name, expected, actual):
                "\(name): rendered \(Int(actual.width))×\(Int(actual.height)), expected \(Int(expected.width))×\(Int(expected.height))"
            }
        }
    }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An opaque sRGB PNG with no alpha channel, exactly `pixels` in size (App Store screenshots).
    static func writeOpaque(_ view: some View, points: CGSize, scale: CGFloat, to url: URL) throws {
        let name = url.lastPathComponent
        let renderer = ImageRenderer(content: view.frame(width: points.width, height: points.height))
        renderer.scale = scale
        renderer.isOpaque = true
        guard let rendered = renderer.cgImage else { throw ExportError.renderFailed(name) }
        let expected = CGSize(width: points.width * scale, height: points.height * scale)
        let actual = CGSize(width: rendered.width, height: rendered.height)
        guard actual == expected else { throw ExportError.wrongSize(name, expected: expected, actual: actual) }

        // Redrawn into an 8-bit sRGB context without alpha, so the file is RGB (no alpha channel),
        // tagged sRGB, whatever color space and alpha ImageRenderer used.
        guard let context = CGContext(
            data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw ExportError.encodingFailed(name) }
        context.interpolationQuality = .none
        context.draw(rendered, in: CGRect(origin: .zero, size: actual))
        guard let flattened = context.makeImage() else { throw ExportError.encodingFailed(name) }
        try write(flattened, to: url)
    }

    /// A PNG with a transparent background at `scale` (website assets).
    static func writeTransparent(_ view: some View, scale: CGFloat, to url: URL) throws {
        let name = url.lastPathComponent
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        guard let rendered = renderer.cgImage else { throw ExportError.renderFailed(name) }
        guard let context = CGContext(
            data: nil, width: rendered.width, height: rendered.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ExportError.encodingFailed(name) }
        context.clear(CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        context.draw(rendered, in: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height))
        guard let converted = context.makeImage() else { throw ExportError.encodingFailed(name) }
        try write(converted, to: url)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed(url.lastPathComponent) }
    }
}
