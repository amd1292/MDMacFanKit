import Foundation

public struct FanStatus: Identifiable, Hashable, Codable {
    public let id: Int
    public let actualRPM: Double
    public let minimumRPM: Double
    public let maximumRPM: Double
    public let targetRPM: Double
    public let isManual: Bool

    public var name: String { "Fan \(id + 1)" }

    /// Maps 0–100 % onto this fan's own [minimum, maximum] range.
    public func rpm(forPercent percent: Double) -> Double {
        let clamped = min(max(percent, 0), 100)
        return minimumRPM + (maximumRPM - minimumRPM) * clamped / 100
    }

    /// Where the actual speed sits within [minimum, maximum], 0 when the fan is stopped.
    public var percent: Double {
        guard maximumRPM > minimumRPM, actualRPM > 0 else { return 0 }
        return min(max((actualRPM - minimumRPM) / (maximumRPM - minimumRPM) * 100, 0), 100)
    }
}

extension SMC {
    public func fanCount() -> Int {
        Int((try? readValue("FNum")) ?? 0)
    }

    public func fanStatus(_ index: Int) -> FanStatus? {
        guard let maximum = try? readValue("F\(index)Mx") else { return nil }
        return FanStatus(
            id: index,
            actualRPM: max((try? readValue("F\(index)Ac")) ?? 0, 0),
            minimumRPM: (try? readValue("F\(index)Mn")) ?? 0,
            maximumRPM: maximum,
            targetRPM: (try? readValue("F\(index)Tg")) ?? 0,
            isManual: isFanManual(index)
        )
    }

    public func fans() -> [FanStatus] {
        (0..<fanCount()).compactMap(fanStatus)
    }

    public func isFanManual(_ index: Int) -> Bool {
        if hasKey("F\(index)Md") {
            return ((try? readValue("F\(index)Md")) ?? 0) == 1
        }
        // Older Intel Macs: one bit per fan in "FS! ".
        let mask = Int((try? readValue("FS! ")) ?? 0)
        return mask & (1 << index) != 0
    }

    // MARK: Privileged (root only)

    /// Switches a fan to manual mode and sets its target speed. The RPM is clamped to the fan's own limits.
    public func setFanManual(_ index: Int, rpm: Double) throws {
        guard let fan = fanStatus(index) else { throw SMCError.keyNotFound("F\(index)Mx") }
        let target = min(max(rpm, fan.minimumRPM), fan.maximumRPM)
        try setManualFlag(index, manual: true)
        try write("F\(index)Tg", value: target)
    }

    /// Hands a fan back to the system's automatic control.
    public func setFanAutomatic(_ index: Int) throws {
        try setManualFlag(index, manual: false)
    }

    private func setManualFlag(_ index: Int, manual: Bool) throws {
        if hasKey("F\(index)Md") {
            try write("F\(index)Md", value: manual ? 1 : 0)
        } else {
            let mask = Int((try? readValue("FS! ")) ?? 0)
            let updated = manual ? mask | (1 << index) : mask & ~(1 << index)
            try write("FS! ", value: Double(updated))
        }
    }
}
