import AppKit

@MainActor
final class OverlayWindowManager {
    private var controllersByScreenId: [String: OverlayWindowController] = [:]

    private var tool: OverlayState.Tool = .pen
    private var penWidth: CGFloat = 4
    private var color: NSColor = .systemRed
    private var inkModeEnabled: Bool = false
    private var clickthroughEnabled: Bool = false

    private var shapeFillEnabled: Bool = true
    private var shapeFillColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.35)
    private var shapeHatchEnabled: Bool = false
    private var shapeCornerRadius: CGFloat = 18

    private var mouseMonitor: Any?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.reconcileScreens()
            }
        }
    }

    func showOverlays() {
        reconcileScreens()
        for controller in controllersByScreenId.values {
            controller.show()
        }
        applyCurrentStateToAll()
        installMouseMonitorIfNeeded()
    }

    func hideOverlays() {
        for controller in controllersByScreenId.values {
            controller.hide()
        }
        removeMouseMonitorIfNeeded()
    }

    func setInkModeEnabled(_ enabled: Bool) {
        inkModeEnabled = enabled
        for controller in controllersByScreenId.values {
            controller.setInkModeEnabled(enabled)
        }
        if enabled {
            NSApp.activate(ignoringOtherApps: true)
        }
        updateMousePassthroughPolicies()
    }

    func setClickthroughEnabled(_ enabled: Bool) {
        clickthroughEnabled = enabled
        for controller in controllersByScreenId.values {
            controller.setClickthroughEnabled(enabled)
        }
        updateMousePassthroughPolicies()
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

    func setShapeFillEnabled(_ enabled: Bool) {
        shapeFillEnabled = enabled
        for controller in controllersByScreenId.values {
            controller.setShapeFillEnabled(enabled)
        }
    }

    func setShapeFillColor(_ color: NSColor) {
        shapeFillColor = color
        for controller in controllersByScreenId.values {
            controller.setShapeFillColor(color)
        }
    }

    func setShapeHatchEnabled(_ enabled: Bool) {
        shapeHatchEnabled = enabled
        for controller in controllersByScreenId.values {
            controller.setShapeHatchEnabled(enabled)
        }
    }

    func setShapeCornerRadius(_ radius: CGFloat) {
        shapeCornerRadius = radius
        for controller in controllersByScreenId.values {
            controller.setShapeCornerRadius(radius)
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
            controller.setClickthroughEnabled(clickthroughEnabled)
            controller.setTool(tool)
            controller.setPenWidth(penWidth)
            controller.setColor(color)
            controller.setShapeFillEnabled(shapeFillEnabled)
            controller.setShapeFillColor(shapeFillColor)
            controller.setShapeHatchEnabled(shapeHatchEnabled)
            controller.setShapeCornerRadius(shapeCornerRadius)
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

        updateMousePassthroughPolicies()
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateMousePassthroughPolicies()
            }
        }
    }

    private func removeMouseMonitorIfNeeded() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func updateMousePassthroughPolicies() {
        // NSEvent.mouseLocation is in global screen coords.
        let global = NSEvent.mouseLocation
        for controller in controllersByScreenId.values {
            controller.updateMousePassthrough(globalMouseLocation: global)
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
private final class OverlayKeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OverlayWindowController {
    private let window: NSWindow
    private let canvasView: CanvasView

    private var inkModeEnabled: Bool = false
    private var clickthroughEnabled: Bool = false

    init(screen: NSScreen) {
        canvasView = CanvasView(frame: screen.frame)

        window = OverlayKeyableWindow(
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

        // Default: not ink mode; allow hit-testing shapes while still letting empty regions click through.
        window.ignoresMouseEvents = false
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
        inkModeEnabled = enabled
        applyMousePolicy(globalMouseLocation: NSEvent.mouseLocation)
        if enabled {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func setClickthroughEnabled(_ enabled: Bool) {
        clickthroughEnabled = enabled
        applyMousePolicy(globalMouseLocation: NSEvent.mouseLocation)
    }

    func updateMousePassthrough(globalMouseLocation: NSPoint) {
        applyMousePolicy(globalMouseLocation: globalMouseLocation)
    }

    private func applyMousePolicy(globalMouseLocation: NSPoint) {
        canvasView.inkModeEnabled = inkModeEnabled
        canvasView.clickthroughEnabled = clickthroughEnabled

        // In ink mode, always capture input for drawing.
        if inkModeEnabled {
            window.ignoresMouseEvents = false
            return
        }

        // If click-through is enabled, everything passes through (including ink/shapes).
        if clickthroughEnabled {
            window.ignoresMouseEvents = true
            return
        }

        // clickthroughEnabled == false:
        // Let clicks pass through unless the pointer is over ink or inside a closed shape.
        guard window.frame.contains(globalMouseLocation) else {
            window.ignoresMouseEvents = true
            return
        }

        let windowPoint = window.convertPoint(fromScreen: globalMouseLocation)
        let viewPoint = canvasView.convert(windowPoint, from: nil)
        let shouldBlock = canvasView.blocksMouse(at: viewPoint)
        window.ignoresMouseEvents = !shouldBlock
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

    func setShapeFillEnabled(_ enabled: Bool) {
        canvasView.shapeFillEnabled = enabled
    }

    func setShapeFillColor(_ color: NSColor) {
        canvasView.shapeFillColor = color
    }

    func setShapeHatchEnabled(_ enabled: Bool) {
        canvasView.shapeHatchEnabled = enabled
    }

    func setShapeCornerRadius(_ radius: CGFloat) {
        canvasView.shapeCornerRadius = radius
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
