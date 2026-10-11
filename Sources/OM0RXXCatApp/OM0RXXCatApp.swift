import AppKit
import SwiftUI

@MainActor
enum MainConfigurationWindow {
    static let identifier = NSUserInterfaceItemIdentifier("OM0RXMainConfigurationWindow")

    static func configure(_ window: NSWindow) {
        window.identifier = identifier
        window.setFrameAutosaveName("OM0RXMainConfigurationWindow")
    }

    static func restore(in application: NSApplication = .shared) {
        application.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            guard let window = application.windows.first(where: { $0.identifier == identifier })
                    ?? application.windows.first(where: { $0.title == "OM0RX-xCat" }) else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { configure(nsView) }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            MainConfigurationWindow.configure(window)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainConfigurationWindow.restore(in: sender)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { @MainActor in
            await model.stopAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct OM0RXXCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .background { MainWindowConfigurator() }
                .task {
                    appDelegate.model = model
                    if model.configuration.launchServersAutomatically {
                        model.start()
                    } else {
                        model.startRotatorIfNeeded()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 620)

        Window("OM0RX Station Monitor", id: "station-monitor") {
            MenuBarView(allowsUndocking: false, isDetached: true)
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 979, height: 540)
    }
}
