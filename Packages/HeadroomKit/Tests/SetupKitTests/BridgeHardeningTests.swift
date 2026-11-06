import Darwin
import Foundation
import Testing
@testable import SetupKit

/// Files that aren't regular files must never block the installer: reading a FIFO waits until
/// some other process writes to it, and `state()` runs on every refresh.
@Suite("BridgeInstaller: special files")
struct SpecialFileTests {
    @Test func aFIFOInPlaceOfTheScriptDoesNotBlockTheState() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        try installer.install()
        try FileManager.default.removeItem(at: sandbox.script)
        try makeFIFO(at: sandbox.script)

        let state = finishes(within: 2, unblocking: [sandbox.script]) { installer.state() }

        #expect(state == .outdated)
        // Connect (Update) replaces it with the script.
        try installer.install()
        #expect(installer.state() == .installed)
    }

    @Test func aFIFOInPlaceOfTheSettingsFileIsUnreadable() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        try makeFIFO(at: sandbox.settings)

        let state = finishes(within: 2, unblocking: [sandbox.settings]) { installer.state() }
        let installError = finishes(within: 2, unblocking: [sandbox.settings]) { thrownError { try installer.install() } }
        let uninstallError = finishes(within: 2, unblocking: [sandbox.settings]) { thrownError { try installer.uninstall() } }

        guard case .settingsUnreadable(let reason)? = state else {
            Issue.record("expected settingsUnreadable, got \(String(describing: state))")
            return
        }
        #expect(reason.contains("not a regular file"))
        #expect(installError == .some(.some(.settingsUnreadable(reason))))
        #expect(uninstallError == .some(.some(.settingsUnreadable(reason))))
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
    }

    @Test(arguments: ["backup", "saved status line"])
    func aFIFOInPlaceOfASavedFileDoesNotBlockConnectOrDisconnect(file: String) throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        var original = try #require(try parseJSON(try fixtureText("settings-user.json")) as? [String: Any])
        original["statusLine"] = ["type": "command", "command": "echo mine"]
        try sandbox.writeSettings(try jsonText(original, pretty: true))
        try installer.install()
        let fifo = file == "backup" ? sandbox.backup : sandbox.originalStatusLine
        try FileManager.default.removeItem(at: fifo)
        try makeFIFO(at: fifo)

        let reinstallError = finishes(within: 2, unblocking: [fifo]) { thrownError { try installer.install() } }
        let uninstallError = finishes(within: 2, unblocking: [fifo]) { thrownError { try installer.uninstall() } }

        #expect(reinstallError == .some(nil))
        #expect(uninstallError == .some(nil))
        #expect(installer.state() == .notInstalled)
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
    }
}

/// "Disconnect terminal" while sessions are still calling the bridge (spec §2.6: it deletes
/// ~/.claude/headroom/).
@Suite("BridgeInstaller: disconnecting while the bridge runs")
struct DisconnectRaceTests {
    @Test func uninstallDeletesTheFolderWhileWritersAreBusy() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        var failures: [String] = []
        for round in 0..<20 {
            try installer.install()
            try sandbox.write("{}", to: sandbox.sessions.appendingPathComponent("s\(round).hook.json"))
            let writers = PathWriters(directories: [sandbox.bridgeDirectory, sandbox.sessions], threads: 2)
            usleep(2_000)
            let error = thrownError { try installer.uninstall() }
            writers.stop()

            if let error { failures.append("round \(round): \(error)") }
            #expect(!sandbox.exists(sandbox.bridgeDirectory), "round \(round)")
        }
        #expect(failures.isEmpty, "\(failures)")
        #expect(sandbox.entries(in: sandbox.claude, prefix: ".headroom").isEmpty)
        #expect(installer.state() == .notInstalled)
    }

    /// The same with the real bridge, run through the installed status line command back to back
    /// (a session streaming a reply refreshes it every few hundred milliseconds). One runner keeps
    /// the load low enough for the timing tests that run alongside.
    @Test func uninstallDeletesTheFolderWhileStatusLinesRun() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        let payload = try fixtureText("statusline-payload.json")
        var failures: [String] = []
        for round in 0..<6 {
            try installer.install()
            let runners = StatusLineRunners(sandbox: sandbox, payload: payload, threads: 1)
            usleep(100_000)
            let error = thrownError { try installer.uninstall() }
            runners.stop()

            if let error { failures.append("round \(round): \(error)") }
            #expect(!installer.hasLeftoverFiles(), "round \(round)")
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// A Disconnect that couldn't delete everything leaves settings.json clean, so `state()` says
    /// not installed; the leftovers are still reported, and Disconnect deletes them.
    @Test func leftoversAreReportedAndDeletedByUninstall() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings(#"{"model":"opus"}"#)
        try sandbox.write("{}", to: sandbox.sessions.appendingPathComponent("s1.hook.json"))
        try sandbox.write("{}", to: sandbox.statusLineLatest)
        let interrupted = sandbox.claude.appendingPathComponent(".headroom-removing-0B5E7F4C")
        try sandbox.write("{}", to: interrupted.appendingPathComponent("sessions/s2.hook.json"))
        let installer = sandbox.installer
        #expect(installer.state() == .notInstalled)
        #expect(installer.hasLeftoverFiles())

        try installer.uninstall()

        #expect(!installer.hasLeftoverFiles())
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
        #expect(!sandbox.exists(interrupted))
        #expect(try Data(contentsOf: sandbox.settings) == Data(#"{"model":"opus"}"#.utf8))
    }

    @Test func noLeftoversWithoutTheFolder() throws {
        let sandbox = try Sandbox()
        #expect(!sandbox.installer.hasLeftoverFiles())
        try sandbox.installer.install()
        #expect(sandbox.installer.hasLeftoverFiles())
        try sandbox.installer.uninstall()
        #expect(!sandbox.installer.hasLeftoverFiles())
    }

    /// A real failure is reported as what it is, the settings are restored anyway, and the files
    /// can be deleted by a later Disconnect.
    @Test func aFailedDeletionIsReportedAccurately() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        try installer.install()
        try sandbox.write("{}", to: sandbox.sessions.appendingPathComponent("s1.hook.json"))
        chmod(sandbox.sessions.path, 0o500)
        defer {
            for name in sandbox.entries(in: sandbox.claude, prefix: ".headroom-removing-") {
                chmod(sandbox.claude.appendingPathComponent(name).appendingPathComponent("sessions").path, 0o700)
            }
            chmod(sandbox.sessions.path, 0o700)
        }

        let error = thrownError { try installer.uninstall() }

        guard case .writeFailed(let reason)? = error else {
            Issue.record("expected writeFailed, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("~/.claude/headroom"))
        #expect(reason.contains(String(cString: strerror(EACCES))))
        #expect(!sandbox.exists(sandbox.settings))
        #expect(installer.state() == .notInstalled)
        #expect(installer.hasLeftoverFiles())
        // Nothing reads the leftovers where they are now.
        #expect(!sandbox.exists(sandbox.bridgeDirectory))

        for name in sandbox.entries(in: sandbox.claude, prefix: ".headroom-removing-") {
            chmod(sandbox.claude.appendingPathComponent(name).appendingPathComponent("sessions").path, 0o700)
        }
        try installer.uninstall()
        #expect(!installer.hasLeftoverFiles())
    }

    /// A writer that keeps adding files through an open directory handle defeats the rename. If
    /// deleting then fails, the message says why instead of blaming permissions.
    @Test func aWriterThatNeverStopsIsNamedAsTheCause() throws {
        let sandbox = try Sandbox()
        let installer = sandbox.installer
        try installer.install()
        try FileManager.default.createDirectory(at: sandbox.sessions, withIntermediateDirectories: true)
        let directory = open(sandbox.sessions.path, O_RDONLY | O_DIRECTORY)
        try #require(directory >= 0)
        let writer = DirectoryWriter(directory: directory)

        let error = thrownError { try installer.uninstall() }
        writer.stop()
        close(directory)

        if case .writeFailed(let reason)? = error {
            #expect(reason.contains("kept writing"), "\(reason)")
            #expect(!reason.localizedCaseInsensitiveContains("permission"))
        } else {
            #expect(error == nil)
        }
        try installer.uninstall()
        #expect(!installer.hasLeftoverFiles())
    }

    /// A bridge run that started before Disconnect must not bring the folder back afterwards.
    @Test(arguments: ["statusline", "SessionStart", "Stop"])
    func theBridgeNeverCreatesTheHeadroomFolder(mode: String) throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.claude, withIntermediateDirectories: true)
        let script = sandbox.scratch.appendingPathComponent("bridge.sh")
        try sandbox.write(BridgeScript.contents, to: script)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        let payload: String
        if mode == "statusline" {
            process.arguments = [script.path, "statusline"]
            payload = try fixtureText("statusline-payload.json")
        } else {
            process.arguments = [script.path, "hook"]
            payload = try hookPayload(event: mode)
        }

        let result = try run(process, stdin: payload, in: sandbox)

        #expect(result.status == 0)
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
        if mode == "statusline" {
            #expect(result.stdout == "5h 20% · wk 90% · ctx 26%\n")
        }
    }
}

/// Threads that keep running the installed status line command, one run after another.
private final class StatusLineRunners: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let finished = DispatchGroup()

    init(sandbox: Sandbox, payload: String, threads: Int) {
        for _ in 0..<threads {
            finished.enter()
            Thread { [self] in
                while !isStopped {
                    _ = try? runShellCommand(BridgeInstaller.statusLineCommand, stdin: payload, in: sandbox)
                }
                finished.leave()
            }.start()
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        finished.wait()
    }
}

/// Creates files through a directory descriptor, so it follows the directory wherever it is renamed.
private final class DirectoryWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private let finished = DispatchGroup()

    init(directory: Int32) {
        finished.enter()
        Thread { [self] in
            var n = 0
            while !isStopped {
                n += 1
                let fd = openat(directory, "busy-\(n % 64).json", O_WRONLY | O_CREAT, 0o600)
                if fd >= 0 { close(fd) }
            }
            finished.leave()
        }.start()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        finished.wait()
    }
}

/// The sandboxed build may open only the folder the user granted (~/.claude). A settings.json that
/// links elsewhere (dotfiles) then fails with EPERM. Unsandboxed tests get the same failure class
/// (EACCES) from permission bits.
@Suite("BridgeInstaller: settings.json linked outside ~/.claude")
struct LinkedSettingsTests {
    enum Denial: String, CaseIterable {
        /// stat works, open fails (what the App Sandbox does).
        case file
        /// stat fails too (a stricter sandbox profile).
        case folder
    }

    @Test(arguments: Denial.allCases)
    func aLinkTargetHeadroomCantOpenIsNamedAndNothingChanges(denial: Denial) throws {
        let sandbox = try Sandbox()
        let target = sandbox.home.appendingPathComponent("dotfiles/claude/settings.json")
        let text = try fixtureText("settings-user.json")
        try sandbox.write(text, to: target)
        try FileManager.default.createDirectory(at: sandbox.claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sandbox.settings, withDestinationURL: target)
        let denied = denial == .file ? target : target.deletingLastPathComponent()
        chmod(denied.path, 0)
        defer { chmod(denied.path, denial == .file ? 0o644 : 0o755) }
        let installer = sandbox.installer

        let state = installer.state()
        let installError = thrownError { try installer.install() }
        let uninstallError = thrownError { try installer.uninstall() }

        guard case .settingsUnreadable(let reason) = state else {
            Issue.record("expected settingsUnreadable, got \(state)")
            return
        }
        #expect(reason.contains("dotfiles/claude/settings.json"))
        #expect(reason.contains("outside the folders Headroom can access"))
        for error in [installError, uninstallError] {
            guard case .settingsOutsideGrant(let linked)? = error else {
                Issue.record("expected settingsOutsideGrant, got \(String(describing: error))")
                continue
            }
            #expect(linked.hasSuffix("/dotfiles/claude/settings.json"))
            let description = error?.localizedDescription ?? ""
            #expect(description.contains(linked))
            #expect(description.contains("Nothing was changed"))
            #expect(!description.localizedCaseInsensitiveContains("remove"))
        }
        chmod(denied.path, denial == .file ? 0o644 : 0o755)
        #expect(try Data(contentsOf: target) == Data(text.utf8))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: sandbox.settings.path) == target.path)
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
        #expect(!sandbox.exists(sandbox.backup))
    }

    @Test func aDanglingLinkIsStillAMissingFile() throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.claude, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: sandbox.settings, withDestinationURL: sandbox.home.appendingPathComponent("dotfiles/missing.json")
        )

        #expect(sandbox.installer.state() == .settingsUnreadable("settings.json links to a missing file"))
        #expect(thrownError { try sandbox.installer.install() } == .settingsUnreadable("settings.json links to a missing file"))
    }

    /// Inside ~/.claude a permission problem is the file's own: say so plainly.
    @Test func anUnreadableFileInsideClaudeIsUnreadable() throws {
        let sandbox = try Sandbox()
        try sandbox.writeSettings("{}")
        chmod(sandbox.settings.path, 0)
        defer { chmod(sandbox.settings.path, 0o644) }

        let state = sandbox.installer.state()

        #expect(state == .settingsUnreadable("settings.json can't be read: \(String(cString: strerror(EACCES)))"))
        guard case .settingsUnreadable? = thrownError({ try sandbox.installer.install() }) else {
            Issue.record("expected settingsUnreadable")
            return
        }
    }
}

/// The installed commands (spec §2.6), run the way Claude Code runs them.
@Suite("BridgeInstaller: installed commands")
struct InstalledCommandTests {
    /// settings.json can reach a machine without the script (dotfiles, or ~/.claude/headroom deleted):
    /// every session would then report hook errors at start and exit.
    @Test func commandsDoNothingWithoutTheScript() throws {
        let sandbox = try Sandbox()
        try FileManager.default.createDirectory(at: sandbox.claude, withIntermediateDirectories: true)
        let commands = [
            (BridgeInstaller.statusLineCommand, try fixtureText("statusline-payload.json")),
            (BridgeInstaller.hookCommand, try hookPayload(event: "SessionStart")),
            (BridgeInstaller.hookCommand, try hookPayload(event: "SessionEnd")),
        ]
        for (command, payload) in commands {
            let (result, stderr) = try runShellCommand(command, stdin: payload, in: sandbox)
            #expect(result.status == 0, "\(command)")
            #expect(result.stdout == "")
            #expect(stderr == "")
        }
        #expect(!sandbox.exists(sandbox.bridgeDirectory))
    }

    @Test func commandsRunTheScriptOnceInstalled() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()

        let statusLine = try runShellCommand(BridgeInstaller.statusLineCommand, stdin: try fixtureText("statusline-payload.json"), in: sandbox)
        let hook = try runShellCommand(BridgeInstaller.hookCommand, stdin: try hookPayload(event: "Stop"), in: sandbox)

        #expect(statusLine.run.stdout == "5h 20% · wk 90% · ctx 26%\n")
        #expect(statusLine.run.status == 0)
        #expect(hook.run.status == 0)
        #expect(try hookRecord("0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6", in: sandbox)["event"] as? String == "Stop")
    }

    /// The shell hands over to the bridge, so its parent is still Claude Code: without a `claude`
    /// ancestor the bridge records `$PPID`, which must not be a shell that exits right away.
    @Test func theShellHandsOverToTheBridge() throws {
        let sandbox = try Sandbox()
        try sandbox.installer.install()
        // Seven bash levels keep any real `claude` ancestor of the test runner out of reach.
        let nest = sandbox.scratch.appendingPathComponent("nest.sh")
        try sandbox.write(
            """
            if [ "$1" -gt 0 ]; then
                /bin/bash "$0" $(($1 - 1))
            else
                echo $$ > "$LEVEL0"
                /bin/sh -c "$COMMAND" < "$PAYLOAD"
            fi
            exit 0
            """,
            to: nest
        )
        let level0 = sandbox.scratch.appendingPathComponent("level0")
        let payload = sandbox.scratch.appendingPathComponent("payload.json")
        try Data(try hookPayload(event: "Stop").utf8).write(to: payload)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [nest.path, "6"]

        let result = try run(process, stdin: nil, in: sandbox, environment: [
            "LEVEL0": level0.path, "COMMAND": BridgeInstaller.hookCommand, "PAYLOAD": payload.path,
        ])

        #expect(result.status == 0)
        let parent = Int(try String(contentsOf: level0, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let recorded = try hookRecord("0f5c2a7e-1b3d-4c5e-8f90-a1b2c3d4e5f6", in: sandbox)["pid"] as? Int
        #expect(recorded != nil)
        #expect(recorded == parent)
    }
}
