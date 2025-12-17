import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    enum Tool: String, CaseIterable {
        case pen
        case eraser
        case rectangle
        case ellipse
        case arrow
    }

    struct PaletteColor: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let color: NSColor
    }

    @Published var overlayEnabled: Bool = false
    @Published var inkModeEnabled: Bool = false
    @Published var selectedTool: Tool = .pen

    @Published var penWidth: CGFloat = 4
    @Published var selectedColor: NSColor = .systemRed

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
    }
}
