import AppKit
import Foundation
import MDFanCore

/// Talks to the root helper over XPC. All callbacks are delivered on the main queue.
final class HelperClient {
    var onDisconnect: (() -> Void)?

    private var connection: NSXPCConnection?

    func version(timeout: TimeInterval = 2, completion: @escaping (Result<String, Error>) -> Void) {
        var finished = false
        let finish: (Result<String, Error>) -> Void = { result in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(result)
            }
        }
        proxy { finish(.failure($0)) }?.helperVersion { finish(.success($0)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            finish(.failure(HelperError.timeout))
        }
    }

    func setFan(_ index: Int, rpm: Double, completion: @escaping (String?) -> Void) {
        proxy { error in completion(error.localizedDescription) }?
            .setFan(index, targetRPM: rpm) { message in DispatchQueue.main.async { completion(message) } }
    }

    func setFanAutomatic(_ index: Int, completion: @escaping (String?) -> Void) {
        proxy { error in completion(error.localizedDescription) }?
            .setFanAutomatic(index) { message in DispatchQueue.main.async { completion(message) } }
    }

    func heartbeat() {
        proxy { _ in }?.heartbeat {}
    }

    /// Blocks until the helper has restored automatic control. Used while the app terminates.
    func setAllFansAutomaticSynchronously() {
        guard let connection else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as? FanHelperProtocol
        proxy?.setAllFansAutomatic { _ in semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    private func proxy(errorHandler: @escaping (Error) -> Void) -> FanHelperProtocol? {
        let connection = self.connection ?? makeConnection()
        let handler: (Error) -> Void = { error in DispatchQueue.main.async { errorHandler(error) } }
        return connection.remoteObjectProxyWithErrorHandler(handler) as? FanHelperProtocol
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        let dropped = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, self.connection === connection else { return }
                self.connection = nil
                self.onDisconnect?()
            }
        }
        connection.invalidationHandler = dropped
        connection.interruptionHandler = dropped
        connection.resume()
        self.connection = connection
        return connection
    }
}

enum HelperError: LocalizedError {
    case timeout
    case notBundled
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "The helper did not answer."
        case .notBundled: return "Helper files are missing. Build the app with scripts/build-app.sh and run the .app bundle."
        case .cancelled: return "Cancelled."
        case .failed(let message): return message
        }
    }
}

/// Installs or removes the LaunchDaemon with the user's administrator password.
enum HelperInstaller {
    static func install() throws {
        try runPrivileged(script: "install-helper.sh")
    }

    static func uninstall() throws {
        try runPrivileged(script: "uninstall-helper.sh")
    }

    private static func runPrivileged(script name: String) throws {
        guard let resources = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("MDFanHelper").path)
        else { throw HelperError.notBundled }

        let command = "/bin/bash \(shellQuoted(resources.appendingPathComponent(name).path)) \(shellQuoted(resources.path))"
        let source = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if errorInfo[NSAppleScript.errorNumber] as? Int == -128 { throw HelperError.cancelled }
            throw HelperError.failed(errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error.")
        }
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
