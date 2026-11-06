import Foundation

/// Reads the Claude desktop app's usage history file (spec §2.1).
public struct DesktopUsageReader: Sendable {
    /// The real file is tens of KB; anything this large is not the format we know.
    static let maxFileSize = 16 * 1024 * 1024

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// All samples (every org), sorted by time ascending.
    ///
    /// Accepts `version` `"2"` or `2` (the app writes a number today). Any other version, or any sample
    /// whose fields have unexpected types, fails the whole file so no wrong numbers reach the UI.
    public func readSamples() throws -> [DesktopUsageSample] {
        let data: Data
        switch readRegularFile(at: fileURL, limit: Self.maxFileSize) {
        case .file(let contents, _): data = contents
        case .unreadable: throw DesktopUsageError.fileMissing
        case .tooLarge: throw DesktopUsageError.unrecognizedFormat
        }
        guard let file = try? JSONDecoder().decode(HistoryFile.self, from: data), file.version == "2" else {
            throw DesktopUsageError.unrecognizedFormat
        }
        return file.samples.map(\.sample).sortedByTime()
    }
}

private struct HistoryFile: Decodable {
    let version: String
    let samples: [RawSample]

    private enum CodingKeys: String, CodingKey {
        case version, samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .version) {
            version = text
        } else {
            version = String(try container.decode(Int.self, forKey: .version))
        }
        samples = try container.decode([RawSample].self, forKey: .samples)
    }
}

/// `{"t":<epoch ms>,"org":"<uuid>","u":{"fh":8,"sd":87,"xu":null}}`
private struct RawSample: Decodable {
    struct Usage: Decodable {
        let fh: Double?
        let sd: Double?
        let xu: Double?
    }

    let t: Double
    let org: String
    let u: Usage

    var sample: DesktopUsageSample {
        DesktopUsageSample(
            time: Date(timeIntervalSince1970: t / 1000),
            org: org,
            fiveHour: u.fh,
            weekly: u.sd,
            extra: u.xu
        )
    }
}
