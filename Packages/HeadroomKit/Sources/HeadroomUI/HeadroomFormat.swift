import Foundation
import HeadroomModel

/// Every user-visible number and time string (spec §1.2). Calendar, time zone and locale are
/// injectable so tests and renders are deterministic.
public struct HeadroomFormat: Sendable {
    public let calendar: Calendar

    public init(
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) {
        var calendar = calendar
        calendar.timeZone = timeZone
        calendar.locale = locale
        self.calendar = calendar
    }

    public var timeZone: TimeZone { calendar.timeZone }
    public var locale: Locale { calendar.locale ?? .autoupdatingCurrent }

    // MARK: Resets

    /// Shown when a limit has usage but no known reset time (spec §3.2).
    public static let unknownReset = "reset unknown"

    /// "resets Sun 7 PM", "resets ~Sun 7 PM" when estimated, "reset unknown" without a date.
    public func weeklyReset(at date: Date?, estimated: Bool) -> String {
        guard let date else { return Self.unknownReset }
        return "resets \(estimated ? "~" : "")\(dayAndTime(date))"
    }

    /// "resets in 2h 50m", "resets ~in 2h 50m" when estimated, "not started" when there is no
    /// active window (no date, or the date has passed; spec §3.1).
    public func fiveHourReset(at date: Date?, estimated: Bool, now: Date) -> String {
        guard let date, date > now else { return "not started" }
        return "resets \(estimated ? "~" : "")in \(countdown(date.timeIntervalSince(now)))"
    }

    /// Abbreviated weekday and time: "Sun 7 PM", "Sun 7:30 PM", or "Sun 19:00" in 24-hour locales.
    public func dayAndTime(_ date: Date) -> String {
        dayAndTime(date, weekday: .abbreviated)
    }

    func dayAndTime(_ date: Date, weekday: Date.FormatStyle.Symbol.Weekday) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
            .weekday(weekday)
            .hour(.defaultDigits(amPM: .abbreviated))
        if calendar.component(.minute, from: date) != 0 || !usesTwelveHourClock {
            style = style.minute(.twoDigits)
        }
        // Newer ICU puts a narrow no-break space before "PM"; keep plain spaces so the text is
        // the same on every macOS version.
        return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "2h 50m", "3h", "45m". Partial minutes round up so the countdown never reads "0m".
    public func countdown(_ interval: TimeInterval) -> String {
        let minutes = Int((Self.clampedSeconds(interval) / 60).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: Tool limits (1.1)

    /// A Codex or Copilot limit's reset (1.1 §6.3): "resets Wed 9 AM" for a week or a day, "resets in 1h 10m" for
    /// shorter windows, "resets Oct 1" for a month; "~" before an estimated time. "reset since last reading" once
    /// the window reset with no new reading (`ToolLimit.resetSinceReading`). Without a reset still ahead, as for
    /// Claude: "not started" for an unused 5-hour window, else "reset unknown".
    public func reset(of limit: ToolLimit, now: Date) -> String {
        if limit.resetSinceReading { return Self.resetSinceReading }
        guard let date = limit.resetsAt, date > now else { return Self.noResetAhead(limit) }
        let mark = limit.resetIsEstimated ? "~" : ""
        switch limit.window {
        case .monthly: return "resets \(mark)\(monthAndDay(date))"
        case let window where window.lengthMinutes < 1440: return "resets \(mark)in \(countdown(date.timeIntervalSince(now)))"
        default: return "resets \(mark)\(dayAndTime(date))"
        }
    }

    /// `reset(of:now:)` for VoiceOver: "resets Wednesday 9 AM", "resets in about 1 hour 10 minutes",
    /// "resets October 1".
    func spokenReset(of limit: ToolLimit, now: Date) -> String {
        if limit.resetSinceReading { return Self.resetSinceReading }
        guard let date = limit.resetsAt, date > now else { return Self.noResetAhead(limit) }
        let about = limit.resetIsEstimated ? "about " : ""
        switch limit.window {
        case .monthly: return "resets \(about)\(monthAndDay(date, month: .wide))"
        case let window where window.lengthMinutes < 1440:
            return "resets in \(about)\(spokenCountdown(date.timeIntervalSince(now)))"
        default: return "resets \(about)\(dayAndTime(date, weekday: .wide))"
        }
    }

    static let resetSinceReading = "reset since last reading"

    private static func noResetAhead(_ limit: ToolLimit) -> String {
        let unused = (limit.usedPercent.flatMap(roundedPercent) ?? 0) == 0
        return limit.window == .fiveHour && unused ? "not started" : unknownReset
    }

    /// "Oct 1": a monthly reset's day (Copilot's is 00:00 UTC on the 1st, shown in local time).
    public func monthAndDay(_ date: Date) -> String {
        monthAndDay(date, month: .abbreviated)
    }

    private func monthAndDay(_ date: Date, month: Date.FormatStyle.Symbol.Month) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
                .month(month)
                .day(.defaultDigits)
        )
    }

    /// "Sep 30, 2026 at 9:00 AM": an exact time, for hover text.
    public func exactDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    /// "512", "1,500": a whole amount with the locale's grouping (Copilot credits and requests).
    public func amount(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let whole = Int(min(max(value, -1e12), 1e12).rounded())
        return whole.formatted(IntegerFormatStyle<Int>(locale: locale))
    }

    // MARK: Age

    /// "just now", "2m ago", "3h ago", "2d ago". Dates in the future read "just now".
    public func age(of date: Date, now: Date) -> String {
        let seconds = Int(Self.clampedSeconds(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }

    // MARK: Tokens

    /// "724k of 1M tokens".
    public func tokens(used: Int, window: Int) -> String {
        "\(tokenCount(used)) of \(tokenCount(window)) tokens"
    }

    /// "168k tokens": a count without a window, for a window size that is only a guess.
    public func tokens(used: Int) -> String {
        "\(tokenCount(used)) tokens"
    }

    /// "850", "52k", "1M", "1.5M".
    public func tokenCount(_ count: Int) -> String {
        guard count > 0 else { return "0" }
        if count < 1000 { return "\(count)" }
        let thousands = Int((Double(count) / 1000).rounded())
        if thousands < 1000 { return "\(thousands)k" }
        let tenthsOfMillions = Int((Double(count) / 100_000).rounded())
        let whole = tenthsOfMillions / 10
        let tenth = tenthsOfMillions % 10
        return tenth == 0 ? "\(whole)M" : "\(whole).\(tenth)M"
    }

    // MARK: Percent

    /// "89%"; values are clamped to 0...100 and rounded. Non-finite input reads "–".
    public func percent(_ value: Double) -> String {
        Self.roundedPercent(value).map { "\($0)%" } ?? "–"
    }

    /// The integer percent the UI shows, or nil for non-finite input.
    public static func roundedPercent(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(min(100, max(0, value)).rounded())
    }

    // MARK: Spoken (VoiceOver)

    /// `weeklyReset` for VoiceOver: "resets Sunday 7 PM", "resets about Sunday 7 PM" when estimated.
    func spokenWeeklyReset(at date: Date?, estimated: Bool) -> String {
        guard let date else { return Self.unknownReset }
        return "resets \(estimated ? "about " : "")\(dayAndTime(date, weekday: .wide))"
    }

    /// `fiveHourReset` for VoiceOver: "resets in 2 hours 50 minutes", "resets in about 45 minutes"
    /// when estimated, "not started".
    func spokenFiveHourReset(at date: Date?, estimated: Bool, now: Date) -> String {
        guard let date, date > now else { return "not started" }
        return "resets in \(estimated ? "about " : "")\(spokenCountdown(date.timeIntervalSince(now)))"
    }

    /// `countdown` in words: "2 hours 50 minutes", "3 hours", "1 minute".
    func spokenCountdown(_ interval: TimeInterval) -> String {
        let minutes = Int((Self.clampedSeconds(interval) / 60).rounded(.up))
        let parts = [(minutes / 60, "hour"), (minutes % 60, "minute")]
            .filter { $0.0 > 0 }
            .map { Self.count($0.0, $0.1) }
        return parts.isEmpty ? Self.count(0, "minute") : parts.joined(separator: " ")
    }

    /// `age` in words: "just now", "42 minutes ago", "1 hour ago", "2 days ago".
    func spokenAge(of date: Date, now: Date) -> String {
        let seconds = Int(Self.clampedSeconds(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Self.count(seconds / 60, "minute")) ago"
        case ..<86_400: return "\(Self.count(seconds / 3600, "hour")) ago"
        default: return "\(Self.count(seconds / 86_400, "day")) ago"
        }
    }

    // MARK: Helpers

    /// "1 hour", "2 hours".
    private static func count(_ value: Int, _ unit: String) -> String {
        "\(value) \(unit)\(value == 1 ? "" : "s")"
    }

    private var usesTwelveHourClock: Bool {
        switch locale.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        case .zeroToTwentyThree, .oneToTwentyFour: false
        @unknown default: false
        }
    }

    /// Keeps interval arithmetic far away from `Int` overflow (about 31 years is plenty).
    private static func clampedSeconds(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return 0 }
        return min(max(interval, 0), 1e9)
    }
}
