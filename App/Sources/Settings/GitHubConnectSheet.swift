import SwiftUI

/// The Connect GitHub sheet (1.1 §4.3, §6.4): the device code to enter on GitHub, then "Waiting for GitHub…", then
/// "Connected as @octocat" or what went wrong.
struct GitHubConnectSheet: View {
    let account: CopilotAccount

    var body: some View {
        VStack(spacing: 16) {
            Text(GitHubCopy.sheetTitle)
                .font(.headline)
            content
        }
        .padding(24)
        .frame(width: 400)
    }

    @ViewBuilder
    private var content: some View {
        switch account.signIn {
        case .requestingCode?, nil:
            ProgressView()
                .controlSize(.small)
            Text(GitHubCopy.requestingCode)
                .foregroundStyle(.secondary)
            buttons(primary: nil)
        case let .code(userCode, _, opened)?:
            Text(GitHubCopy.sheetBody)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(userCode)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityLabel("Code \(userCode.map(String.init).joined(separator: " "))")
            if opened {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(GitHubCopy.waiting)
                        .foregroundStyle(.secondary)
                }
            }
            buttons(primary: (GitHubCopy.copyAndOpen, account.copyCodeAndOpenGitHub))
        case let .failed(message)?:
            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            buttons(primary: ("Try Again", account.beginSignIn))
        case let .connected(login)?:
            Label(GitHubCopy.connected(login), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            HStack {
                Spacer()
                Button("Done", action: account.endSignIn)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Cancel, and the step's primary button.
    private func buttons(primary: (title: String, action: () -> Void)?) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: account.endSignIn)
                .keyboardShortcut(.cancelAction)
            if let primary {
                Button(primary.title, action: primary.action)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
