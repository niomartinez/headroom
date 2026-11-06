import AppKit
import HeadroomModel
import HeadroomUI
import SwiftUI

// Renders synthetic pill and panel states to PNG files (spec §5). Never reads real data.
//   headroom-render <dir>            every pill and panel state on gray, for review by eye
//   headroom-render --store <dir>    the Mac App Store screenshots, 2880×1800 opaque sRGB
//   headroom-render --assets <dir>   website PNGs on transparent backgrounds (pills 3×, panels 2×)
//   headroom-render --marketing <dir>  the 1.1 feature snippets, 2× on transparent backgrounds

let usage = "usage: headroom-render [--store | --assets | --marketing] <output-directory>\n"

enum Mode {
    case review
    case store
    case assets
    case marketing
}

let arguments = Array(CommandLine.arguments.dropFirst())
let mode: Mode
let path: String
switch arguments.count {
case 1 where !arguments[0].hasPrefix("-"):
    (mode, path) = (.review, arguments[0])
case 2 where arguments[0] == "--store":
    (mode, path) = (.store, arguments[1])
case 2 where arguments[0] == "--assets":
    (mode, path) = (.assets, arguments[1])
case 2 where arguments[0] == "--marketing":
    (mode, path) = (.marketing, arguments[1])
default:
    FileHandle.standardError.write(Data(usage.utf8))
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("headroom-render: cannot create \(outputDirectory.path): \(error.localizedDescription)\n".utf8))
    exit(73)
}

var failures = 0
@MainActor func render(_ name: String, _ write: (URL) throws -> Void) {
    let url = outputDirectory.appendingPathComponent("\(name).png")
    do {
        try write(url)
        print(url.path)
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("headroom-render: \(name): \(error)\n".utf8))
    }
}

switch mode {
case .review:
    for scene in RenderScene.all {
        render(scene.name, scene.writePNG(to:))
    }
case .store:
    for screenshot in StoreScreenshot.all {
        render(screenshot.name, screenshot.write(to:))
    }
case .assets:
    for asset in MarketingAsset.all {
        render(asset.name, asset.write(to:))
    }
case .marketing:
    for snippet in MarketingAsset.snippets {
        render(snippet.name, snippet.write(to:))
    }
}
exit(failures == 0 ? 0 : 1)
