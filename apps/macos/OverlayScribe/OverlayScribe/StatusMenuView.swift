import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject private var overlayState: OverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Overlay", isOn: $overlayState.overlayEnabled)
                .onChange(of: overlayState.overlayEnabled) { _ in
                    overlayState.applyOverlayState()
                }
                .keyboardShortcut("o", modifiers: [.control, .shift])

            Toggle("Ink Mode", isOn: $overlayState.inkModeEnabled)
                .onChange(of: overlayState.inkModeEnabled) { _ in
                    overlayState.applyOverlayState()
                }
                .keyboardShortcut("i", modifiers: [.control, .shift])

            Toggle("Click-through", isOn: $overlayState.clickthroughEnabled)
                .onChange(of: overlayState.clickthroughEnabled) { _ in
                    overlayState.applyOverlayState()
                }
                .keyboardShortcut("c", modifiers: [.control, .shift])

            Toggle("Toolbox", isOn: $overlayState.toolboxVisible)
                .onChange(of: overlayState.toolboxVisible) { newValue in
                    overlayState.setToolboxVisible(newValue)
                }
                .keyboardShortcut("t", modifiers: [.control, .shift])

            Divider()

            Button("Undo") { overlayState.undo() }
                .keyboardShortcut("z", modifiers: [.control, .shift])

            Button("Redo") { overlayState.redo() }

            Button("Clear") { overlayState.clearAll() }
                .keyboardShortcut("x", modifiers: [.control, .shift])

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
