import Foundation
import IOKit

// MARK: - Kernel structures (layout must match AppleSMC's SMCParamStruct, 80 bytes)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private enum SMCSelector: UInt8 {
    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

private let kSMCHandleYPCEvent: UInt32 = 2

// MARK: - Public API

public struct SMCKeyInfo: Hashable {
    public let size: Int
    public let type: String
}

public enum SMCError: Error, LocalizedError {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(String, kern_return_t)
    case keyNotFound(String)
    case smcResult(String, UInt8)
    case unsupportedType(String, String)
    case sizeMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound: return "AppleSMC service not found."
        case .openFailed(let kr): return "Could not open AppleSMC (\(String(format: "0x%08x", kr)))."
        case .callFailed(let key, let kr):
            if kr == kIOReturnNotPrivileged {
                return "Writing \(key) requires root privileges."
            }
            return "SMC call for \(key) failed (\(String(format: "0x%08x", kr)))."
        case .keyNotFound(let key): return "SMC key \(key) does not exist on this Mac."
        case .smcResult(let key, let code): return "SMC rejected \(key) (result \(code))."
        case .unsupportedType(let key, let type): return "SMC key \(key) has unsupported type '\(type)'."
        case .sizeMismatch(let key): return "Wrong data size for SMC key \(key)."
        }
    }
}

/// A connection to the System Management Controller. Reading works for any user; writing requires root.
/// Thread-safe: every call is serialized by an internal lock.
public final class SMC {
    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: SMCKeyInfo] = [:]
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { throw SMCError.openFailed(kr) }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        lock.lock(); defer { lock.unlock() }
        return try keyInfoLocked(key)
    }

    public func read(_ key: String) throws -> (info: SMCKeyInfo, bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = SMCSelector.readBytes.rawValue
        let output = try call(&input, key: key)
        guard output.result == 0 else { throw SMCError.smcResult(key, output.result) }
        var bytes = output.bytes
        let data = withUnsafeBytes(of: &bytes) { Array($0.prefix(min(info.size, 32))) }
        return (info, data)
    }

    public func readValue(_ key: String) throws -> Double {
        let (info, bytes) = try read(key)
        return try SMCValue.decode(bytes, type: info.type, key: key)
    }

    public func write(_ key: String, bytes: [UInt8]) throws {
        lock.lock(); defer { lock.unlock() }
        let info = try keyInfoLocked(key)
        guard bytes.count == info.size else { throw SMCError.sizeMismatch(key) }
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.dataSize = UInt32(info.size)
        input.data8 = SMCSelector.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        let output = try call(&input, key: key)
        guard output.result == 0 else { throw SMCError.smcResult(key, output.result) }
    }

    /// Encodes `value` using the key's own SMC data type and writes it.
    public func write(_ key: String, value: Double) throws {
        let info = try keyInfo(key)
        try write(key, bytes: SMCValue.encode(value, type: info.type, size: info.size, key: key))
    }

    public func hasKey(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    /// Every key the SMC exposes, in index order.
    public func allKeys() -> [String] {
        guard let count = try? readValue("#KEY") else { return [] }
        lock.lock(); defer { lock.unlock() }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<UInt32(count) {
            var input = SMCParamStruct()
            input.data8 = SMCSelector.readIndex.rawValue
            input.data32 = index
            guard let output = try? call(&input, key: "#\(index)"), output.result == 0 else { continue }
            keys.append(fourCCString(output.key))
        }
        return keys
    }

    // MARK: Private

    private func keyInfoLocked(_ key: String) throws -> SMCKeyInfo {
        let code = fourCC(key)
        if let cached = infoCache[code] { return cached }
        var input = SMCParamStruct()
        input.key = code
        input.data8 = SMCSelector.readKeyInfo.rawValue
        let output = try call(&input, key: key)
        guard output.result == 0, output.keyInfo.dataSize > 0 else { throw SMCError.keyNotFound(key) }
        let info = SMCKeyInfo(size: Int(output.keyInfo.dataSize), type: fourCCString(output.keyInfo.dataType))
        infoCache[code] = info
        return info
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, kSMCHandleYPCEvent,
                                           &input, MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outputSize)
        guard kr == KERN_SUCCESS else { throw SMCError.callFailed(key, kr) }
        return output
    }
}

// MARK: - Value coding

enum SMCValue {
    static func decode(_ bytes: [UInt8], type: String, key: String) throws -> Double {
        switch type {
        case "flt ":
            guard bytes.count == 4 else { throw SMCError.sizeMismatch(key) }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 ", "flag":
            return Double(bytes.first ?? 0)
        case "ui16":
            return Double(bigEndian(bytes, count: 2))
        case "ui32":
            return Double(bigEndian(bytes, count: 4))
        case "sp78":
            return Double(Int16(bitPattern: UInt16(bigEndian(bytes, count: 2)))) / 256
        case "fpe2":
            return Double(bigEndian(bytes, count: 2)) / 4
        default:
            throw SMCError.unsupportedType(key, type)
        }
    }

    static func encode(_ value: Double, type: String, size: Int, key: String) throws -> [UInt8] {
        switch type {
        case "flt ":
            return withUnsafeBytes(of: Float(value)) { Array($0) }
        case "ui8 ", "flag":
            return [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            let v = UInt16(clamping: Int(value.rounded()))
            return [UInt8(v >> 8), UInt8(v & 0xff)]
        case "ui32":
            let v = UInt32(clamping: Int(value.rounded()))
            return [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        case "fpe2":
            let v = UInt16(clamping: Int((value * 4).rounded()))
            return [UInt8(v >> 8), UInt8(v & 0xff)]
        default:
            throw SMCError.unsupportedType(key, type)
        }
    }

    private static func bigEndian(_ bytes: [UInt8], count: Int) -> UInt32 {
        bytes.prefix(count).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    }
}

func fourCC(_ string: String) -> UInt32 {
    string.utf8.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
}

func fourCCString(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xff) }
    return String(decoding: bytes, as: UTF8.self)
}
