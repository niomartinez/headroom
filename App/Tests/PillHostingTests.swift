import AppKit
import HeadroomModel
import HeadroomSamples
import HeadroomUI
import Testing

@Suite("Native pill images", .serialized)
@MainActor
struct PillHostingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func frame(name: String? = nil, moment: Moment? = nil) throws -> PillImageFrame {
        let inputs = PillInputs(snapshot: .empty(at: now), moment: moment, now: now,
                                attention: name.flatMap { NeedsYouAttention(names: [$0]) }, height: 24)
        return try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
    }

    @Test(arguments: [1.0, 2.0])
    func nativeImageRetainsOpaqueBackgroundAtBothPixelDensities(scale: CGFloat) throws {
        let frame = try frame(name: "Fix pill on inactive monitor")
        for width in [frame.size.width, frame.size.width + 80, frame.size.width - 30] {
            for opacity in [0.0, 0.5, 1.0] {
                let image = frame.image(width: width, textOpacity: opacity)
                #expect(!image.isTemplate)
                #expect(image.size == NSSize(width: ceil(width), height: 24))
                let bitmap = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * scale), pixelsHigh: Int(24 * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ))
                let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                context.cgContext.scaleBy(x: scale, y: scale)
                image.draw(in: NSRect(origin: .zero, size: image.size))
                NSGraphicsContext.restoreGraphicsState()
                let background = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(scale))?.usingColorSpace(.deviceRGB))
                #expect(background.alphaComponent > 0.99)
                #expect(background.redComponent < 0.01)
                #expect(background.greenComponent < 0.01)
                #expect(background.blueComponent < 0.01)
                #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01)
            }
        }
    }

    @Test func attentionExpandsForAnOrdinaryTaskTitle() throws {
        let short = "Fix pill"
        let long = "Fix pill on inactive monitor"
        let font = NSFont.systemFont(ofSize: PillMetrics(height: 24).fontSize, weight: .medium)
        let requiredGrowth = (long as NSString).size(withAttributes: [.font: font]).width
            - (short as NSString).size(withAttributes: [.font: font]).width
        let actualGrowth = try frame(name: long).size.width - frame(name: short).size.width
        #expect(actualGrowth >= requiredGrowth - 4)
        #expect(try frame(name: String(repeating: "W", count: 200)).size.width < 340)
    }

    @Test(arguments: ["Fix pill on inactive monitor", "Fix pill behavior across monitors"])
    func momentAndRestingPillGiveTheSameTaskNameEqualRoom(long: String) throws {
        let short = "Fix pill"
        let restingGrowth = try frame(name: long).size.width - frame(name: short).size.width
        for needsInput in [true, false] {
            func moment(_ name: String) -> Moment {
                needsInput ? .sessionNeedsInput(sessionID: "s", name: name)
                    : .sessionFinished(sessionID: "s", name: name)
            }
            let momentGrowth = try frame(moment: moment(long)).size.width - frame(moment: moment(short)).size.width
            #expect(abs(momentGrowth - restingGrowth) <= 2,
                    "A task name must not shorten for the announcement and expand again when it rests.")
            #expect(try frame(moment: moment(String(repeating: "W", count: 200))).size.width < 420)
        }
    }

    @Test func focusDoesNotChangeSharedImageHeight() {
        #expect(StatusItemMotion.sharedPillHeight(menuBarHeights: [30, 37]) == 24)
        #expect(StatusItemMotion.sharedPillHeight(menuBarHeights: [37, 30]) == 24)
        #expect(StatusItemMotion.sharedPillHeight(menuBarHeights: [24, 37]) == 22)
        #expect(StatusItemMotion.sharedPillHeight(menuBarHeights: []) == 22)
    }

    @Test func widthBudgetFitsTheSmallestDisplayRegardlessOfFocus() {
        #expect(StatusItemMotion.widthBudget(lanes: [760, 210]) == 210)
        #expect(StatusItemMotion.widthBudget(lanes: [210, 760]) == 210)
        #expect(StatusItemMotion.widthBudget(lanes: [210]) == 210)
        #expect(StatusItemMotion.widthBudget(lanes: [.nan, .infinity, -1, 0]) == nil)
    }

    @Test func compactKeepsTheStatusAndGaugeWithoutAllocatingTitleWidth() throws {
        let sample = SampleData.fixed
        let snapshot = sample.multiTool
        var inputs = PillInputs(snapshot: snapshot, moment: nil, now: sample.now, gaugePerTool: true,
                                attention: NeedsYouAttention(names: ["A long task title that stays in the panel"]),
                                height: 24, compact: true)
        let compact = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
        #expect(!inputs.model.isGaugePerTool)
        #expect(inputs.model.accessibilityLabel.contains("A long task title"))
        #expect(compact.size.width < 140)
        inputs.attention = NeedsYouAttention(names: ["Short"])
        let short = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
        #expect(short.size == compact.size)
        let key = PillDrawKey(inputs)
        inputs.compact = false
        #expect(PillDrawKey(inputs) != key)
        inputs.maximumWidth = compact.size.width + 1
        let crowded = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
        #expect(crowded.size.width > compact.size.width + 10,
                "Automatic can shorten the title, but it must preserve the selected tool gauges.")
        inputs.attention = nil
        inputs.maximumWidth = nil
        let normal = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
        inputs.maximumWidth = 1
        let smallestBudget = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
        #expect(smallestBudget.size == normal.size, "A conservative width estimate must not hide a requested ring.")
    }

    @Test func inactiveCopiesReceiveFinishedPixelsForPulseAndGaugeChanges() throws {
        let sample = SampleData.fixed
        func rendered(percent: Double, date: Date) throws -> NSImage {
            let inputs = PillInputs(snapshot: sample.snapshot(sample.plan(weekly: percent, fiveHour: 18), sample.working),
                                    moment: nil, now: sample.now, height: 24)
            let frame = try #require(PillImageFrame(inputs: inputs, differentiateWithoutColor: false))
            return frame.image(width: frame.size.width, textOpacity: 1, pulseDate: date)
        }
        let first = try rendered(percent: 81, date: Date(timeIntervalSinceReferenceDate: 0))
        let pulsed = try rendered(percent: 81, date: Date(timeIntervalSinceReferenceDate: 0.6))
        let updated = try rendered(percent: 94, date: Date(timeIntervalSinceReferenceDate: 0.6))
        for image in [first, pulsed, updated] {
            // A remote copy must be able to take pixels without invoking a drawing callback on the original view.
            let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            #expect(bitmaps.count == 2)
            #expect(bitmaps.map(\.size) == [image.size, image.size])
            #expect(bitmaps.map(\.pixelsWide) == [Int(image.size.width), Int(image.size.width * 2)])
        }
        #expect(first.tiffRepresentation != pulsed.tiffRepresentation)
        #expect(pulsed.tiffRepresentation != updated.tiffRepresentation)
    }

    @Test func waitingHasOnePersistentLayoutWithoutATimedSuffix() throws {
        let moment = Moment.sessionNeedsInput(sessionID: "s", name: "Fix pill behavior across monitors")
        let attention = try #require(NeedsYouAttention(names: ["Fix pill behavior across monitors"]))
        let initial = PillInputs(snapshot: .empty(at: now), moment: PillInputs.menuBarMoment(moment), now: now,
                                 attention: attention, height: 24)
        let later = PillInputs(snapshot: .empty(at: now), moment: PillInputs.menuBarMoment(nil), now: now,
                               attention: attention, height: 24)
        #expect(PillDrawKey(initial) == PillDrawKey(later))
        #expect(initial.model.mode == .attention)
        let finished = Moment.sessionFinished(sessionID: "s", name: "Fix pill")
        #expect(PillInputs.menuBarMoment(finished) == finished)
        let limit = Moment.limitCrossed(kind: .weekly, percent: 90)
        #expect(PillInputs.menuBarMoment(limit) == limit)
    }

    @Test func trailingGaugeAndPercentKeepTheirSpaceAcrossLayouts() throws {
        let samples = SampleData.fixed
        let snapshot = samples.snapshot(samples.plan(weekly: 91, fiveHour: 18), samples.working)
        let attention = NeedsYouAttention(names: ["Fix pill behavior across monitors"])
        let states = [
            PillInputs(snapshot: snapshot, moment: nil, now: samples.now, height: 24),
            PillInputs(snapshot: snapshot, moment: nil, now: samples.now, attention: attention, height: 24),
            PillInputs(snapshot: snapshot, moment: .sessionFinished(sessionID: "s", name: "Fix pill"), now: samples.now, height: 24)
        ]
        let frames = try states.map { try #require(PillImageFrame(inputs: $0, differentiateWithoutColor: false)) }
        let trailingWidth = frames[0].size.width - frames[0].gaugeX
        #expect(trailingWidth > 50, "The 91% label must keep its space beside the rings.")
        for frame in frames {
            #expect(abs(frame.size.width - frame.gaugeX - trailingWidth) <= 1)
        }
    }

    @Test func everyWarningPercentageKeepsItsSpaceAcrossNativeLayouts() throws {
        let sample = SampleData.fixed
        var snapshot = sample.snapshot(sample.plan(weekly: 94, fiveHour: 18), sample.working)
        snapshot.codex = sample.codex(weekly: 85)
        snapshot.copilot = sample.copilot(used: 100, allowance: 100)
        let states = [
            PillInputs(snapshot: snapshot, moment: nil, now: sample.now, gaugePerTool: true, height: 24),
            PillInputs(snapshot: snapshot, moment: nil, now: sample.now, gaugePerTool: true,
                       attention: NeedsYouAttention(names: ["Review changes"]), height: 24),
            PillInputs(snapshot: snapshot, moment: .sessionFinished(sessionID: "s", name: "Review changes"),
                       now: sample.now, gaugePerTool: true, height: 24)
        ]
        let frames = try states.map { try #require(PillImageFrame(inputs: $0, differentiateWithoutColor: false)) }
        let trailingWidth = frames[0].size.width - frames[0].gaugeX
        #expect(trailingWidth > 180, "All three gauges and their percentages must fit.")
        for frame in frames {
            #expect(abs(frame.size.width - frame.gaugeX - trailingWidth) <= 1)
        }
        var crowded = states[0]
        crowded.maximumWidth = 1
        #expect(try #require(PillImageFrame(inputs: crowded, differentiateWithoutColor: false)).size == frames[0].size,
                "Automatic sizing must preserve every selected gauge and warning percentage.")
        crowded.compact = true
        let compact = try #require(PillImageFrame(inputs: crowded, differentiateWithoutColor: false))
        #expect(!crowded.model.isGaugePerTool)
        #expect(crowded.model.badge?.text == "94%")
        #expect(compact.size.width < frames[0].size.width)
    }

    @Test(arguments: [false, true])
    func transitionKeepsItsCanvasAndRightEdgeStable(shrinking: Bool) throws {
        let short = try frame(name: "Fix pill")
        let long = try frame(name: "Fix pill behavior across monitors")
        let from = shrinking ? long : short
        let to = shrinking ? short : long
        let canvas = max(from.size.width, to.size.width)
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let width = from.size.width + (to.size.width - from.size.width) * progress
            let image = to.transitionImage(from: from, width: width, canvasWidth: canvas, progress: progress)
            #expect(image.size == NSSize(width: canvas, height: 24))
            #expect(!image.isTemplate)
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(canvas * 2), pixelsHigh: 48,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.current?.cgContext.scaleBy(x: 2, y: 2)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            // The capsule grows left inside the same canvas; its right edge never follows a changing image size.
            #expect((bitmap.colorAt(x: bitmap.pixelsWide - 2, y: 24)?.alphaComponent ?? 0) > 0.99)
            let blankColumn = Int((canvas - width) * 2) - 3
            if blankColumn >= 0 {
                #expect((bitmap.colorAt(x: blankColumn, y: 24)?.alphaComponent ?? 1) < 0.01)
            }
            // There is always visible title content, including the midpoint; no hidden-text resize phase.
            let gaugeX = from.gaugeX + (to.gaugeX - from.gaugeX) * progress
            let textStart = Int((canvas - width + 25) * 2)
            let textEnd = Int((canvas - width + gaugeX - 5) * 2)
            var visibleText = false
            for x in textStart..<textEnd {
                for y in 8..<40 {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       min(color.redComponent, color.greenComponent, color.blueComponent) > 0.2 {
                        visibleText = true
                    }
                }
            }
            #expect(visibleText)
        }
    }

    @Test func nativeButtonDoesNotScaleThePill() throws {
        let frame = try frame()
        let item = NSStatusBar.system.statusItem(withLength: frame.size.width + 4)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try #require(item.button)
        button.imageScaling = .scaleNone
        button.imagePosition = .imageOnly
        button.image = frame.image(width: frame.size.width, textOpacity: 1)
        let rect = try #require(button.cell?.imageRect(forBounds: button.bounds))
        #expect(rect.size == frame.size)
    }

    @Test func incomingTitleHasFullContrastDuringExpansion() throws {
        let from = try frame()
        let to = try frame(name: "Fix pill")
        let width = (from.size.width + to.size.width) / 2
        let image = to.transitionImage(from: from, width: width, canvasWidth: to.size.width, progress: 0.5)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(to.size.width * 2), pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.current?.cgContext.scaleBy(x: 2, y: 2)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let origin = to.size.width - width
        let gauge = (from.gaugeX + to.gaugeX) / 2
        var brightest: CGFloat = 0
        for x in Int((origin + 27) * 2)..<Int((origin + gauge - 3) * 2) {
            for y in 8..<40 {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    brightest = max(brightest, min(color.redComponent, color.greenComponent, color.blueComponent))
                }
            }
        }
        #expect(brightest > 0.9, "The title reveals with the capsule instead of fading in behind it.")
    }

    @Test func completionUsesTheNameOnlyAndFitsTheAvailableWidth() throws {
        let name = "Fix pill completion animation and identify sessions across all three tools"
        func completion(_ name: String, width: CGFloat) throws -> PillImageFrame {
            try #require(PillImageFrame(inputs: PillInputs(
                snapshot: .empty(at: now), moment: .sessionFinished(sessionID: "s", name: name), now: now,
                height: 24, maximumWidth: width
            ), differentiateWithoutColor: false))
        }
        let short = try completion("Fix", width: 1000)
        let full = try completion(name, width: 1000)
        let constrained = try completion(name, width: 300)
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let titleGrowth = (name as NSString).size(withAttributes: [.font: font]).width
            - ("Fix" as NSString).size(withAttributes: [.font: font]).width
        #expect(abs(full.size.width - short.size.width - titleGrowth) < 3)
        #expect(full.size.width > 400)
        #expect(constrained.size.width <= 300)
        #expect(abs(full.size.width - full.gaugeX - (constrained.size.width - constrained.gaugeX)) <= 1)
        // Name + check slot + gauge + three gaps/padding: there is no space reserved for "finished".
        let metrics = PillMetrics(height: 24)
        let fixed = metrics.fontSize + 2 + metrics.gaugeSize + 2 * metrics.spacing + 2 * metrics.horizontalPadding
        #expect(abs(short.size.width - fixed - ("Fix" as NSString).size(withAttributes: [.font: font]).width) < 3)
        #expect(full.key.model.accessibilityLabel.contains("finished"))
    }

    @Test func completionCheckDrawsProgressivelyAndNeverBecomesACircle() throws {
        let from = try frame()
        let to = try frame(moment: .sessionFinished(sessionID: "s", name: "Fix pill"))
        var counts: [Int] = []
        for time in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let image = to.transitionImage(from: from, width: to.size.width, canvasWidth: to.size.width,
                                           progress: PillMotion<Int>.progress(time))
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(to.size.width * 2), pixelsHigh: 48,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.current?.cgContext.scaleBy(x: 2, y: 2)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            var painted = 0
            for x in 20..<50 {
                for y in 6..<42 {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       color.greenComponent > 0.3, color.greenComponent > color.redComponent * 1.5 {
                        painted += 1
                    }
                }
            }
            counts.append(painted)
        }
        #expect(counts[0] == 0)
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0 < $1 })
        #expect(counts.last! < 200, "Only the thin check is painted, without a filled green disc.")
    }
}
