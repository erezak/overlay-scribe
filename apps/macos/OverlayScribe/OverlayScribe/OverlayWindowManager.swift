import AppKit

@MainActor
final class OverlayWindowManager {
    private var controllersByScreenId: [String: OverlayWindowController] = [:]

    private var tool: OverlayState.Tool = .pen
    private var penWidth: CGFloat = 4
    private var color: NSColor = .systemRed
    private var inkModeEnabled: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileScreens()
        }
    }

    func showOverlays() {
        reconcileScreens()
        for controller in controllersByScreenId.values {
            controller.show()
        }
        applyCurrentStateToAll()
    }

    func hideOverlays() {
        for controller in controllersByScreenId.values {
            controller.hide()
        }
    }

    func setInkModeEnabled(_ enabled: Bool) {
        inkModeEnabled = enabled
        for controller in controllersByScreenId.values {
            controller.setInkModeEnabled(enabled)
        }
        if enabled {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func setTool(_ tool: OverlayState.Tool) {
        self.tool = tool
        for controller in controllersByScreenId.values {
            controller.setTool(tool)
        }
    }

    func setPenWidth(_ width: CGFloat) {
        penWidth = width
        for controller in controllersByScreenId.values {
            controller.setPenWidth(width)
        }
    }

    func setColor(_ color: NSColor) {
        self.color = color
        for controller in controllersByScreenId.values {
            controller.setColor(color)
        }
    }

    func clearAll() {
        for controller in controllersByScreenId.values {
            controller.clearAll()
        }
    }

    func undo() {
        for controller in controllersByScreenId.values {
            controller.undo()
        }
    }

    func redo() {
        for controller in controllersByScreenId.values {
            controller.redo()
        }
    }

    private func applyCurrentStateToAll() {
        for controller in controllersByScreenId.values {
            controller.setInkModeEnabled(inkModeEnabled)
            controller.setTool(tool)
            controller.setPenWidth(penWidth)
            controller.setColor(color)
        }
    }

    private func reconcileScreens() {
        let screens = NSScreen.screens
        let screenIds = Set(screens.map { self.screenId(for: $0) })

        for id in controllersByScreenId.keys where !screenIds.contains(id) {
            controllersByScreenId[id]?.hide()
            controllersByScreenId[id] = nil
        }

        for screen in screens {
            let id = screenId(for: screen)
            if controllersByScreenId[id] == nil {
                controllersByScreenId[id] = OverlayWindowController(screen: screen)
            } else {
                controllersByScreenId[id]?.updateFrame(for: screen)
            }
        }
    }

    private func screenId(for screen: NSScreen) -> String {
        if let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return displayId.stringValue
        }
        return screen.localizedName
    }
}

@MainActor
private final class OverlayWindowController {
    private let window: NSWindow
    private let canvasView: CanvasView

    init(screen: NSScreen) {
        canvasView = CanvasView(frame: screen.frame)

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false

        // A reliable "always-on-top" for overlays; may still have edge cases with system UI.
        window.level = .screenSaver

        window.ignoresMouseEvents = true
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
        ]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        let hosting = NSView(frame: screen.frame)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.addSubview(canvasView)
        canvasView.autoresizingMask = [.width, .height]
        canvasView.frame = hosting.bounds
        window.contentView = hosting
    }

    func updateFrame(for screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
        canvasView.frame = window.contentView?.bounds ?? screen.frame
    }

    func show() {
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func setInkModeEnabled(_ enabled: Bool) {
        window.ignoresMouseEvents = !enabled
        canvasView.inkModeEnabled = enabled
        if enabled {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func setTool(_ tool: OverlayState.Tool) {
        canvasView.selectedTool = tool
    }

    func setPenWidth(_ width: CGFloat) {
        canvasView.penWidth = width
    }

    func setColor(_ color: NSColor) {
        canvasView.penColor = color
    }

    func clearAll() {
        canvasView.clearAll()
    }

    func undo() {
        canvasView.undo()
    }

    func redo() {
        canvasView.redo()
    }
}
