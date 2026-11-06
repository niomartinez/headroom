import Foundation
import Testing

@Suite struct FolderGrantTests {
    @Test func theExpectedFolderMatches() {
        let expected = URL(fileURLWithPath: "/Users/example/.claude", isDirectory: true)
        #expect(FolderGrant.isExpected(URL(fileURLWithPath: "/Users/example/.claude"), expected: expected))
    }

    @Test func trailingSlashesAndDotSegmentsAreIgnored() {
        let expected = URL(fileURLWithPath: "/Users/example/.claude")
        #expect(FolderGrant.isExpected(URL(fileURLWithPath: "/Users/example/./.claude/"), expected: expected))
    }

    @Test func anotherFolderDoesNotMatch() {
        let expected = URL(fileURLWithPath: "/Users/example/.claude")
        #expect(!FolderGrant.isExpected(URL(fileURLWithPath: "/Users/example/Documents"), expected: expected))
    }

    @Test func aParentOrChildFolderDoesNotMatch() {
        let expected = URL(fileURLWithPath: "/Users/example/.claude")
        #expect(!FolderGrant.isExpected(URL(fileURLWithPath: "/Users/example"), expected: expected))
        #expect(!FolderGrant.isExpected(URL(fileURLWithPath: "/Users/example/.claude/sessions"), expected: expected))
    }

    @Test func theTargetOfASymlinkedFolderMatches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadroomFolderGrantTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("dotfiles-claude", isDirectory: true)
        let link = root.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(FolderGrant.isExpected(target, expected: link))
    }
}
