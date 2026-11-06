import Foundation
import HeadroomModel
@testable import UsageKit

/// Parses `2026-09-20T10:52:00Z`-style UTC timestamps. A typo yields `.distantPast`, which fails the assertion.
func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text) ?? .distantPast
}

func sample(
    _ time: String,
    org: String = "org-a",
    fh: Double? = nil,
    sd: Double? = nil,
    xu: Double? = nil
) -> DesktopUsageSample {
    DesktopUsageSample(time: utc(time), org: org, fiveHour: fh, weekly: sd, extra: xu)
}

let minute: TimeInterval = 60
let hour: TimeInterval = 3600
let week: TimeInterval = 7 * 24 * 3600

/// A fresh directory under the system temp dir, unique per call.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("UsageKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `contents` to a new temp file and optionally sets its modification date.
func writeTempFile(_ contents: String, name: String = "file.json", modified: Date? = nil) throws -> URL {
    try writeTempFile(Data(contents.utf8), name: name, modified: modified)
}

func writeTempFile(_ data: Data, name: String = "file.json", modified: Date? = nil) throws -> URL {
    let url = try makeTempDirectory().appendingPathComponent(name)
    try data.write(to: url)
    if let modified {
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
    return url
}

/// Copies a file from `Fixtures/` to a temp dir (so its modification date can be set).
func copyFixture(_ name: String, modified: Date? = nil) throws -> URL {
    guard let source = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
        throw FixtureError.missing(name)
    }
    return try writeTempFile(try Data(contentsOf: source), name: name, modified: modified)
}

enum FixtureError: Error {
    case missing(String)
}
