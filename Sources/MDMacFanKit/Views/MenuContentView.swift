import MDFanCore
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: PresetStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var showManual = ViewState(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.helperState.isReady { HelperBanner() }
            if model.conflictingAppRunning {
                Notice(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: "Macs Fan Control is running. Quit it so the two apps don't fight over the fans.")
            }
            if let error = model.lastError {
                Notice(symbol: "xmark.octagon.fill", tint: .red, text: error)
            }

            section("Fans") {
                ForEach(model.fans) { FanRow(fan: $0) }
                if model.fans.isEmpty { Text("No fans found").foregroundStyle(.secondary) }
            }

            section("Presets") {
                ForEach(store.presets) { preset in
                    PresetRow(preset: preset, isActive: model.activePreset?.id == preset.id) {
                        model.select(preset: preset.id)
                    }
                }
            }

            DisclosureGroup(isExpanded: $showManual.value) {
                VStack(spacing: 10) {
                    ForEach(model.fans) { fan in
                        ManualFanSlider(fan: fan)
                    }
                }
                .padding(.top, 6)
            } label: {
                SectionTitle("Manual control")
            }
            .disabled(!model.helperState.isReady)

            section("Temperatures") {
                TemperatureSummary()
            }

            Divider()
            HStack {
                Button("Settings…") {
                    openWindow(id: SettingsView.windowID)
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.generalSource.title(sensors: model.sensors))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.formatted(model.generalTemperature, decimals: 1, unit: true))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(temperatureColor(model.generalTemperature))
            }
            Spacer()
            Text(model.controlTitle)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title)
            content()
        }
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

func temperatureColor(_ celsius: Double?) -> Color {
    guard let celsius else { return .secondary }
    switch celsius {
    case ..<60: return .primary
    case ..<80: return .orange
    default: return .red
    }
}

private struct FanRow: View {
    let fan: FanStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fan")
                    .foregroundStyle(.secondary)
                Text(fan.name)
                Spacer()
                Text(fan.isManual ? "Manual" : "Auto")
                    .font(.caption)
                    .foregroundStyle(fan.isManual ? Color.accentColor : .secondary)
                Text("\(Int(fan.actualRPM)) rpm")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            ProgressView(value: fan.actualRPM, total: max(fan.maximumRPM, 1))
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }
}

private struct PresetRow: View {
    let preset: FanPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                Text(preset.name)
                Spacer()
                Text(preset.mode == .fixed ? "\(Int(preset.fixedPercent))%" : preset.mode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ManualFanSlider: View {
    @EnvironmentObject private var model: AppModel
    let fan: FanStatus

    var body: some View {
        let percent = model.manualPercent(for: fan)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(fan.name)
                Spacer()
                Text("\(Int(fan.rpm(forPercent: percent))) rpm")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: Binding(get: { percent }, set: { model.setManual(fan: fan.id, percent: $0) }),
                   in: 0...100)
                .controlSize(.small)
        }
    }
}

private struct TemperatureSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SensorGroup.allCases.filter { $0 != .other }) { group in
                let values = model.sensors.filter { $0.group == group }.map(\.value)
                if let hottest = values.max() {
                    HStack(spacing: 8) {
                        Image(systemName: group.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(group.title)
                        Spacer()
                        Text(model.formatted(values.reduce(0, +) / Double(values.count), decimals: 0))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(model.formatted(hottest, decimals: 0))
                            .monospacedDigit()
                            .foregroundStyle(temperatureColor(hottest))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .font(.callout)
    }
}

struct HelperBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.helperState {
            case .checking:
                Label("Connecting to helper…", systemImage: "hourglass")
            case .notInstalled:
                Label("Fan control needs the helper", systemImage: "lock.shield")
                    .font(.callout.weight(.medium))
                Text("Temperatures work without it. Setting fan speeds needs a small root helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Install Helper…") { model.installHelper() }
            case .outdated(let version):
                Label("Helper v\(version) is outdated", systemImage: "arrow.triangle.2.circlepath")
                Button("Update Helper…") { model.installHelper() }
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Notice: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        Label {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}
