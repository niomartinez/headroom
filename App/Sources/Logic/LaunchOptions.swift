import Foundation

/// How Headroom was asked to run.
enum LaunchMode: Equatable {
    /// The normal menu bar app.
    case menuBar
    /// `--render-live <dir>`: build real snapshots for a few seconds, write the live pill and panel
    /// as PNGs plus the snapshot as JSON into `directory`, then quit (see `LiveRender`).
    case renderLive(directory: URL)
}

/// Parses the command line. Arguments Headroom doesn't know (Launch Services' `-psn_…`, Xcode's
/// `-NSDocumentRevisionsDebugMode YES`) are ignored.
enum LaunchOptions {
    static let renderLiveFlag = "--render-live"
    static let usage = "usage: Headroom [--render-live <output-directory>]"

    enum ParseError: Error, Equatable {
        case missingDirectory
    }

    /// `arguments` is `CommandLine.arguments`: the first element is the executable. A relative
    /// directory is resolved against `currentDirectory`.
    static func mode(from arguments: [String], currentDirectory: URL) -> Result<LaunchMode, ParseError> {
        let options = Array(arguments.dropFirst())
        for (index, argument) in options.enumerated() {
            let value: String?
            if argument == renderLiveFlag {
                value = index + 1 < options.count ? options[index + 1] : nil
            } else if argument.hasPrefix(renderLiveFlag + "=") {
                value = String(argument.dropFirst(renderLiveFlag.count + 1))
            } else {
                continue
            }
            guard let value, !value.isEmpty, !value.hasPrefix("-") else { return .failure(.missingDirectory) }
            let directory = URL(fileURLWithPath: value, isDirectory: true, relativeTo: currentDirectory)
            return .success(.renderLive(directory: directory.standardizedFileURL))
        }
        return .success(.menuBar)
    }
}
