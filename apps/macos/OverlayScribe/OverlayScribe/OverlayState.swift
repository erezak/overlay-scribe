import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    enum Tool: String, CaseIterable {
        case pen
        case eraser
        case rectangle
        case roundedRectangle
        case ellipse
        case arrow
        case curvedArrow
    }

    struct PaletteColor: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let color: NSColor
    }

    @Published var overlayEnabled: Bool = false
    @Published var inkModeEnabled: Bool = false
    @Published var selectedTool: Tool = .pen

    @Published var toolboxVisible: Bool = false

    @Published var penWidth: CGFloat = 4
    @Published var selectedColor: NSColor = .systemRed

    // Shape styling
    @Published var shapeFillEnabled: Bool = true
    @Published var shapeFillColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.35)
    @Published var shapeHatchEnabled: Bool = false
    @Published var shapeCornerRadius: CGFloat = 18

    let palette: [PaletteColor] = [
        .init(name: "Red", color: .systemRed),
        .init(name: "Orange", color: .systemOrange),
        .init(name: "Yellow", color: .systemYellow),
        .init(name: "Green", color: .systemGreen),
        .init(name: "Blue", color: .systemBlue),
        .init(name: "Purple", color: .systemPurple),
    ]

    let windowManager = OverlayWindowManager()
    private let hotkeyManager = HotkeyManager()
    private let toolboxController = ToolboxPanelController()

    init() {
        hotkeyManager.onToggleOverlay = { [weak self] in
            Task { @MainActor in self?.toggleOverlay() }
        }
        hotkeyManager.onToggleMode = { [weak self] in
            Task { @MainActor in self?.toggleInkMode() }
        }
        hotkeyManager.onExitInkMode = { [weak self] in
            Task { @MainActor in self?.disableInkMode() }
        }
        hotkeyManager.onUndo = { [weak self] in
            Task { @MainActor in self?.undo() }
        }
        hotkeyManager.onClear = { [weak self] in
            Task { @MainActor in self?.clearAll() }
        }
        hotkeyManager.onToggleToolbox = { [weak self] in
            Task { @MainActor in self?.toggleToolbox() }
        }

        hotkeyManager.start()
    }

    func toggleOverlay() {
        overlayEnabled.toggle()
        applyOverlayState()
    }

    func toggleInkMode() {
        inkModeEnabled.toggle()
        applyOverlayState()
    }

    func disableInkMode() {
        inkModeEnabled = false
        applyOverlayState()
    }

    func toggleToolbox() {
        toolboxVisible.toggle()
        applyToolboxVisibility()
    }

    func setToolboxVisible(_ visible: Bool) {
        toolboxVisible = visible
        applyToolboxVisibility()
    }

    func applyToolboxVisibility() {
        if toolboxVisible {
            toolboxController.show(overlayState: self)
        } else {
            toolboxController.hide()
        }
    }

    func clearAll() {
        windowManager.clearAll()
    }

    func undo() {
        windowManager.undo()
    }

    func redo() {
        windowManager.redo()
    }

    func applyOverlayState() {
        if overlayEnabled {
            windowManager.showOverlays()
        } else {
            windowManager.hideOverlays()
        }

        windowManager.setInkModeEnabled(inkModeEnabled)
        windowManager.setTool(selectedTool)
        windowManager.setPenWidth(penWidth)
        windowManager.setColor(selectedColor)
        windowManager.setShapeFillEnabled(shapeFillEnabled)
        windowManager.setShapeFillColor(shapeFillColor)
        windowManager.setShapeHatchEnabled(shapeHatchEnabled)
        windowManager.setShapeCornerRadius(shapeCornerRadius)
    }
}

@MainActor
private final class ToolboxPanelController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?

    func show(overlayState: OverlayState) {
        if panel == nil {
            let view = AnyView(ToolboxView().environmentObject(overlayState))
            let hosting = NSHostingView(rootView: view)
            self.hosting = hosting

            let panel = NSPanel(
                contentRect: NSRect(x: 80, y: 80, width: 320, height: 220),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
            panel.isOpaque = false

            hosting.frame = panel.contentView?.bounds ?? panel.frame
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            self.panel = panel
        } else {
            // Refresh environment object if the state object was recreated.
            hosting?.rootView = AnyView(ToolboxView().environmentObject(overlayState))
        }

        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct ToolboxView: View {
    @EnvironmentObject private var overlayState: OverlayState

    private var toolButtons: [(String, OverlayState.Tool)] {
        [
            ("Pen", .pen),
            ("Eraser", .eraser),
            ("Rect", .rectangle),
            ("Round", .roundedRectangle),
            ("Ellipse", .ellipse),
            ("Arrow", .arrow),
            ("Curve", .curvedArrow),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(toolButtons, id: \.0) { label, tool in
                    Button {
                        overlayState.selectedTool = tool
                        overlayState.applyOverlayState()
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(overlayState.selectedTool == tool ? Color.accentColor.opacity(0.22) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Stroke")
                    .frame(width: 44, alignment: .leading)
                Slider(value: $overlayState.penWidth, in: 2...14, step: 1)
                Text("\(Int(overlayState.penWidth))")
                    .frame(width: 28, alignment: .trailing)
            }
            .onChange(of: overlayState.penWidth) { _ in overlayState.applyOverlayState() }

            HStack(spacing: 8) {
                Text("Line")
                    .frame(width: 44, alignment: .leading)
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
                }
            }

            Divider()

            HStack(spacing: 10) {
                Toggle("Fill", isOn: $overlayState.shapeFillEnabled)
                Toggle("Hatch", isOn: $overlayState.shapeHatchEnabled)
                Text("Radius")
                Slider(value: $overlayState.shapeCornerRadius, in: 0...40, step: 1)
                    .frame(width: 120)
            }
            .onChange(of: overlayState.shapeFillEnabled) { _ in overlayState.applyOverlayState() }
            .onChange(of: overlayState.shapeHatchEnabled) { _ in overlayState.applyOverlayState() }
            .onChange(of: overlayState.shapeCornerRadius) { _ in overlayState.applyOverlayState() }

            HStack(spacing: 8) {
                Text("Fill")
                    .frame(width: 44, alignment: .leading)
                Button {
                    overlayState.shapeFillColor = NSColor.systemGreen.withAlphaComponent(0.35)
                    overlayState.applyOverlayState()
                } label: {
                    Label("Green", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                Button {
                    overlayState.shapeFillColor = NSColor.systemYellow.withAlphaComponent(0.45)
                    overlayState.applyOverlayState()
                } label: {
                    Label("Yellow", systemImage: "circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                Button {
                    overlayState.shapeFillColor = NSColor.clear
                    overlayState.applyOverlayState()
                } label: {
                    Text("None")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12))

            HStack {
                Button("Undo") { overlayState.undo() }
                Button("Redo") { overlayState.redo() }
                Button("Clear") { overlayState.clearAll() }
                Spacer()
                Button("Hide") { overlayState.setToolboxVisible(false) }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(minWidth: 320)
    }
}
