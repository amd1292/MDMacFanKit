import Foundation

public enum HelperConstants {
    public static let label = "com.mdmacfankit.helper"
    public static let machServiceName = label
    /// Bumped whenever the protocol or helper behavior changes, so the app can ask to reinstall.
    public static let version = "1"
    public static let installedBinaryPath = "/Library/PrivilegedHelperTools/\(label)"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/\(label).plist"
    /// Without a heartbeat for this long, the helper hands every fan back to the system.
    public static let heartbeatTimeout: TimeInterval = 15
}

/// XPC interface of the root helper. Errors come back as a message string; nil means success.
@objc public protocol FanHelperProtocol {
    func helperVersion(withReply reply: @escaping (String) -> Void)
    func setFan(_ index: Int, targetRPM rpm: Double, withReply reply: @escaping (String?) -> Void)
    func setFanAutomatic(_ index: Int, withReply reply: @escaping (String?) -> Void)
    func setAllFansAutomatic(withReply reply: @escaping (String?) -> Void)
    func heartbeat(withReply reply: @escaping () -> Void)
}
