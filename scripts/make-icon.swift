#!/usr/bin/env swift
// Draws the Headroom app icon (a black rounded square with the two-ring gauge, spec §1.1 colors)
// at every macOS size and writes the AppIcon.appiconset contents.
//
// Usage: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/make-icon.swift [output.appiconset]
// Default output: App/Assets.xcassets/AppIcon.appiconset next to this script's repository.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconImage {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png" }
}

let images = [16, 32, 128, 256, 512].flatMap { [IconImage(points: $0, scale: 1), IconImage(points: $0, scale: 2)] }

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let trackColor = color(0x444441)
let weeklyColor = color(0xF1EFE8)   // outer ring: normal severity
let fiveHourColor = color(0xEF9F27) // inner ring: warning severity
let weeklyFraction: CGFloat = 0.72
let fiveHourFraction: CGFloat = 0.42

/// Apple's macOS icon grid: an 824-pt body centered on a 1024-pt canvas, corner radius ≈ 185.
func drawIcon(in context: CGContext, pixels: Int) {
    let s = CGFloat(pixels) / 1024
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    context.saveGState()
    if pixels >= 64 {
        context.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: color(0x000000, alpha: 0.35))
    }
    context.addPath(bodyPath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x1C1C1B), color(0x050505)] as CFArray,
        locations: [0, 1]
    )
    if let gradient {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    }
    context.restoreGState()

    // The gauge uses the panel's 64-unit geometry: outer r 26, inner r 17, line width 5.
    // Small sizes get a slightly larger gauge and a minimum stroke so the rings stay legible.
    let small = pixels <= 32
    let unit = 8.6 * s * (small ? 1.15 : 1)
    let lineWidth = max(5 * unit, small ? 1.25 : 0)
    let center = CGPoint(x: body.midX, y: body.midY)
    drawRing(in: context, center: center, radius: 26 * unit, lineWidth: lineWidth, fraction: weeklyFraction, color: weeklyColor)
    drawRing(in: context, center: center, radius: 17 * unit, lineWidth: lineWidth, fraction: fiveHourFraction, color: fiveHourColor)
}

/// A track circle plus a progress arc from 12 o'clock, clockwise, with round caps.
func drawRing(in context: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, fraction: CGFloat, color: CGColor) {
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)

    context.setStrokeColor(trackColor)
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.strokePath()

    let start = CGFloat.pi / 2
    context.setStrokeColor(color)
    context.addArc(center: center, radius: radius, startAngle: start, endAngle: start - fraction * 2 * .pi, clockwise: true)
    context.strokePath()
}

func renderPNG(pixels: Int, to url: URL) throws {
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { throw IconError.context }
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    drawIcon(in: context, pixels: pixels)
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw IconError.encode(url.lastPathComponent) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.encode(url.lastPathComponent) }
}

func contentsJSON() throws -> Data {
    let entries: [[String: String]] = images.map {
        ["filename": $0.filename, "idiom": "mac", "scale": "\($0.scale)x", "size": "\($0.points)x\($0.points)"]
    }
    let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
    return try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
}

enum IconError: Error {
    case context
    case encode(String)
}

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : repository.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for image in images {
        try renderPNG(pixels: image.pixels, to: output.appendingPathComponent(image.filename))
    }
    try contentsJSON().write(to: output.appendingPathComponent("Contents.json"))
    print("Wrote \(images.count) icons to \(output.path)")
} catch {
    FileHandle.standardError.write(Data("make-icon: \(error)\n".utf8))
    exit(1)
}
