import SwiftUI

@main
struct OverlayScribeApp: App {
    @StateObject private var overlayState = OverlayState()

    var body: some Scene {
        MenuBarExtra("OverlayScribe", systemImage: "pencil.tip") {
            StatusMenuView()
                .environmentObject(overlayState)
        }
    }
}
