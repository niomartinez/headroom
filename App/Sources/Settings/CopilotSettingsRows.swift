import CopilotKit
import SwiftUI

/// Settings › Tools › GitHub Copilot › GitHub account (1.1 §4.6, §6.4): Connect GitHub…, Connected as @octocat ·
/// updated 5m ago with Disconnect, or Sign-in expired with Reconnect.
struct CopilotAccountRow: View {
    let account: CopilotAccount
    /// Keeps "updated 5m ago" current.
    let now: Date

    var body: some View {
        let presentation = GitHubAccountPresentation(
            login: account.login, usage: account.usage, lastUpdated: account.lastUpdated, now: now
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GitHub account")
                    Text(presentation.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if account.isDisconnecting {
                    ProgressView()
                        .controlSize(.small)
                }
                ForEach(presentation.actions, id: \.self) { action in
                    Button(GitHubAccountPresentation.title(for: action)) { perform(action) }
                        .disabled(account.isDisconnecting)
                }
            }
            if let caption = presentation.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func perform(_ action: GitHubAccountPresentation.Action) {
        switch action {
        case .connect, .reconnect: account.beginSignIn()
        case .disconnect: account.disconnect()
        }
    }
}

/// Settings › Tools › GitHub Copilot › Plan (1.1 §4.5): GitHub doesn't tell apps the plan's allowance, so the user
/// picks it; Custom takes a number.
struct CopilotPlanPicker: View {
    let account: CopilotAccount

    @State private var customText = ""
    @State private var customRejected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Plan", selection: Binding(get: { account.plan }, set: { account.setPlan($0) })) {
                ForEach(CopilotPlan.allCases, id: \.self) { plan in
                    Text(plan.label).tag(plan)
                }
            }
            if account.plan == .custom {
                HStack {
                    Text("A month")
                    Spacer()
                    TextField("Credits or requests", text: $customText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                        .onSubmit {
                            customRejected = !account.setCustomAllowance(CustomAllowanceText.value(customText))
                        }
                        .onChange(of: customText) { _, text in
                            // Kept as soon as it is valid; said to be wrong only on Return. The saved value shown
                            // by onAppear isn't saved again.
                            let value = CustomAllowanceText.value(text)
                            guard value != account.customAllowance else { return }
                            if account.setCustomAllowance(value) { customRejected = false }
                        }
                }
                if customRejected {
                    Text("Enter a number from 1 to 1,000,000.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Text(GitHubCopy.planCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            customText = CustomAllowanceText.text(for: account.customAllowance)
        }
    }
}

/// Settings › Tools › GitHub Copilot › Copilot CLI (1.1 §4.9, §6.4): Connect / Update / Disconnect.
struct CopilotCLIRow: View {
    let presentation: CopilotCLIPresentation
    let isBusy: Bool
    let connect: () -> Void
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Session activity")
                Text(presentation.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            ForEach(presentation.actions, id: \.self) { action in
                Button(CopilotCLIPresentation.title(for: action)) { perform(action) }
                    .disabled(isBusy)
            }
        }
    }

    private func perform(_ action: CopilotCLIPresentation.Action) {
        switch action {
        case .connect, .update: connect()
        case .disconnect: disconnect()
        }
    }
}
