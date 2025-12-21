import SwiftUI

@main
struct OverlayScribeApp: App {
    @StateObject private var overlayState = OverlayState()

    var body: some Scene {
        MenuBarExtra(
            "OverlayScribe",
            systemImage: overlayState.effectiveInkModeEnabled ? "pencil.tip.crop.circle.fill" : "pencil.tip"
        ) {
            StatusMenuView()
                .environmentObject(overlayState)
        }
    }
}
