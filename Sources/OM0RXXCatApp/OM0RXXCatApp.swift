import SwiftUI

@main
struct OM0RXXCatApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task {
                    if model.configuration.launchServersAutomatically {
                        model.start()
                    }
                }
        }
        .windowResizability(.contentMinSize)
    }
}
