import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject private var overlayState: OverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Overlay", isOn: $overlayState.overlayEnabled)
                .onChange(of: overlayState.overlayEnabled) { _ in
                    overlayState.applyOverlayState()
                }

            Toggle("Ink Mode", isOn: $overlayState.inkModeEnabled)
                .onChange(of: overlayState.inkModeEnabled) { _ in
                    overlayState.applyOverlayState()
                }

            Toggle("Toolbox", isOn: $overlayState.toolboxVisible)
                .onChange(of: overlayState.toolboxVisible) { newValue in
                    overlayState.setToolboxVisible(newValue)
                }

            Divider()

            Picker("Tool", selection: $overlayState.selectedTool) {
                Text("Pen").tag(OverlayState.Tool.pen)
                Text("Eraser").tag(OverlayState.Tool.eraser)
                Divider()
                Text("Rectangle").tag(OverlayState.Tool.rectangle)
                Text("Rounded Rect").tag(OverlayState.Tool.roundedRectangle)
                Text("Ellipse").tag(OverlayState.Tool.ellipse)
                Text("Arrow").tag(OverlayState.Tool.arrow)
                Text("Curved Arrow").tag(OverlayState.Tool.curvedArrow)
            }
            .pickerStyle(.menu)
            .onChange(of: overlayState.selectedTool) { _ in
                overlayState.applyOverlayState()
            }

            HStack {
                Text("Width")
                Slider(value: $overlayState.penWidth, in: 2...14, step: 1)
                    .frame(width: 140)
                Text("\(Int(overlayState.penWidth))")
                    .frame(width: 24, alignment: .trailing)
            }
            .onChange(of: overlayState.penWidth) { _ in
                overlayState.applyOverlayState()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                HStack(spacing: 8) {
                    ForEach(overlayState.palette) { item in
                        Button {
                            overlayState.selectedColor = item.color
                            overlayState.applyOverlayState()
                        } label: {
                            Circle()
                                .fill(Color(nsColor: item.color))
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            Color.primary.opacity(item.color == overlayState.selectedColor ? 0.9 : 0.2),
                                            lineWidth: item.color == overlayState.selectedColor ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
            }

            Divider()

            HStack {
                Button("Undo") { overlayState.undo() }
                Button("Redo") { overlayState.redo() }
                Button("Clear") { overlayState.clearAll() }
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
    }
}
