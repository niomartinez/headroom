import Darwin
import Foundation

/// Whether a Claude session has an agent still at work (1.1 §14.11). Claude Code writes each agent's transcript to
/// `<session transcript without .jsonl>/subagents/agent-<id>.jsonl`, one line per content block, and an agent is done
/// once its newest message is a reply that ended the turn. An agent stopped or interrupted mid-turn is never written
/// again, so one that isn't done counts only while its transcript was written in the last `staleAfter`.
public struct SubagentActivity: Sendable {
    public static let defaultStaleAfter: TimeInterval = 10 * 60

    public var staleAfter: TimeInterval
    let tail = JSONLTailReader()

    public init(staleAfter: TimeInterval = Self.defaultStaleAfter) {
        self.staleAfter = staleAfter
    }

    /// Lists the session's `subagents` folder and reads the end of each transcript written in the last `staleAfter`.
    public func hasRunningAgent(transcript: URL, now: Date) -> Bool {
        let folder = transcript.deletingPathExtension().appendingPathComponent("subagents", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return false }
        return files.contains { file in
            guard file.lastPathComponent.hasPrefix("agent-"), file.pathExtension == "jsonl",
                  let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modified) < staleAfter
            else { return false }
            return !isDone(path: file.path)
        }
    }

    /// Stop reasons that end an agent's turn. Blocks still streaming have none, a tool call has `tool_use`.
    static let finalStopReasons: Set<String> = ["end_turn", "stop_sequence", "max_tokens", "refusal"]

    /// The newest `user` or `assistant` line is an assistant line with a final stop reason. A last line still being
    /// written, or a file that can't be read, counts as not done.
    func isDone(path: String) -> Bool {
        // O_NONBLOCK: a path swapped for a FIFO must not wait for a writer.
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        guard let status = FileStatus.of(descriptor: descriptor), status.isRegularFile else { return false }
        var done = false
        _ = tail.scan(descriptor: descriptor, size: status.signature.size) { line in
            guard line.isTerminated else { return .stop }
            guard let object = try? JSONSerialization.jsonObject(with: line.data) as? [String: Any] else { return .next }
            switch object["type"] as? String {
            case "assistant":
                let stopReason = (object["message"] as? [String: Any])?["stop_reason"] as? String
                done = stopReason.map(Self.finalStopReasons.contains) ?? false
                return .stop
            case "user":
                return .stop
            default:
                return .next
            }
        }
        return done
    }
}
