import AppKit
import SwiftUI

@main
struct MDMacFanKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(model)
                .environmentObject(model.presets)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("MDMacFanKit Settings", id: SettingsView.windowID) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.presets)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when started with `swift run` outside the .app bundle.
        NSApp.setActivationPolicy(.accessory)
        if let directory = Snapshot.directory {
            MainActor.assumeIsolated { Snapshot.run(into: directory) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let temperature = model.formatted(model.generalTemperature)
        switch model.menuBarStyle {
        case .icon:
            Image(systemName: "fan")
        case .temperature:
            Text(temperature)
        case .iconAndTemperature:
            HStack(spacing: 3) {
                Image(systemName: "fan")
                Text(temperature)
            }
        case .temperatureAndRPM:
            let rpm = model.fans.map(\.actualRPM).max() ?? 0
            Text("\(temperature) \(Int(rpm)) rpm")
        }
    }
}
