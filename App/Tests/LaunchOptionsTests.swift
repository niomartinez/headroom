import Foundation
import Testing

@Suite struct LaunchOptionsTests {
    private let executable = "/Applications/Headroom.app/Contents/MacOS/Headroom"
    private let cwd = URL(fileURLWithPath: "/tmp/work", isDirectory: true)

    private func directory(_ arguments: [String]) -> String? {
        guard case let .success(.renderLive(url)) = LaunchOptions.mode(from: [executable] + arguments, currentDirectory: cwd) else {
            return nil
        }
        return url.path
    }

    @Test func noArgumentsRunsTheMenuBarApp() {
        #expect(LaunchOptions.mode(from: [executable], currentDirectory: cwd) == .success(.menuBar))
    }

    /// Launch Services and Xcode add their own arguments; they are not ours to reject.
    @Test func unrelatedArgumentsAreIgnored() {
        let arguments = [executable, "-NSDocumentRevisionsDebugMode", "YES", "-psn_0_12345"]
        #expect(LaunchOptions.mode(from: arguments, currentDirectory: cwd) == .success(.menuBar))
    }

    @Test func renderLiveTakesTheNextArgumentAsTheDirectory() {
        #expect(directory(["--render-live", "/tmp/headroom-live"]) == "/tmp/headroom-live")
    }

    @Test func renderLiveAcceptsTheEqualsForm() {
        #expect(directory(["--render-live=/tmp/headroom-live"]) == "/tmp/headroom-live")
    }

    @Test func aRelativeDirectoryIsResolvedAgainstTheWorkingDirectory() {
        #expect(directory(["--render-live", "renders/live"]) == "/tmp/work/renders/live")
    }

    @Test func renderLiveWithoutADirectoryIsAnError() {
        #expect(LaunchOptions.mode(from: [executable, "--render-live"], currentDirectory: cwd) == .failure(.missingDirectory))
        #expect(LaunchOptions.mode(from: [executable, "--render-live="], currentDirectory: cwd) == .failure(.missingDirectory))
        #expect(LaunchOptions.mode(from: [executable, "--render-live", "--verbose"], currentDirectory: cwd) == .failure(.missingDirectory))
    }

    @Test func theExecutablePathIsNeverTheFlag() {
        #expect(LaunchOptions.mode(from: ["--render-live"], currentDirectory: cwd) == .success(.menuBar))
    }
}
