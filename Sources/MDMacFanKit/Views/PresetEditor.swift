import Charts
import MDFanCore
import SwiftUI

struct PresetEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var preset: FanPreset

    private var isSystem: Bool { preset.id == FanPreset.systemID }

    // A plain ScrollView instead of a grouped Form: Form rows squeeze sliders to nothing and report
    // an ideal width wider than the settings window.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Name") { TextField("Name", text: $preset.name).labelsHidden() }
                        row("Mode") {
                            Picker("Mode", selection: $preset.mode) {
                                ForEach(PresetMode.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .disabled(isSystem)
                        }
                    }
                    .padding(6)
                }

                switch preset.mode {
                case .automatic:
                    caption("macOS controls the fans. On Apple Silicon they often stay off while the Mac is cool.")
                case .fixed:
                    fixedSection
                case .curve:
                    curveSections
                }

                HStack {
                    Spacer()
                    Button("Use This Preset") { model.select(preset: preset.id) }
                        .disabled(model.activePreset?.id == preset.id)
                }
            }
            .padding(20)
        }
    }

    private var fixedSection: some View {
        GroupBox("Speed") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Slider(value: $preset.fixedPercent, in: 0...100)
                    Text("\(Int(preset.fixedPercent))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                ForEach(model.fans) { fan in
                    HStack {
                        Text(fan.name)
                        Spacer()
                        Text("\(Int(fan.rpm(forPercent: preset.fixedPercent))) rpm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                caption("0% is each fan's minimum speed, 100% its maximum. Manual speeds can't go below the minimum.")
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var curveSections: some View {
        let current = preset.source.value(in: model.sensors)
        GroupBox("Curve") {
            VStack(alignment: .leading, spacing: 10) {
                row("Follow") {
                    TemperatureSourcePicker(title: "Follow", selection: $preset.source)
                        .labelsHidden()
                }
                CurveChart(points: preset.sortedPoints, current: current,
                           currentPercent: preset.curvePercent(temperature: current, currentlyManual: false))
                    .frame(height: 170)
                caption("Below the first point the fans are left to macOS, so they can still stop when the Mac is cool.")
            }
            .padding(6)
        }
        GroupBox("Points") {
            VStack(spacing: 8) {
                ForEach($preset.points) { $point in
                    HStack(spacing: 10) {
                        Text("\(Int(point.temperature)) °C")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .leading)
                        Stepper("Temperature", value: $point.temperature, in: 20...110, step: 1)
                            .labelsHidden()
                        Slider(value: $point.percent, in: 0...100)
                        Text("\(Int(point.percent))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                        Button {
                            preset.points.removeAll { $0.id == point.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(preset.points.count <= 1)
                    }
                }
                HStack {
                    Button("Add Point") { addPoint() }
                    Spacer()
                    Button("Sort") { preset.points = preset.sortedPoints }
                }
            }
            .padding(6)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 60, alignment: .leading)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addPoint() {
        let last = preset.sortedPoints.last
        let temperature = min((last?.temperature ?? 50) + 10, 110)
        preset.points.append(CurvePoint(temperature: temperature, percent: min((last?.percent ?? 0) + 20, 100)))
    }
}

private struct CurveChart: View {
    let points: [CurvePoint]
    let current: Double?
    let currentPercent: Double?

    var body: some View {
        Chart {
            if let first = points.first {
                // Below the first point macOS is in charge; draw that stretch as a dashed baseline.
                RuleMark(xStart: .value("From", 20), xEnd: .value("To", first.temperature), y: .value("Auto", 0))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(points) { point in
                AreaMark(x: .value("Temperature", point.temperature), y: .value("Speed", point.percent))
                    .foregroundStyle(Color.accentColor.opacity(0.15))
                LineMark(x: .value("Temperature", point.temperature), y: .value("Speed", point.percent))
                    .foregroundStyle(Color.accentColor)
                PointMark(x: .value("Temperature", point.temperature), y: .value("Speed", point.percent))
                    .foregroundStyle(Color.accentColor)
            }
            if let last = points.last, last.temperature < 110 {
                RuleMark(xStart: .value("From", last.temperature), xEnd: .value("To", 110),
                         y: .value("Max", last.percent))
                    .foregroundStyle(Color.accentColor)
            }
            if let current {
                RuleMark(x: .value("Now", min(max(current, 20), 110)))
                    .foregroundStyle(.orange)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(Int(current))° → \(currentPercent.map { "\(Int($0))%" } ?? "auto")")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
            }
        }
        .chartXScale(domain: 20...110)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("°C")
        .chartYAxisLabel("%")
    }
}
