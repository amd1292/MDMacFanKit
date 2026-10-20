import AppKit
import SwiftUI

/// Debug aid: `MDMacFanKit --snapshot <directory>` renders the menu popover and each settings tab to PNG
/// files offscreen and quits. Handy for checking layout and for README screenshots.
enum Snapshot {
    static var directory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    @MainActor
    static func run(into directory: URL) {
        let model = AppModel.shared
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Give the first hardware sample time to arrive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            render(MenuContentView(), name: "menu", width: 320, model: model, into: directory)
            for (index, name) in ["general", "presets", "sensors", "helper"].enumerated() {
                render(SettingsView(selectedTab: index), name: "settings-\(name)", width: 640, model: model,
                       into: directory)
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func render<V: View>(_ view: V, name: String, width: CGFloat, model: AppModel, into directory: URL) {
        let root = view
            .environmentObject(model)
            .environmentObject(model.presets)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        let size = hosting.fittingSize
        window.setContentSize(NSSize(width: max(size.width, width), height: max(size.height, 100)))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}
