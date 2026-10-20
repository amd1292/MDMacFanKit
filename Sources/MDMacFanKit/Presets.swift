import Foundation
import MDFanCore

struct CurvePoint: Codable, Hashable, Identifiable {
    var id = UUID()
    var temperature: Double
    var percent: Double
}

enum PresetMode: String, Codable, CaseIterable, Identifiable {
    case automatic, fixed, curve

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "System"
        case .fixed: return "Fixed"
        case .curve: return "Curve"
        }
    }
}

struct FanPreset: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var mode: PresetMode
    var fixedPercent: Double = 50
    var source: TemperatureSource = .cpuAverage
    var points: [CurvePoint] = []

    /// Degrees the temperature must fall below the first curve point before handing the fans back to macOS.
    /// Stops the fans flapping between manual and automatic around the threshold.
    static let hysteresis = 3.0

    var sortedPoints: [CurvePoint] { points.sorted { $0.temperature < $1.temperature } }

    /// Fan speed (0–100 % of each fan's range) for a temperature, or nil to leave the fans to macOS.
    /// Below the first point the curve is "off", because manual mode can never go below a fan's minimum
    /// while macOS is free to stop the fans entirely.
    func curvePercent(temperature: Double?, currentlyManual: Bool) -> Double? {
        let points = sortedPoints
        guard let temperature, let first = points.first, let last = points.last else { return nil }
        let threshold = first.temperature - (currentlyManual ? Self.hysteresis : 0)
        if temperature < threshold { return nil }
        if temperature <= first.temperature { return first.percent }
        if temperature >= last.temperature { return last.percent }
        for (lower, upper) in zip(points, points.dropFirst()) where temperature <= upper.temperature {
            let span = upper.temperature - lower.temperature
            guard span > 0 else { return upper.percent }
            return lower.percent + (upper.percent - lower.percent) * (temperature - lower.temperature) / span
        }
        return last.percent
    }
}

extension FanPreset {
    static let systemID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // Thresholds follow the CPU average. Apple Silicon cores routinely sit at 70–80 °C under light load
    // with the fans off, so curves start late; Performance trades noise for lower temperatures.
    static let defaults: [FanPreset] = [
        FanPreset(id: systemID, name: "System (Auto)", mode: .automatic),
        FanPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Silent", mode: .curve,
                  points: [.init(temperature: 80, percent: 0), .init(temperature: 90, percent: 40),
                           .init(temperature: 100, percent: 100)]),
        FanPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Balanced", mode: .curve,
                  points: [.init(temperature: 70, percent: 0), .init(temperature: 80, percent: 35),
                           .init(temperature: 90, percent: 70), .init(temperature: 100, percent: 100)]),
        FanPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Performance", mode: .curve,
                  points: [.init(temperature: 55, percent: 15), .init(temperature: 70, percent: 50),
                           .init(temperature: 85, percent: 100)]),
        FanPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Full Speed", mode: .fixed,
                  fixedPercent: 100),
    ]
}

/// User presets, persisted as JSON in ~/Library/Application Support/MDMacFanKit/presets.json.
@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [FanPreset] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MDMacFanKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("presets.json")

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([FanPreset].self, from: data), !stored.isEmpty {
            presets = stored
        } else {
            presets = FanPreset.defaults
        }
        // The System preset is the safe fallback and always exists.
        if !presets.contains(where: { $0.id == FanPreset.systemID }) {
            presets.insert(FanPreset.defaults[0], at: 0)
        }
    }

    func preset(_ id: UUID) -> FanPreset? {
        presets.first { $0.id == id }
    }

    @discardableResult
    func add(_ preset: FanPreset) -> UUID {
        presets.append(preset)
        return preset.id
    }

    func delete(_ id: UUID) {
        guard id != FanPreset.systemID else { return }
        presets.removeAll { $0.id == id }
    }

    func restoreDefaults() {
        presets = FanPreset.defaults
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
