import Foundation
import Testing
@testable import ContextKit

/// 1.1 §14.11: background agents, from their transcripts under `<session>/subagents/`.
@Suite struct SubagentActivityTests {
    static let now = Date(timeIntervalSince1970: 1_790_251_200)
    static let user = #"{"type":"user","message":{"role":"user","content":"Find the parser tests"}}"#

    static func assistant(_ block: String, stopReason: String?) -> String {
        let reason = stopReason.map { #""\#($0)""# } ?? "null"
        return #"{"type":"assistant","message":{"content":[{"type":"\#(block)"}],"stop_reason":\#(reason)}}"#
    }

    /// Writes the session transcript and one agent transcript of `lines`, last written `age` ago, and asks.
    func running(_ lines: [String], age: TimeInterval = 30, name: String = "agent-a1.jsonl") throws -> Bool {
        try withTempDirectory { tmp in
            let transcript = tmp.appendingPathComponent("session-1.jsonl")
            try transcript.write(Self.user + "\n")
            let agent = tmp.appendingPathComponent("session-1/subagents/\(name)")
            try agent.write(lines.joined(separator: "\n") + "\n")
            try FileManager.default.setAttributes([.modificationDate: Self.now - age], ofItemAtPath: agent.path)
            return SubagentActivity().hasRunningAgent(transcript: transcript, now: Self.now)
        }
    }

    @Test func anAgentMidTurnIsRunning() throws {
        #expect(try running([Self.user, Self.assistant("tool_use", stopReason: "tool_use")]))
        #expect(try running([Self.user, Self.assistant("tool_use", stopReason: "tool_use"), Self.user]))
        // Blocks still streaming have no stop reason yet.
        #expect(try running([Self.user, Self.assistant("text", stopReason: nil)]))
    }

    @Test func anAgentThatEndedItsTurnIsDone() throws {
        #expect(try !running([Self.user, Self.assistant("text", stopReason: "end_turn")]))
        #expect(try !running([Self.user, Self.assistant("text", stopReason: "stop_sequence")]))
        // Lines that aren't messages after the reply don't matter.
        #expect(try !running([Self.assistant("text", stopReason: "end_turn"), #"{"type":"attachment"}"#]))
    }

    @Test func anAgentNotWrittenForTenMinutesIsNotRunning() throws {
        let midTurn = [Self.user, Self.assistant("tool_use", stopReason: "tool_use")]
        #expect(try running(midTurn, age: SubagentActivity.defaultStaleAfter - 1))
        #expect(try !running(midTurn, age: SubagentActivity.defaultStaleAfter))
    }

    @Test func onlyAgentTranscriptsCount() throws {
        #expect(try !running([Self.user], name: "agent-a1.meta.json"))
        #expect(try !running([Self.user], name: "notes.jsonl"))
    }

    @Test func aSessionWithoutAgentsHasNone() throws {
        try withTempDirectory { tmp in
            let transcript = tmp.appendingPathComponent("session-1.jsonl")
            try transcript.write(Self.user + "\n")
            #expect(!SubagentActivity().hasRunningAgent(transcript: transcript, now: Self.now))
        }
    }
}
