import AppKit
import Foundation
import MDFanCore
import ServiceManagement

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, temperature, iconAndTemperature, temperatureAndRPM

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: return "Icon only"
        case .temperature: return "Temperature"
        case .iconAndTemperature: return "Icon + temperature"
        case .temperatureAndRPM: return "Temperature + fan speed"
        }
    }
}

enum HelperState: Equatable {
    case checking
    case notInstalled
    case outdated(String)
    case ready

    var isReady: Bool { self == .ready }
}

enum ControlMode: Equatable {
    case preset(UUID)
    /// Per-fan percentages set with the manual sliders. Fans without an entry stay automatic.
    case manual([Int: Double])
}

/// What the app last asked the helper to do with a fan.
private enum FanCommand: Equatable {
    case automatic
    case rpm(Double)

    var isManual: Bool { if case .rpm = self { return true } else { return false } }

    func isClose(to other: FanCommand?) -> Bool {
        switch (self, other) {
        case (.automatic, .automatic?): return true
        case (.rpm(let a), .rpm(let b)?): return abs(a - b) < 25
        default: return false
        }
    }
}

/// Samples the hardware off the main thread. Reading never needs root.
final class HardwareMonitor {
    private let queue = DispatchQueue(label: "mdmacfankit.hardware")
    private var smc: SMC?
    private var reader: SensorReader?

    init() {
        queue.async {
            self.smc = try? SMC()
            self.reader = SensorReader(smc: self.smc)
        }
    }

    func sample(completion: @escaping ([FanStatus], [Sensor]) -> Void) {
        queue.async {
            let fans = self.smc?.fans() ?? []
            let sensors = self.reader?.read() ?? []
            DispatchQueue.main.async { completion(fans, sensors) }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var fans: [FanStatus] = []
    @Published private(set) var sensors: [Sensor] = []
    @Published private(set) var helperState: HelperState = .checking
    @Published private(set) var control: ControlMode
    @Published private(set) var conflictingAppRunning = false
    @Published var lastError: String?

    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }
    @Published var generalSource: TemperatureSource {
        didSet { defaults.set(generalSource.rawValue, forKey: Keys.generalSource) }
    }
    @Published var useFahrenheit: Bool {
        didSet { defaults.set(useFahrenheit, forKey: Keys.useFahrenheit) }
    }
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval); startTimer() }
    }

    let presets = PresetStore()

    private let defaults = UserDefaults.standard
    private let monitor = HardwareMonitor()
    private let helper = HelperClient()
    private var timer: Timer?
    private var lastSent: [Int: FanCommand] = [:]
    private var tick = 0

    private enum Keys {
        static let menuBarStyle = "menuBarStyle"
        static let generalSource = "generalSource"
        static let useFahrenheit = "useFahrenheit"
        static let refreshInterval = "refreshInterval"
        static let activePreset = "activePreset"
    }

    private init() {
        menuBarStyle = defaults.string(forKey: Keys.menuBarStyle).flatMap(MenuBarStyle.init) ?? .iconAndTemperature
        generalSource = defaults.string(forKey: Keys.generalSource).flatMap(TemperatureSource.init) ?? .cpuAverage
        useFahrenheit = defaults.bool(forKey: Keys.useFahrenheit)
        let interval = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = interval > 0 ? interval : 2
        let stored = defaults.string(forKey: Keys.activePreset).flatMap(UUID.init) ?? FanPreset.systemID
        control = .preset(stored)
        if presets.preset(stored) == nil { control = .preset(FanPreset.systemID) }

        helper.onDisconnect = { [weak self] in
            guard let self else { return }
            self.lastSent.removeAll()
            // A missing helper also invalidates the connection; keep showing "not installed" in that case.
            if self.helperState.isReady { self.helperState = .checking }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The SMC can reset fan modes across sleep; resend everything.
            Task { @MainActor in
                self?.lastSent.removeAll()
                self?.refresh()
            }
        }

        checkHelper()
        startTimer()
        refresh()
    }

    // MARK: Derived values

    var generalTemperature: Double? { generalSource.value(in: sensors) }

    var activePreset: FanPreset? {
        if case .preset(let id) = control { return presets.preset(id) }
        return nil
    }

    var controlTitle: String {
        switch control {
        case .preset: return activePreset?.name ?? "System (Auto)"
        case .manual: return "Manual"
        }
    }

    func formatted(_ celsius: Double?, decimals: Int = 0, unit: Bool = false) -> String {
        guard let celsius else { return "--°" }
        let value = useFahrenheit ? celsius * 9 / 5 + 32 : celsius
        let suffix = unit ? (useFahrenheit ? "°F" : "°C") : "°"
        return String(format: "%.\(decimals)f", value) + suffix
    }

    // MARK: Control

    func select(preset id: UUID) {
        control = .preset(id)
        defaults.set(id.uuidString, forKey: Keys.activePreset)
        applyControl()
    }

    func manualPercent(for fan: FanStatus) -> Double {
        if case .manual(let values) = control, let percent = values[fan.id] { return percent }
        return fan.percent
    }

    func setManual(fan: Int, percent: Double) {
        var values: [Int: Double] = [:]
        if case .manual(let current) = control { values = current }
        values[fan] = percent
        control = .manual(values)
        applyControl()
    }

    // MARK: Helper

    func checkHelper() {
        helper.version { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let version):
                self.helperState = version == HelperConstants.version ? .ready : .outdated(version)
                if self.helperState.isReady { self.applyControl() }
            case .failure:
                self.helperState = .notInstalled
            }
        }
    }

    func installHelper() {
        do {
            helper.disconnect()
            try HelperInstaller.install()
            lastError = nil
            helperState = .checking
            lastSent.removeAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkHelper() }
        } catch HelperError.cancelled {
        } catch {
            lastError = error.localizedDescription
        }
    }

    func uninstallHelper() {
        do {
            helper.disconnect()
            try HelperInstaller.uninstall()
            helperState = .notInstalled
        } catch HelperError.cancelled {
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called from applicationWillTerminate: hand the fans back to macOS before exiting.
    func shutdown() {
        guard helperState.isReady else { return }
        helper.setAllFansAutomaticSynchronously()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    // MARK: Loop

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = refreshInterval * 0.2
        // Keep sampling while a menu, picker or slider is tracking.
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func refresh() {
        monitor.sample { [weak self] fans, sensors in
            guard let self else { return }
            self.fans = fans
            self.sensors = sensors
            self.tick += 1
            self.applyControl()
            if self.helperState.isReady {
                self.helper.heartbeat()
            } else if self.tick % 5 == 0 {
                self.checkHelper()
            }
            if self.tick % 5 == 1 {
                self.conflictingAppRunning = !NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.crystalidea.macsfancontrol").isEmpty
            }
        }
    }

    private func applyControl() {
        guard helperState.isReady else { return }
        for fan in fans {
            let command = desiredCommand(for: fan)
            guard !command.isClose(to: lastSent[fan.id]) else { continue }
            lastSent[fan.id] = command
            let done: (String?) -> Void = { [weak self] error in
                guard let self, let error else { return }
                self.lastError = error
                self.lastSent[fan.id] = nil  // retry on the next tick
            }
            switch command {
            case .automatic: helper.setFanAutomatic(fan.id, completion: done)
            case .rpm(let rpm): helper.setFan(fan.id, rpm: rpm, completion: done)
            }
        }
    }

    private func desiredCommand(for fan: FanStatus) -> FanCommand {
        switch control {
        case .manual(let values):
            guard let percent = values[fan.id] else { return .automatic }
            return .rpm(fan.rpm(forPercent: percent))
        case .preset(let id):
            guard let preset = presets.preset(id) else { return .automatic }
            switch preset.mode {
            case .automatic:
                return .automatic
            case .fixed:
                return .rpm(fan.rpm(forPercent: preset.fixedPercent))
            case .curve:
                let temperature = preset.source.value(in: sensors)
                let manual = lastSent[fan.id]?.isManual ?? false
                guard let percent = preset.curvePercent(temperature: temperature, currentlyManual: manual) else {
                    return .automatic
                }
                return .rpm(fan.rpm(forPercent: percent))
            }
        }
    }
}
