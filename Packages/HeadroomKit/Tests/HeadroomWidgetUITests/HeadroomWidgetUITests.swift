import HeadroomShare
import Testing
import WidgetKit
@testable import HeadroomWidgetUI

@Suite struct HeadroomWidgetUITests {
    @Test func familiesPerKind() {
        #expect(HeadroomWidgetUI.supportedFamilies(kind: WidgetShare.limitsKind) == [.systemSmall, .systemMedium])
        #expect(HeadroomWidgetUI.supportedFamilies(kind: WidgetShare.sessionsKind) == [.systemMedium, .systemLarge])
        #expect(HeadroomWidgetUI.supportedFamilies(kind: "other").isEmpty)
    }
}
