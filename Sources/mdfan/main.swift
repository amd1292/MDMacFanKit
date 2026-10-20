import Foundation
import MDFanCore

// Small CLI for inspecting the hardware and testing fan writes without the app or helper.
// Writes talk to the SMC directly, so they need sudo.

let usage = """
usage: mdfan <command>

  fans                 list fans (speed, limits, mode)
  temps                list temperature sensors
  read <KEY>           read a raw SMC key, e.g. read F0Ac
  set <fan> <rpm>      put a fan in manual mode at <rpm>        (sudo)
  auto [fan]           give one fan, or all fans, back to macOS  (sudo)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { print(usage); exit(0) }

let smc: SMC
do { smc = try SMC() } catch { fail(error.localizedDescription) }

func printFans() {
    let fans = smc.fans()
    if fans.isEmpty { print("No fans found.") }
    for fan in fans {
        print(String(format: "%@  %5.0f rpm  (min %4.0f, max %4.0f, target %4.0f)  %@",
                     fan.name, fan.actualRPM, fan.minimumRPM, fan.maximumRPM, fan.targetRPM,
                     fan.isManual ? "MANUAL" : "auto"))
    }
}

switch command {
case "fans":
    printFans()

case "temps":
    let sensors = SensorReader(smc: smc).read()
    for group in SensorGroup.allCases {
        let members = sensors.filter { $0.group == group }.sorted { $0.name < $1.name }
        guard !members.isEmpty else { continue }
        print("\n\(group.title)")
        for sensor in members { print(String(format: "  %-24@ %5.1f °C", sensor.name as NSString, sensor.value)) }
    }
    for source in TemperatureSource.aggregates {
        if let value = source.value(in: sensors) { print(String(format: "\n%@: %.1f °C", source.title(), value)) }
    }

case "read":
    guard arguments.count == 2 else { fail(usage) }
    do {
        let (info, bytes) = try smc.read(arguments[1])
        let value = (try? smc.readValue(arguments[1])).map { String($0) } ?? "-"
        print("\(arguments[1])  type '\(info.type)'  size \(info.size)  bytes \(bytes)  value \(value)")
    } catch { fail(error.localizedDescription) }

case "set":
    guard arguments.count == 3, let fan = Int(arguments[1]), let rpm = Double(arguments[2]) else { fail(usage) }
    do { try smc.setFanManual(fan, rpm: rpm) } catch { fail(error.localizedDescription) }
    print("Fan \(fan + 1) set to manual, target \(Int(rpm)) rpm. Run `sudo mdfan auto` to restore.")
    Thread.sleep(forTimeInterval: 3)
    printFans()

case "auto":
    let indices = arguments.count > 1 ? [Int(arguments[1]) ?? -1] : Array(0..<smc.fanCount())
    do { try indices.forEach(smc.setFanAutomatic) } catch { fail(error.localizedDescription) }
    printFans()

default:
    fail(usage)
}
