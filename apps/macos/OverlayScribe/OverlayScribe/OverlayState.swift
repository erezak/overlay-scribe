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

    @Published var overlayEnabled: Bool = true
    @Published var inkModeEnabled: Bool = false
    // When true, the overlay is fully click-through to apps behind it.
    // When false, shapes can intercept clicks (for selection/text editing).
    @Published var clickthroughEnabled: Bool = false
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
        hotkeyManager.onToggleClickthrough = { [weak self] in
            Task { @MainActor in self?.toggleClickthrough() }
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

        // Ensure the initial published values take effect immediately at launch.
        applyOverlayState()
    }

    func toggleOverlay() {
        overlayEnabled.toggle()
        applyOverlayState()
    }

    func toggleInkMode() {
        inkModeEnabled.toggle()
        applyOverlayState()
    }

    func toggleClickthrough() {
        clickthroughEnabled.toggle()
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
        windowManager.setClickthroughEnabled(clickthroughEnabled)
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
                contentRect: NSRect(x: 80, y: 80, width: 460, height: 270),
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

    private struct ToolButton: Identifiable {
        let id = UUID()
        let label: String
        let symbol: String
        let tool: OverlayState.Tool
    }

    private var toolButtons: [ToolButton] {
        [
            .init(label: "Pen", symbol: "pencil", tool: .pen),
            .init(label: "Eraser", symbol: "eraser", tool: .eraser),
            .init(label: "Rect", symbol: "rectangle", tool: .rectangle),
            .init(label: "Rounded", symbol: "rectangle.roundedtop", tool: .roundedRectangle),
            .init(label: "Ellipse", symbol: "circle", tool: .ellipse),
            .init(label: "Arrow", symbol: "arrow.right", tool: .arrow),
            .init(label: "Curved", symbol: "arrow.triangle.turn.up.right.diamond", tool: .curvedArrow),
        ]
    }

    private func toolLabel(_ button: ToolButton) -> some View {
        HStack(spacing: 6) {
            Image(systemName: button.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text(button.label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(overlayState.selectedTool == button.tool ? Color.accentColor.opacity(0.22) : Color.clear)
        )
    }

    private func fillOptionLabel(title: String, dotColor: NSColor) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: dotColor))
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
            Text(title)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(overlayState.inkModeEnabled ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text("Ink Mode")
                        .font(.system(size: 12, weight: .semibold))
                    Text(overlayState.inkModeEnabled ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(overlayState.inkModeEnabled ? .primary : .secondary)
                }
                Spacer()
                Toggle(isOn: $overlayState.inkModeEnabled) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: overlayState.inkModeEnabled) { _ in
                    overlayState.applyOverlayState()
                }
            }

            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(overlayState.clickthroughEnabled ? Color.orange : Color.secondary.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text("Click-through")
                        .font(.system(size: 12, weight: .semibold))
                    Text(overlayState.clickthroughEnabled ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(overlayState.clickthroughEnabled ? .primary : .secondary)
                }
                Spacer()
                Toggle(isOn: $overlayState.clickthroughEnabled) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: overlayState.clickthroughEnabled) { _ in
                    overlayState.applyOverlayState()
                }
            }

            let columns: [GridItem] = [
                GridItem(.flexible(minimum: 120), spacing: 8),
                GridItem(.flexible(minimum: 120), spacing: 8),
                GridItem(.flexible(minimum: 120), spacing: 8),
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(toolButtons) { button in
                    Button {
                        overlayState.selectedTool = button.tool
                        overlayState.applyOverlayState()
                    } label: {
                        toolLabel(button)
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
                    fillOptionLabel(title: "Green", dotColor: .systemGreen)
                }
                .buttonStyle(.plain)
                Button {
                    overlayState.shapeFillColor = NSColor.systemYellow.withAlphaComponent(0.45)
                    overlayState.applyOverlayState()
                } label: {
                    fillOptionLabel(title: "Yellow", dotColor: .systemYellow)
                }
                .buttonStyle(.plain)
                Button {
                    overlayState.shapeFillColor = NSColor.clear
                    overlayState.applyOverlayState()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("None")
                    }
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
        .frame(minWidth: 460)
    }
}
