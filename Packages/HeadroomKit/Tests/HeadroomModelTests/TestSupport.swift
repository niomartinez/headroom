import Foundation

/// Parses `2026-09-20T10:52:00Z`-style UTC timestamps. A typo yields `.distantPast`, which fails the assertion.
func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text) ?? .distantPast
}

let minute: TimeInterval = 60
let hour: TimeInterval = 3600
