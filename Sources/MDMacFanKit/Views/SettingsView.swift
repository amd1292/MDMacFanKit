import MDFanCore
import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"
    static let width: CGFloat = 640

    @StateObject private var tab: ViewState<Int>

    init(selectedTab: Int = 0) {
        _tab = StateObject(wrappedValue: ViewState(selectedTab))
    }

    var body: some View {
        TabView(selection: $tab.value) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)
            PresetSettings()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
                .tag(1)
            SensorList()
                .tabItem { Label("Sensors", systemImage: "thermometer.medium") }
                .tag(2)
            HelperSettings()
                .tabItem { Label("Helper", systemImage: "lock.shield") }
                .tag(3)
        }
        .frame(width: Self.width, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                TemperatureSourcePicker(title: "Overall temperature", selection: $model.generalSource)
                Picker("Unit", selection: $model.useFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section("Behavior") {
                Picker("Update every", selection: $model.refreshInterval) {
                    ForEach([1.0, 2, 3, 5], id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.launchAtLogin = $0 }))
            }
            Section {
                Text("Quitting the app always hands the fans back to macOS.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct TemperatureSourcePicker: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    @Binding var selection: TemperatureSource

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(TemperatureSource.aggregates, id: \.self) { source in
                Text(source.title()).tag(source)
            }
            Divider()
            ForEach(SensorGroup.allCases) { group in
                let members = model.sensors.filter { $0.group == group }.sorted { $0.name < $1.name }
                if !members.isEmpty {
                    Section(group.title) {
                        ForEach(members) { sensor in
                            Text("\(sensor.name)  (\(model.formatted(sensor.value)))")
                                .tag(TemperatureSource.sensor(sensor.id))
                        }
                    }
                }
            }
            // Keep a stored sensor selectable even if it is not reporting right now.
            if case .sensor(let id) = selection, !model.sensors.contains(where: { $0.id == id }) {
                Text(id).tag(selection)
            }
        }
    }
}

// MARK: - Presets

private struct PresetSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: PresetStore
    static let listWidth: CGFloat = 180
    @StateObject private var selectionState = ViewState<UUID?>(nil)

    private var selection: UUID? {
        get { selectionState.value }
        nonmutating set { selectionState.value = newValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectionState.value) {
                    ForEach(store.presets) { preset in
                        HStack {
                            Text(preset.name)
                            Spacer()
                            if model.activePreset?.id == preset.id {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                        .tag(preset.id)
                    }
                    .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { addPreset() } label: { Image(systemName: "plus") }
                        .help("New preset")
                    Button { duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate")
                        .disabled(selection == nil)
                    Button {
                        if let selection { store.delete(selection) }
                        selection = nil
                    } label: { Image(systemName: "minus") }
                        .help("Delete")
                        .disabled(selection == nil || selection == FanPreset.systemID)
                    Spacer()
                    Menu {
                        Button("Restore Default Presets") { store.restoreDefaults() }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: Self.listWidth)

            Divider()

            if let selection, let index = store.presets.firstIndex(where: { $0.id == selection }) {
                PresetEditor(preset: $store.presets[index])
                    .id(selection)
                    // Forms report a wide ideal width; pin the editor to the space left of the list.
                    .frame(width: SettingsView.width - PresetSettings.listWidth - 1)
            } else {
                Text("Select a preset")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? model.activePreset?.id ?? store.presets.first?.id }
    }

    private func addPreset() {
        let preset = FanPreset(name: "My Preset", mode: .curve,
                               points: [.init(temperature: 50, percent: 0), .init(temperature: 70, percent: 40),
                                        .init(temperature: 90, percent: 100)])
        selection = store.add(preset)
    }

    private func duplicateSelected() {
        guard let selection, var copy = store.preset(selection) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        copy.points = copy.points.map { CurvePoint(temperature: $0.temperature, percent: $0.percent) }
        self.selection = store.add(copy)
    }
}

// MARK: - Sensors

private struct SensorList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(SensorGroup.allCases) { group in
                let members = model.sensors.filter { $0.group == group }.sorted { $0.name < $1.name }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { sensor in
                            HStack {
                                Text(sensor.name)
                                Text(sensor.id.hasPrefix("smc:") ? "SMC" : "HID")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Text(model.formatted(sensor.value, decimals: 1, unit: true))
                                    .monospacedDigit()
                                    .foregroundStyle(temperatureColor(sensor.value))
                            }
                        }
                    } header: {
                        Label("\(group.title) — \(members.count)", systemImage: group.symbol)
                    }
                }
            }
            Section("Fans") {
                ForEach(model.fans) { fan in
                    HStack {
                        Text(fan.name)
                        Spacer()
                        Text("\(Int(fan.actualRPM)) rpm · min \(Int(fan.minimumRPM)) · max \(Int(fan.maximumRPM))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Helper

private struct HelperSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Privileged helper") {
                LabeledContent("Status") {
                    switch model.helperState {
                    case .checking: Text("Checking…")
                    case .notInstalled: Text("Not installed").foregroundStyle(.orange)
                    case .outdated(let version): Text("Outdated (v\(version))").foregroundStyle(.orange)
                    case .ready: Text("Running").foregroundStyle(.green)
                    }
                }
                Text("""
                Changing fan speeds means writing to the SMC, which only root can do. The helper is a small \
                LaunchDaemon installed at \(HelperConstants.installedBinaryPath). It only accepts fan commands, \
                clamps every speed to the fan's own limits, and hands all fans back to macOS when the app quits \
                or stops responding for \(Int(HelperConstants.heartbeatTimeout)) seconds.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack {
                    Button(model.helperState == .notInstalled ? "Install Helper…" : "Reinstall Helper…") {
                        model.installHelper()
                    }
                    Button("Uninstall…") { model.uninstallHelper() }
                        .disabled(model.helperState == .notInstalled)
                    Spacer()
                    Button("Check Again") { model.checkHelper() }
                }
            }
            if let error = model.lastError {
                Section("Last error") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                    Button("Clear") { model.lastError = nil }
                }
            }
        }
        .formStyle(.grouped)
    }
}
