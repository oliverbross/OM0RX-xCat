import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var terminationPending = false

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
        .defaultSize(width: 903, height: 420)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Label("OM0RX-xCat", systemImage: model.isStationReady
                  ? "antenna.radiowaves.left.and.right"
                  : "exclamationmark.triangle")
        }
        .menuBarExtraStyle(.window)
    }
}
