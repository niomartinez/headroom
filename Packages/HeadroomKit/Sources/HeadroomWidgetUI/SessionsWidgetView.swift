import HeadroomModel
import HeadroomUI
import SwiftUI
import WidgetKit

/// The Sessions widget (1.1 §5.6): medium lists the first 3 sessions under a headline; large shows the tracked
/// tools' compact limit rows and up to 6 sessions grouped Working / Needs you / Idle.
public struct SessionsWidgetView: View {
    public enum Size: Sendable {
        case medium
        case large
    }

    public var model: SessionsWidgetModel
    public var size: Size

    public init(model: SessionsWidgetModel, size: Size) {
        self.model = model
        self.size = size
    }

    public var body: some View {
        Group {
            switch size {
            case .medium: medium
            case .large: large
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    // MARK: Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                StaticDot(state: model.dot)
                Text(model.headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HeadroomTheme.primaryText)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)
            if model.rows.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.rows.prefix(SessionsWidgetModel.mediumRowLimit)) { row in
                        SessionRow(row: row, showsBar: false)
                    }
                }
                .opacity(model.isOutdated ? HeadroomTheme.staleOpacity : 1)
            }
            Spacer(minLength: 4)
            FooterText(footer: model.footer)
        }
    }

    // MARK: Large

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.tools.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.tools) { CompactToolRow(summary: $0) }
                }
                Rectangle()
                    .fill(HeadroomTheme.separator)
                    .frame(height: 1)
                    .padding(.vertical, 10)
            }
            if model.rows.isEmpty {
                emptyState
                Spacer(minLength: 4)
            } else {
                // As many rows as fit, up to 6: three tools with two windows each leave room for fewer.
                ViewThatFits(in: .vertical) {
                    ForEach((1...SessionsWidgetModel.largeRowLimit).reversed(), id: \.self) { limit in
                        sessionList(limit: limit)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(model.isOutdated ? HeadroomTheme.staleOpacity : 1)
            }
            HStack {
                FooterText(footer: model.footer)
                Spacer(minLength: 8)
                if !model.isEmpty, model.rows.contains(where: { $0.dot != .idle }) {
                    Text(model.headline)
                        .font(.system(size: 11))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    private func sessionList(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.sections(limit: limit)) { section in
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HeadroomTheme.secondaryText)
                        .padding(.bottom, 2)
                    ForEach(section.rows) { SessionRow(row: $0, showsBar: true) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let message = model.emptyMessage {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
}

/// Dot, name, tool tag when tools mix, terminal symbol, and the context percent (with the panel's 44×4 bar in the
/// large widget).
struct SessionRow: View {
    var row: SessionsWidgetModel.Row
    var showsBar: Bool

    var body: some View {
        HStack(spacing: 8) {
            StaticDot(state: row.dot)
            Text(row.name)
                .font(.system(size: 13))
                .foregroundStyle(HeadroomTheme.primaryText)
                .lineLimit(1)
            if let tag = row.toolTag {
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            if row.isTerminal {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(HeadroomTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if let context = row.context {
                if showsBar, !context.windowIsAssumed {
                    ContextBarShape(fraction: context.fraction, severity: context.severity)
                }
                Text(context.text)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(
                        context.severity == .normal ? HeadroomTheme.secondaryText : HeadroomTheme.color(for: context.severity)
                    )
                    .lineLimit(1)
                    .frame(minWidth: 30, alignment: .trailing)
            }
        }
        .frame(height: 20)
    }
}

/// The panel's 44×4 context bar (its `ContextBar` is internal to HeadroomUI).
struct ContextBarShape: View {
    static let size = CGSize(width: 44, height: 4)

    var fraction: Double
    var severity: Severity

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let clamped = min(1, max(0, fraction))
        let fill = clamped > 0 ? max(Self.size.height, Self.size.width * clamped) : 0
        let seeThrough = SeeThrough.isOn(renderingMode: renderingMode, showsBackground: showsBackground)
        ZStack(alignment: .leading) {
            Capsule().fill(seeThrough ? Color.primary.opacity(0.22) : HeadroomTheme.track)
            Capsule().fill(HeadroomTheme.color(for: severity)).frame(width: fill).widgetAccentable()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}
