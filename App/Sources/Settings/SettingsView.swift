import SwiftUI

/// Connect and Disconnect Copilot CLI, for Settings; nil in a build without Copilot CLI support (1.1 §4.9).
struct CopilotCLIActions {
    var connect: @MainActor () -> Void
    var disconnect: @MainActor () -> Void
}

/// Settings and first-run onboarding (spec §1.3): three tabs in a 500 pt window (1.1 §6.4). General holds the app's
/// behavior, Tools what Headroom reads for each tool, About the version and the notice.
struct SettingsView: View {
    let model: AppModel
    let launchAtLogin: LaunchAtLogin
    let terminal: TerminalConnection
    let copilotCLI: CopilotCLIActions?
    let navigation: SettingsNavigation
    let grantAccess: (HeadroomFolder) -> Void
    let close: () -> Void

    var body: some View {
        Group {
            if navigation.isOnboarding {
                OnboardingView(model: model, terminal: terminal, copilotCLI: copilotCLI,
                               navigation: navigation, grantAccess: grantAccess, close: close)
            } else {
                tabs
            }
        }
        .frame(width: 500)
        .sheet(isPresented: Binding(
            get: { model.copilot.signIn != nil },
            set: { if !$0 { model.copilot.endSignIn() } }
        )) {
            GitHubConnectSheet(account: model.copilot)
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { navigation.tab }, set: { navigation.select($0) })) {
            GeneralSettingsTab(model: model, launchAtLogin: launchAtLogin, setUpTools: navigation.beginOnboarding)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ToolsSettingsTab(model: model, terminal: terminal, copilotCLI: copilotCLI, grantAccess: grantAccess)
                .tabItem { Label("Tools", systemImage: "square.stack.3d.up") }
                .tag(SettingsTab.tools)
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
    }
}

/// Settings › General (1.1 §6.4, §14.4): launch at login, moments (and keeping "needs you"), sample data, the menu bar
/// item, widgets.
struct GeneralSettingsTab: View {
    let model: AppModel
    let launchAtLogin: LaunchAtLogin
    var setUpTools: () -> Void = {}

    var body: some View {
        Form {
            Section {
                Text(SettingsCopy.intro)
                    .foregroundStyle(.secondary)
                Button("Set up tools…", action: setUpTools)
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("Allow Headroom in Login Items to finish turning this on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(isOn: Binding(get: { model.showMoments }, set: { model.setShowMoments($0) })) {
                    Text("Show moments")
                    Text(SettingsCopy.showMomentsDetail)
                }
                // A sub-setting of Show moments: it keeps a moment's "needs you" (1.1 §14.4).
                Toggle(SettingsCopy.keepNeedsYou, isOn: Binding(
                    get: { model.keepNeedsYou },
                    set: { model.setKeepNeedsYou($0) }
                ))
                .padding(.leading, 16)
                .disabled(!model.showMoments)
                Toggle(isOn: Binding(get: { model.sampleData.isOn }, set: { model.setShowSampleData($0) })) {
                    Text("Show sample data")
                    Text(SettingsCopy.sampleDataDetail)
                }
            }
            menuBar
            Section("Widgets") {
                Text(SettingsCopy.widgetsHowTo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(SettingsCopy.widgetShowsSessionNames, isOn: Binding(
                    get: { model.widgetShowsSessionNames },
                    set: { model.setWidgetShowsSessionNames($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Rings show" offers the tracked tools that have limits; "One gauge per tool" needs two or more tools.
    private var menuBar: some View {
        Section("Menu bar") {
            Picker(selection: Binding(get: { model.menuBarLayout }, set: { model.setMenuBarLayout($0) })) {
                ForEach(MenuBarLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            } label: {
                Text("Display")
                Text("Automatic expands task titles when space allows. Always compact keeps one gauge and shows full titles in the panel.")
            }
            Picker(selection: Binding(get: { model.ringsChoice }, set: { model.setRingsChoice($0) })) {
                ForEach(RingsChoice.allCases) { choice in
                    Text(choice.title)
                        .tag(choice)
                        .selectionDisabled(!choice.isAvailable(in: model.snapshot))
                }
            } label: {
                Text(SettingsCopy.ringsShow)
                Text(SettingsCopy.ringsShowCaption)
            }
            Toggle(isOn: Binding(get: { model.gaugePerTool }, set: { model.setGaugePerTool($0) })) {
                Text(SettingsCopy.gaugePerTool)
                Text(SettingsCopy.gaugePerToolCaption)
            }
            .disabled(model.menuBarLayout == .compact || !GaugePerTool.isAvailable(in: model.snapshot))
            Text("macOS controls menu bar visibility. Command-drag Headroom toward the clock to give it a better position when space is tight.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("Pill not visible?", destination: URL(string: "https://headroom.niomartinez.com/support#pill-not-visible")!)
                .font(.caption)
        }
    }
}

/// Settings › About: version and the non-affiliation notice.
struct AboutSettingsTab: View {
    var body: some View {
        Form {
            Section {
                AboutRow()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
