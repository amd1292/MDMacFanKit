import Foundation
import MDFanCore
import os

let log = Logger(subsystem: HelperConstants.label, category: "helper")

// Root LaunchDaemon. Owns every SMC write and is deliberately conservative:
// - all fans go back to automatic on launch, on SIGTERM, when the last client disconnects,
//   and when no heartbeat arrives within HelperConstants.heartbeatTimeout;
// - targets are clamped to each fan's own min/max inside SMC.setFanManual.

final class FanService: NSObject, FanHelperProtocol {
    private let smc: SMC
    private let queue = DispatchQueue(label: "mdfan.helper.state")
    private var manualTargets: [Int: Double] = [:]
    private var lastHeartbeat = Date()
    private var clientCount = 0
    private var timer: DispatchSourceTimer?

    init(smc: SMC) {
        self.smc = smc
        super.init()
    }

    func start() {
        queue.sync { _ = restoreAllLocked(reason: "helper start") }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.maintainLocked() }
        timer.resume()
        self.timer = timer
    }

    func clientConnected() {
        queue.async { self.clientCount += 1; self.lastHeartbeat = Date() }
    }

    func clientDisconnected() {
        queue.async {
            self.clientCount = max(self.clientCount - 1, 0)
            if self.clientCount == 0 { self.restoreAllLocked(reason: "last client disconnected") }
        }
    }

    func shutdown() {
        queue.sync { _ = restoreAllLocked(reason: "helper stopping") }
    }

    // MARK: FanHelperProtocol

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply(HelperConstants.version)
    }

    func setFan(_ index: Int, targetRPM rpm: Double, withReply reply: @escaping (String?) -> Void) {
        queue.async {
            guard index >= 0, index < self.smc.fanCount(), rpm.isFinite else {
                return reply("Invalid fan \(index).")
            }
            do {
                try self.smc.setFanManual(index, rpm: rpm)
                self.manualTargets[index] = rpm
                self.lastHeartbeat = Date()
                reply(nil)
            } catch {
                log.error("Set fan \(index, privacy: .public) to \(Int(rpm), privacy: .public) rpm failed: \(error.localizedDescription, privacy: .public)")
                reply(error.localizedDescription)
            }
        }
    }

    func setFanAutomatic(_ index: Int, withReply reply: @escaping (String?) -> Void) {
        queue.async {
            do {
                try self.smc.setFanAutomatic(index)
                self.manualTargets[index] = nil
                reply(nil)
            } catch {
                reply(error.localizedDescription)
            }
        }
    }

    func setAllFansAutomatic(withReply reply: @escaping (String?) -> Void) {
        queue.async {
            reply(self.restoreAllLocked(reason: "client request"))
        }
    }

    func heartbeat(withReply reply: @escaping () -> Void) {
        queue.async {
            self.lastHeartbeat = Date()
            reply()
        }
    }

    // MARK: Private (call on `queue` only)

    @discardableResult
    private func restoreAllLocked(reason: String) -> String? {
        var failure: String?
        for index in 0..<smc.fanCount() {
            do { try smc.setFanAutomatic(index) } catch { failure = error.localizedDescription }
        }
        if !manualTargets.isEmpty { log.notice("Fans back to automatic (\(reason, privacy: .public))") }
        manualTargets.removeAll()
        return failure
    }

    private func maintainLocked() {
        guard !manualTargets.isEmpty else { return }
        if Date().timeIntervalSince(lastHeartbeat) > HelperConstants.heartbeatTimeout {
            restoreAllLocked(reason: "heartbeat timeout")
            return
        }
        // macOS may take a fan back (thermal daemon, sleep/wake). Re-assert our targets when it does.
        for (index, rpm) in manualTargets {
            let target = (try? smc.readValue("F\(index)Tg")) ?? 0
            if !smc.isFanManual(index) || abs(target - rpm) > 1 {
                try? smc.setFanManual(index, rpm: rpm)
            }
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service: FanService

    init(service: FanService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.exportedObject = service
        var finished = false
        let ended = { [service] in
            // Interruption and invalidation can both fire for one connection.
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                service.clientDisconnected()
            }
        }
        connection.invalidationHandler = ended
        connection.interruptionHandler = ended
        service.clientConnected()
        connection.resume()
        return true
    }
}

guard getuid() == 0 else {
    FileHandle.standardError.write("MDFanHelper must run as root (it is installed as a LaunchDaemon).\n".data(using: .utf8)!)
    exit(1)
}

let smc: SMC
do {
    smc = try SMC()
} catch {
    log.fault("\(error.localizedDescription, privacy: .public)")
    exit(1)
}

let service = FanService(smc: smc)
service.start()

let delegate = ListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    service.shutdown()
    exit(0)
}
termination.resume()

log.notice("MDFanHelper \(HelperConstants.version, privacy: .public) started with \(smc.fanCount(), privacy: .public) fans")
dispatchMain()
