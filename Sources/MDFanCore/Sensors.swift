import CPrivate
import Foundation

public enum SensorGroup: String, CaseIterable, Codable, Identifiable {
    case cpu, gpu, soc, ssd, battery, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .soc: return "SoC"
        case .ssd: return "SSD"
        case .battery: return "Battery"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "square.stack.3d.up"
        case .soc: return "memorychip"
        case .ssd: return "internaldrive"
        case .battery: return "battery.75percent"
        case .other: return "thermometer.medium"
        }
    }
}

public struct Sensor: Identifiable, Hashable {
    /// Stable identifier: "smc:<key>" or "hid:<product name>".
    public let id: String
    public let name: String
    public let group: SensorGroup
    public let value: Double
}

/// Reads temperatures from two sources:
/// - SMC `T*` keys of type `flt ` (CPU cores, GPU, battery, SSD, …).
/// - The IOHIDEventSystem temperature services, which carry readable names ("PMU tdie1", "NAND CH0 temp").
/// Neither needs root.
public final class SensorReader {
    /// Readings outside this range are uninitialized or unused SMC slots, not real temperatures.
    public static let plausibleRange = 15.0...125.0

    private let smc: SMC?
    private let smcKeys: [String]
    private let hidClient: IOHIDEventSystemClient?

    public init(smc: SMC?) {
        self.smc = smc
        smcKeys = smc.map { smc in
            smc.allKeys().filter { $0.hasPrefix("T") && (try? smc.keyInfo($0))?.type == "flt " }
        } ?? []

        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let client {
            let matching = [
                "PrimaryUsagePage": kMDHIDPageAppleVendor,
                "PrimaryUsage": kMDHIDUsageTemperatureSensor,
            ] as CFDictionary
            _ = IOHIDEventSystemClientSetMatching(client, matching)
        }
        hidClient = client
    }

    public func read() -> [Sensor] {
        smcSensors() + hidSensors()
    }

    private func smcSensors() -> [Sensor] {
        guard let smc else { return [] }
        return smcKeys.compactMap { key in
            guard let value = try? smc.readValue(key), Self.plausibleRange.contains(value) else { return nil }
            return Sensor(id: "smc:\(key)", name: key, group: Self.group(forSMCKey: key), value: value)
        }
    }

    private func hidSensors() -> [Sensor] {
        guard let hidClient, let services = IOHIDEventSystemClientCopyServices(hidClient) as? [AnyObject] else {
            return []
        }
        // Several services report under the same product name (one per PMU die); average them.
        var readings: [String: [Double]] = [:]
        for object in services {
            let service = unsafeBitCast(object, to: IOHIDServiceClient.self)
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = IOHIDServiceClientCopyEvent(service, Int64(kMDHIDEventTypeTemperature), 0, 0)
            else { continue }
            let value = IOHIDEventGetFloatValue(event, Int32(kMDHIDEventTypeTemperature << 16))
            guard Self.plausibleRange.contains(value), name != "PMU tcal" else { continue }
            readings[name, default: []].append(value)
        }
        return readings.map { name, values in
            Sensor(id: "hid:\(name)", name: name, group: Self.group(forHIDName: name),
                   value: values.reduce(0, +) / Double(values.count))
        }
    }

    private static func group(forSMCKey key: String) -> SensorGroup {
        switch key.prefix(2) {
        // TC* keys are SMC summaries (TCMz mirrors the hottest Tp key); keep them out of CPU averages.
        case "Tp", "Te": return .cpu
        case "Tg", "TG": return .gpu
        case "TB": return .battery
        case "TH": return .ssd
        default: return .other
        }
    }

    private static func group(forHIDName name: String) -> SensorGroup {
        if name.hasPrefix("PMU") || name.hasPrefix("SOC") { return .soc }
        if name.contains("NAND") { return .ssd }
        if name.contains("battery") { return .battery }
        return .other
    }
}

// MARK: - Temperature sources

/// Which temperature drives the menu bar readout or a fan curve.
public enum TemperatureSource: Hashable, RawRepresentable, Codable {
    case cpuMax
    case cpuAverage
    case gpuMax
    case hottest
    case sensor(String)

    public static let aggregates: [TemperatureSource] = [.cpuMax, .cpuAverage, .gpuMax, .hottest]

    public init?(rawValue: String) {
        switch rawValue {
        case "cpuMax": self = .cpuMax
        case "cpuAverage": self = .cpuAverage
        case "gpuMax": self = .gpuMax
        case "hottest": self = .hottest
        default:
            guard rawValue.hasPrefix("sensor:") else { return nil }
            self = .sensor(String(rawValue.dropFirst("sensor:".count)))
        }
    }

    public var rawValue: String {
        switch self {
        case .cpuMax: return "cpuMax"
        case .cpuAverage: return "cpuAverage"
        case .gpuMax: return "gpuMax"
        case .hottest: return "hottest"
        case .sensor(let id): return "sensor:\(id)"
        }
    }

    public func title(sensors: [Sensor] = []) -> String {
        switch self {
        case .cpuMax: return "CPU (hottest core)"
        case .cpuAverage: return "CPU (average)"
        case .gpuMax: return "GPU (hottest)"
        case .hottest: return "Hottest sensor"
        case .sensor(let id):
            guard let sensor = sensors.first(where: { $0.id == id }) else { return id }
            return "\(sensor.group.title) · \(sensor.name)"
        }
    }

    public func value(in sensors: [Sensor]) -> Double? {
        switch self {
        case .cpuMax:
            return Self.values(.cpu, sensors).max() ?? Self.values(.soc, sensors).max()
        case .cpuAverage:
            let cpu = Self.values(.cpu, sensors)
            let values = cpu.isEmpty ? Self.values(.soc, sensors) : cpu
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        case .gpuMax:
            return Self.values(.gpu, sensors).max()
        case .hottest:
            return sensors.map(\.value).max()
        case .sensor(let id):
            return sensors.first { $0.id == id }?.value
        }
    }

    private static func values(_ group: SensorGroup, _ sensors: [Sensor]) -> [Double] {
        sensors.filter { $0.group == group }.map(\.value)
    }
}
