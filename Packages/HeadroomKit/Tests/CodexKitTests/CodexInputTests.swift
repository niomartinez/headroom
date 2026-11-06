import Foundation
import HeadroomModel
import Testing
@testable import CodexKit

@Suite("Codex input requests")
struct CodexInputTests {
    private func item(_ payload: [String: Any], at: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["timestamp": at, "type": "response_item", "payload": payload])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private func request(_ id: String = "question", async: Bool = true, at: String = "2026-09-23T13:32:00Z") throws -> String {
        try item([
            "type": "function_call", "name": async ? "request_user_input_async" : "functions.request_user_input",
            "call_id": id, "arguments": "Synthetic question arguments are not decoded",
        ], at: at)
    }

    private func output(_ id: String = "question", accepted: Bool = true, at: String = "2026-09-23T13:32:01Z") throws -> String {
        try item([
            "type": "function_call_output", "call_id": id,
            "output": accepted ? #"{"accepted":true}"# : #"{"accepted":false}"#,
        ], at: at)
    }

    private func user(_ kind: String = "user.text", at: String = "2026-09-23T13:34:00Z") throws -> String {
        try item([
            "type": "message", "role": "user", "content": ["intentionally": "not a message array"],
            "internal_chat_message_metadata_passthrough": ["content_item_kinds": [kind]],
        ], at: at)
    }

    @Test func asyncRequestStaysWaitingThroughAcknowledgementBackgroundWorkAndTurnCompletion() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        try home.append(request(), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .waitingForInput)
        try home.append(output() + output("unrelated") + RolloutText.complete(at: "2026-09-23T13:33:00Z", turn: "t1"), to: file)
        let pending = reader.read(now: testNow).sessions.first
        #expect(pending?.activity == .waitingForInput)
        #expect(pending?.activitySince == date("2026-09-23T13:32:00Z"))
        // Restarting Headroom must find the same pending question.
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .waitingForInput)
        try home.append(user("environments.environment_context"), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .waitingForInput)
        try home.append(user(), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .idle)
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .idle)
    }

    @Test func syncRequestResolvesOnlyOnItsMatchingOutput() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        try home.append(request(async: false) + output("other"), to: file)
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .waitingForInput)
        try home.append(output(), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .working)
    }

    @Test func answeringAsyncQuestionDuringAnOpenTurnResumesOnTheNextRead() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        let reader = home.reader()
        try home.append(request() + output(), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .waitingForInput)
        // The desktop answer arrives as a user.text message while the same turn is still running.
        try home.append(user(), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .working)
    }

    @Test func rejectedAsyncRequestAndAbortedTurnDoNotKeepAttention() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        try home.append(request() + output(accepted: false), to: file)
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        try home.append(request("second", at: "2026-09-23T13:35:00Z"), to: file)
        #expect(reader.read(now: testNow).sessions.first?.activity == .waitingForInput)
        try home.append(
            #"{"timestamp":"2026-09-23T13:36:00Z","type":"event_msg","payload":{"type":"turn_aborted"}}"# + "\n",
            to: file
        )
        #expect(reader.read(now: testNow).sessions.first?.activity == .idle)
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .idle)
    }

    @Test func aNewQuestionAfterUserInteractionGetsANewAttentionTime() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        try home.append(request() + output() + user(), to: file)
        let reader = home.reader()
        #expect(reader.read(now: testNow).sessions.first?.activity == .working)
        try home.append(request("second", at: "2026-09-23T13:35:00Z"), to: file)
        let pending = reader.read(now: testNow).sessions.first
        #expect(pending?.activity == .waitingForInput)
        #expect(pending?.activitySince == date("2026-09-23T13:35:00Z"))
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .waitingForInput)
    }

    @Test func toolNamesInsideMessagesDoNotTriggerAttention() throws {
        let home = try CodexHome()
        let file = try home.install("open_turn")
        try home.lock([CodexFixtures.threadID("open_turn")])
        try home.append(RolloutText.message(at: "2026-09-23T13:32:00Z", text: "request_user_input_async"), to: file)
        #expect(home.reader().read(now: testNow).sessions.first?.activity == .working)
    }
}
