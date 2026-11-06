import SwiftUI

/// Access prompt, the Working / Needs you / Just finished / Idle sections, or the empty state (spec §1.2 items 2–3).
struct SessionListView: View {
    let model: PanelModel
    @Binding var idleExpanded: Bool
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let accessMessage = model.accessMessage {
                AccessRowView(message: accessMessage, grantAccess: actions.grantAccess)
            }
            if let codexOffer = model.codexOffer {
                CodexOfferView(message: codexOffer, giveAccess: actions.giveCodexAccess, notNow: actions.declineCodex)
            }
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HeadroomTheme.secondaryText)
                            // VoiceOver users can jump between Working / Needs you / Just finished / Idle.
                            .accessibilityAddTraits(.isHeader)
                        if let clearTitle = section.clearTitle {
                            Spacer(minLength: 8)
                            Button(clearTitle) { actions.clearFinished() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HeadroomTheme.secondaryText)
                                .help("Move every finished session to Idle.")
                                .accessibilityLabel("Clear just finished")
                        }
                    }
                    .padding(.bottom, 4)
                    ForEach(section.rows) { SessionRowView(row: $0, actions: actions) }
                    if let toggleTitle = section.toggleTitle {
                        Button(toggleTitle) { idleExpanded.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HeadroomTheme.secondaryText)
                            .padding(.leading, SessionRowView.textInset + (section.rows.first?.toolTag != nil
                                ? SessionToolIcon.width + SessionRowView.spacing : 0))
                            .padding(.top, 4)
                    }
                }
            }
            if let notice = model.sessionNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            if let emptyMessage = model.emptyMessage {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(HeadroomTheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            if let offer = model.sampleDataOffer {
                SampleDataOfferView(title: offer, show: actions.showSampleData)
            }
        }
    }
}

/// Shown when Headroom found no Claude data at all: a way to see what it does anyway.
struct SampleDataOfferView: View {
    let title: String
    let show: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(title) { show() }
                .buttonStyle(PanelButtonStyle())
            Text("Made-up sessions and limits, to see how Headroom works.")
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

struct AccessRowView: View {
    let message: String
    let grantAccess: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Symbols.lock)
                .font(.system(size: 11))
                .foregroundStyle(HeadroomTheme.warning)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HeadroomTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Give access") { grantAccess() }
                .buttonStyle(PanelButtonStyle())
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HeadroomTheme.rowHighlight))
    }
}

/// "Codex found on this Mac. Show its limits and sessions here too?" (1.1 §6.3): shown once, above the sessions.
struct CodexOfferView: View {
    let message: String
    let giveAccess: @MainActor () -> Void
    let notNow: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HeadroomTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Give access") { giveAccess() }
                    .buttonStyle(PanelButtonStyle())
                Button("Not now") { notNow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.secondaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HeadroomTheme.rowHighlight))
    }
}
