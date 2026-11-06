import AppKit
import HeadroomModel
import SwiftUI
import Testing
@testable import HeadroomUI

/// Measured layout: what the menu bar and the panel actually get, not just what the models say.
@MainActor @Suite struct LayoutTests {
    let now = Fixture.now

    // MARK: Moment pill width

    /// The status item's length is the hosting view's fitting width (StatusItemController), so
    /// this is the width the menu bar has to find room for. Measured at 1.0's 22 pt height; taller pills scale the
    /// budget with their height (`tallerPillsScaleTheBudget`).
    private func pillWidth(_ moment: Moment?, height: CGFloat = PillMetrics.minimumHeight) -> CGFloat {
        NSHostingView(rootView: PillView(snapshot: Fixture.snapshot(), moment: moment, now: now, height: height))
            .fittingSize.width
    }

    static let pillWidthBudget: CGFloat = 280

    /// 1.1 §14.6: everything in a taller pill scales with its height, the text cap included.
    @Test(arguments: [24.0, 30.0])
    func tallerPillsScaleTheBudget(height: Double) {
        let scale = PillMetrics(height: height).scale
        let wide = String(repeating: "W", count: 30)
        let capped = pillWidth(.sessionNeedsInput(sessionID: "a", name: wide), height: height)
        #expect(capped <= (Self.pillWidthBudget * scale).rounded(.up) + 1, "\(capped) pt at \(height) pt")
        #expect(capped > pillWidth(.sessionNeedsInput(sessionID: "a", name: wide)))
    }

    @Test(arguments: [
        String(repeating: "W", count: 30),
        String(repeating: "M", count: 30),
        "INVESTIGATE FLAKY UPLOADS NOW",
        "修复登录错误并更新文档以及测试用例和发布说明内容",
        "ログイン画面のエラーを修正してテストを追加する作業",
        "로그인 오류 수정 및 문서 업데이트와 테스트 추가 작업",
        String(repeating: "🚀", count: 30),
    ])
    func momentPillStaysNarrowForWideNames(name: String) {
        // Wide glyphs make a name far wider than a typical one; the width cap keeps
        // the pill from growing past the space a notched menu bar has left.
        let finished = pillWidth(.sessionFinished(sessionID: "a", name: name))
        let needsInput = pillWidth(.sessionNeedsInput(sessionID: "a", name: name))
        #expect(finished <= Self.pillWidthBudget, "finished: \(finished) pt")
        #expect(needsInput <= Self.pillWidthBudget, "needs you: \(needsInput) pt")
    }

    @Test func ordinaryMomentNamesAreNotCut() {
        // Below the cap the pill follows the text, so a longer name gives a wider pill.
        let names = ["Fix bug", "Tidy build", "Tidy build script", "Update pricing table", "Investigate the intermit"]
        let widths = names.map { pillWidth(.sessionNeedsInput(sessionID: "a", name: $0)) }
        #expect(widths == widths.sorted() && Set(widths).count == widths.count, "\(widths)")
        #expect(widths.allSatisfy { $0 < Self.pillWidthBudget }, "\(widths)")
        let capped = pillWidth(.sessionNeedsInput(sessionID: "a", name: String(repeating: "W", count: 30)))
        #expect(widths.allSatisfy { $0 < capped }, "no ordinary name reaches the cap: \(widths) vs \(capped)")
        // A limit moment keeps its whole text.
        #expect(pillWidth(.limitCrossed(kind: .fiveHour, percent: 100)) < Self.pillWidthBudget)
    }

    @Test func cappedMomentsAllHaveOneWidth() {
        // Over the cap the text fills exactly the capped width, whatever the status after it
        // (the name is what gets cut; see headroom-render's pill-moment-wide-* for the look).
        let wide = String(repeating: "W", count: 30)
        let finished = pillWidth(.sessionFinished(sessionID: "a", name: wide))
        let needsInput = pillWidth(.sessionNeedsInput(sessionID: "a", name: wide))
        #expect(finished == needsInput, "\(finished) vs \(needsInput)")
    }

    // MARK: Stale pill

    @Test func stalePillDimsTheRingsButNotTheNumber() throws {
        // Spec §1.1: only the rings are drawn at 45 %; the limit number keeps its contrast. At 1.0's 22 pt height.
        let fresh = try pixels(PillView(
            snapshot: Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14)), moment: nil, now: now, height: 22
        ))
        let stale = try pixels(PillView(
            snapshot: Fixture.snapshot(plan: Fixture.plan(weekly: 89, fiveHour: 14, age: 45 * 60)), moment: nil, now: now,
            height: 22
        ))
        try #require(fresh.width == stale.width && fresh.height == stale.height)

        // Right to left: 9 pt padding, the number, a 7 pt gap, then the 18 pt gauge.
        let numberStrip = (fresh.width - 34 * 2)..<fresh.width
        let gaugeStrip = (fresh.width - 60 * 2)..<(fresh.width - 44 * 2)
        #expect(fresh.columns(numberStrip) == stale.columns(numberStrip), "the stale number must not be dimmed")
        #expect(fresh.columns(gaugeStrip) != stale.columns(gaugeStrip), "the stale rings are dimmed")
    }

    @Test func stalePillNumberKeepsItsColor() throws {
        // The critical red on the black capsule is 5.3:1; at 45 % it fell to 1.8:1.
        let snapshot = Fixture.snapshot(plan: Fixture.plan(weekly: 97, fiveHour: 14, age: 45 * 60))
        let image = try pixels(PillView(snapshot: snapshot, moment: nil, now: now, height: 22))
        let numberStrip = (image.width - 34 * 2)..<image.width
        let brightest = image.columns(numberStrip).map { Int($0.red) }.max() ?? 0
        #expect(brightest >= 0xD0, "brightest red in the number: \(String(brightest, radix: 16))")
    }

    // MARK: Session row name and folder

    typealias Split = NameAndFolderLayout

    @Test func nameAndFolderShowWholeWhenTheyFit() {
        let widths = Split.widths(name: 120, folder: 40, spacing: 8, available: 208)
        #expect(widths.name == 120 && widths.folder == 40)
        let unconstrained = Split.widths(name: 400, folder: 300, spacing: 8, available: nil)
        #expect(unconstrained.name == 400 && unconstrained.folder == 300)
    }

    @Test func shortFolderStaysWholeAndTheNameGivesWay() {
        // "Tidy CI workflow for release" + "ledger": the folder used to vanish over 1 pt.
        let widths = Split.widths(name: 176, folder: 33, spacing: 8, available: 208)
        #expect(widths.folder == 33)
        #expect(widths.name == 167)
    }

    @Test func longFolderUsesTheSpaceTheNameLeaves() {
        // "Short" + a 350 pt folder used to show no folder with half the row empty.
        let widths = Split.widths(name: 33, folder: 350, spacing: 8, available: 208)
        #expect(widths.name == 33)
        #expect(widths.folder == 167)
    }

    @Test func longNameAndLongFolderShareTheRow() {
        // Both too long: the folder keeps a readable minimum, the name truncates.
        let widths = Split.widths(name: 185, folder: 95, spacing: 8, available: 208)
        #expect(widths.folder == Split.minFolderWidth)
        #expect(widths.name == 200 - Split.minFolderWidth)
        // Never more than the room there is.
        let tiny = Split.widths(name: 185, folder: 95, spacing: 8, available: 40)
        #expect(tiny.name + tiny.folder <= 32)
        #expect(tiny.name >= 0 && tiny.folder >= 0)
    }

    // MARK: Helpers

    private func pixels(_ view: some View) throws -> Bitmap {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try #require(renderer.cgImage.flatMap(Bitmap.init))
    }
}

/// An RGBA8 copy of a rendered image, for comparing regions.
struct Bitmap {
    struct Pixel: Equatable {
        var red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Every pixel in these columns, top to bottom.
    func columns(_ columns: Range<Int>) -> [Pixel] {
        (0..<height).flatMap { y in
            columns.map { x in
                let i = (y * width + x) * 4
                return Pixel(red: bytes[i], green: bytes[i + 1], blue: bytes[i + 2], alpha: bytes[i + 3])
            }
        }
    }
}
