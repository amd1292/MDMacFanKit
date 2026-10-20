// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MDMacFanKit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MDMacFanKit", targets: ["MDMacFanKit"]),
        .executable(name: "MDFanHelper", targets: ["MDFanHelper"]),
        .executable(name: "mdfan", targets: ["mdfan"]),
        .library(name: "MDFanCore", targets: ["MDFanCore"]),
    ],
    targets: [
        // Declarations for the private IOHIDEventSystem API used to read named temperature sensors.
        .target(
            name: "CPrivate",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        // SMC access, fan model, sensors and the helper XPC protocol. Shared by every executable.
        .target(
            name: "MDFanCore",
            dependencies: ["CPrivate"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Root LaunchDaemon that performs SMC writes on behalf of the app.
        .executableTarget(name: "MDFanHelper", dependencies: ["MDFanCore"]),
        // Command-line tool for inspecting sensors and testing fan writes.
        .executableTarget(name: "mdfan", dependencies: ["MDFanCore"]),
        // Menu bar app.
        .executableTarget(name: "MDMacFanKit", dependencies: ["MDFanCore"]),
    ]
)
