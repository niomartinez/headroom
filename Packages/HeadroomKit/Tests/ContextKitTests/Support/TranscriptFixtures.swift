import Foundation

/// Synthetic transcript lines shaped like Claude Code's `projects/*/<id>.jsonl` entries (spec §2.3).
/// Every line returned ends with "\n".
enum Fixture {
    static let timestamp = "2026-01-02T03:04:05.678Z"
    /// `timestamp` as a Date (2026-01-02 03:04:05.678 UTC).
    static let timestampDate = Date(timeIntervalSince1970: 1_767_323_045.678)

    static func assistant(
        model: String? = "claude-test-model",
        input: Int = 10,
        cacheCreation: Int = 200,
        cacheRead: Int = 3_000,
        output: Int = 40,
        timestamp: String? = Fixture.timestamp,
        sidechain: Bool? = false,
        text: String = "synthetic reply"
    ) -> String {
        let usage = #"{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"#
            + #""cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"service_tier":"standard"}"#
        return assistant(usageJSON: usage, model: model, timestamp: timestamp, sidechain: sidechain, text: text)
    }

    /// An assistant line with a raw `usage` value (or none when `usageJSON` is nil).
    static func assistant(
        usageJSON: String?,
        model: String? = "claude-test-model",
        timestamp: String? = Fixture.timestamp,
        sidechain: Bool? = false,
        text: String = "synthetic reply"
    ) -> String {
        var message = #"{"id":"msg_synthetic","type":"message","role":"assistant","#
        if let model { message += #""model":"\#(model)","# }
        message += #""content":[{"type":"text","text":"\#(text)"}]"#
        if let usageJSON { message += #","usage":\#(usageJSON)"# }
        message += "}"
        var line = #"{"parentUuid":"00000000-0000-4000-8000-000000000001","#
        if let sidechain { line += #""isSidechain":\#(sidechain),"# }
        line += #""type":"assistant","uuid":"00000000-0000-4000-8000-000000000002","#
        if let timestamp { line += #""timestamp":"\#(timestamp)","# }
        line += #""message":\#(message)}"#
        return line + "\n"
    }

    static func user(text: String = "synthetic prompt") -> String {
        #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"\#(text)"},"timestamp":"\#(timestamp)"}"#
            + "\n"
    }

    private static let fillerPrefix = #"{"type":"user","isSidechain":false,"message":{"role":"user","content":""#
    private static let fillerSuffix = #""}}"# + "\n"
    static var fillerOverhead: Int { fillerPrefix.utf8.count + fillerSuffix.utf8.count }

    /// Complete non-assistant lines totalling exactly `bytes` bytes (`bytes` must be ≥ `fillerOverhead`).
    static func filler(bytes: Int, lineLength: Int = 1_024) -> String {
        var out = ""
        out.reserveCapacity(bytes)
        var remaining = bytes
        while remaining > 0 {
            var length = min(lineLength, remaining)
            if remaining - length < fillerOverhead { length = remaining }
            out += fillerPrefix + String(repeating: "x", count: max(0, length - fillerOverhead)) + fillerSuffix
            remaining -= length
        }
        return out
    }

    /// Writes `megabytes` MB of filler to `handle` in 1 MB blocks (for large-file tests).
    static func writeLargeFiller(megabytes: Int, to handle: FileHandle) throws {
        let block = Data(filler(bytes: 1_048_576, lineLength: 2_048).utf8)
        for _ in 0..<megabytes {
            try handle.write(contentsOf: block)
        }
    }
}
