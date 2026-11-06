import Foundation
import Testing
@testable import HeadroomModel

@Suite struct WindowKindTests {
    @Test(arguments: [
        (239, WindowKind.minutes(239)), (240, .fiveHour), (300, .fiveHour), (360, .fiveHour), (361, .minutes(361)),
        (1199, .minutes(1199)), (1200, .daily), (1440, .daily), (1680, .daily), (1681, .minutes(1681)),
        (8999, .minutes(8999)), (9000, .weekly), (10080, .weekly), (11000, .weekly), (11001, .minutes(11001)),
        (39999, .minutes(39999)), (40000, .monthly), (43200, .monthly), (46000, .monthly), (46001, .minutes(46001)),
        (1, .minutes(1)),
    ])
    func mapsMinutesToKinds(minutes: Int, kind: WindowKind) {
        #expect(WindowKind(windowMinutes: minutes) == kind)
    }

    /// Malformed lengths are no window at all, never a "0-minute" ring (1.1 §0.1 invariant 6).
    @Test(arguments: [0, -1, -60, Int.min])
    func rejectsLengthsUpToZero(minutes: Int) {
        #expect(WindowKind(windowMinutes: minutes) == nil)
    }

    @Test func titles() {
        #expect(WindowKind.fiveHour.title == "5-hour")
        #expect(WindowKind.daily.title == "Daily")
        #expect(WindowKind.weekly.title == "Weekly")
        #expect(WindowKind.monthly.title == "Monthly")
        #expect(WindowKind.minutes(180).title == "3-hour")
        #expect(WindowKind.minutes(2880).title == "2-day")
        #expect(WindowKind.minutes(90).title == "90-minute")
    }

    @Test func lengths() {
        #expect([WindowKind.fiveHour, .daily, .weekly, .monthly, .minutes(180)].map(\.lengthMinutes)
            == [300, 1440, 10080, 43200, 180])
    }

    @Test func codableRoundTripsEveryKind() throws {
        let kinds: [WindowKind] = [.fiveHour, .daily, .weekly, .monthly, .minutes(180), .minutes(300)]
        let decoded = try JSONDecoder().decode([WindowKind].self, from: JSONEncoder().encode(kinds))
        #expect(decoded == kinds)
    }

    /// The shared widget file's format (1.1 §5.3).
    @Test func encodesInTheSharedFileFormat() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(WindowKind.weekly), as: UTF8.self) == #"{"weekly":{}}"#)
        #expect(String(decoding: try encoder.encode(WindowKind.minutes(180)), as: UTF8.self) == #"{"minutes":{"_0":180}}"#)
    }
}
