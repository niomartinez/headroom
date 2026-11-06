import Foundation
import HeadroomModel
import Testing

@Suite struct AccessProbeTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomAccessProbeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func anExistingDirectoryIsReadable() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClaudePaths.standard(home: root)
        try FileManager.default.createDirectory(at: paths.claudeDirectory, withIntermediateDirectories: true)
        #expect(AccessProbe.isReadableDirectory(paths.claudeDirectory))
    }

    @Test func aMissingDirectoryIsNotReadable() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(!AccessProbe.isReadableDirectory(ClaudePaths.standard(home: root).desktopSupportDirectory))
    }

    @Test func aFileIsNotAReadableDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("not-a-folder")
        try Data("x".utf8).write(to: file)
        #expect(!AccessProbe.isReadableDirectory(file))
    }

    @Test func aDirectoryWithoutPermissionIsNotReadable() throws {
        let root = try makeTempDirectory()
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        #expect(!AccessProbe.isReadableDirectory(locked))
    }

    @Test func aSymlinkToADirectoryIsReadable() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target", isDirectory: true)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(AccessProbe.isReadableDirectory(link))
    }
}
