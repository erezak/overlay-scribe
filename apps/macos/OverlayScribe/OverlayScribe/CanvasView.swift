import AppKit

@MainActor
final class CanvasView: NSView, NSTextViewDelegate {
    var inkModeEnabled: Bool = false
    var clickthroughEnabled: Bool = false {
        didSet {
            if clickthroughEnabled {
                // If we become fully click-through, clear any interactive UI.
                if textEditor != nil {
                    if !_commitTextEditingAndTearDown() {
                        endTextEditing()
                    }
                }
                clearSelection()
            }
        }
    }
    var selectedTool: OverlayState.Tool = .pen
    var penWidth: CGFloat = 4
    var penColor: NSColor = .systemRed

    // Shape styling (applied when a shape is created).
    var shapeFillEnabled: Bool = true
    var shapeFillColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.35)
    var shapeHatchEnabled: Bool = false
    var shapeCornerRadius: CGFloat = 18

    private let document = CoreDocument()
    private var cachedItems: [FfiItem] = []
    private var activeStroke: FfiStroke?
    private var activeShape: FfiShape?

    private enum DragState {
        case none
        case pending(start: CGPoint)
        case dragging(start: CGPoint)
    }

    private var dragState: DragState = .none

    private var selectedShapeId: UInt64?
    private var alignmentHud: AlignmentHUDView?

    private var textEditorScrollView: NSScrollView?
    private var textEditor: NSTextView?
    private var editingShapeId: UInt64?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if inkModeEnabled {
            return super.hitTest(point)
        }

        // If fully click-through, never intercept.
        if clickthroughEnabled {
            return nil
        }

        // Allow interactive subviews (e.g. text editor, alignment HUD) to receive clicks.
        if let hit = super.hitTest(point), hit !== self {
            return hit
        }

        // Not ink mode, not click-through: only intercept clicks on (or inside) shapes.
        if hitTestShape(at: point) != nil {
            return self
        }
        return nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Non-ink mode: selection + text editing on shapes.
        if !inkModeEnabled {
            // If we had an active editor, a click outside of it should commit so the drawn text persists.
            if textEditor != nil {
                _ = commitTextEditingIfNeeded()
            }

            if event.clickCount >= 2 {
                _ = beginEditingTextIfNeeded(at: p)
                return
            }

            if let hit = hitTestShape(at: p) {
                selectShape(hit.shape.id)
            }
            return
        }

        if event.clickCount >= 2 {
            if beginEditingTextIfNeeded(at: p) {
                return
            }
        }

        // Clicking outside commits any active text editing.
        if textEditor != nil {
            if !commitTextEditingIfNeeded() {
                // If commit failed (e.g. shape missing), still tear down editor.
                endTextEditing()
            }
        }

        switch selectedTool {
        case .pen:
            dragState = .pending(start: p)
        case .eraser:
            erase(at: p)
        case .rectangle:
            dragState = .pending(start: p)
        case .roundedRectangle:
            dragState = .pending(start: p)
        case .ellipse:
            dragState = .pending(start: p)
        case .arrow:
            dragState = .pending(start: p)
        case .curvedArrow:
            dragState = .pending(start: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard inkModeEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)

        switch dragState {
        case .none:
            break
        case .pending(let start):
            let dx = p.x - start.x
            let dy = p.y - start.y
            let dist2 = dx * dx + dy * dy
            let threshold: CGFloat = 6
            if dist2 >= threshold * threshold {
                dragState = .dragging(start: start)
                beginDragGesture(at: start)
            }
        case .dragging:
            break
        }

        switch selectedTool {
        case .pen:
            if activeStroke != nil {
                activeStroke?.points.append(p.asFfiPoint())
                setNeedsDisplay(bounds)
            }
        case .eraser:
            erase(at: p)
        case .rectangle, .roundedRectangle, .ellipse, .arrow, .curvedArrow:
            if activeShape != nil {
                activeShape?.end = p.asFfiPoint()
                setNeedsDisplay(bounds)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard inkModeEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)

        defer {
            activeStroke = nil
            activeShape = nil
            dragState = .none
        }

        // If we never started a drag gesture, treat this as a click.
        if case .pending = dragState {
            if let hit = hitTestShape(at: p) {
                selectShape(hit.shape.id)
                return
            }

            // Pen: allow a single-click dot.
            if selectedTool == .pen {
                var stroke = document.beginStroke(color: penColor.asFfiColor(), width: Float(penWidth), start: p.asFfiPoint())
                stroke.points.append(p.asFfiPoint())
                commit(stroke: stroke)
            }
            return
        }

        if var stroke = activeStroke {
            stroke.points.append(p.asFfiPoint())
            commit(stroke: stroke)
            return
        }

        if var shape = activeShape {
            shape.end = p.asFfiPoint()
            commit(shape: shape)
            return
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        func draw(stroke: FfiStroke) {
            guard let first = stroke.points.first else { return }
            ctx.beginPath()
            ctx.move(to: first.asCGPoint())
            for point in stroke.points.dropFirst() {
                ctx.addLine(to: point.asCGPoint())
            }
            ctx.setStrokeColor(stroke.color.asNSColor().cgColor)
            ctx.setLineWidth(CGFloat(stroke.width))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }

        func draw(shape: FfiShape) {
            let strokeColor = shape.style.strokeColor.asNSColor().cgColor
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(CGFloat(shape.style.strokeWidth))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            func fillAndHatch(path: CGPath) {
                guard shape.style.fillEnabled else { return }

                ctx.saveGState()
                ctx.addPath(path)
                ctx.setFillColor(shape.style.fillColor.asNSColor().cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                guard shape.style.hatchEnabled else { return }

                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                drawHatch(ctx: ctx, in: path.boundingBox, strokeColor: strokeColor, lineWidth: max(1, CGFloat(shape.style.strokeWidth) * 0.6))
                ctx.restoreGState()
            }

            switch shape.kind {
            case .rectangle:
                let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
                let path = CGPath(rect: rect, transform: nil)
                fillAndHatch(path: path)
                ctx.stroke(rect)
                drawShapeTextIfNeeded(shape, in: rect, clipPath: path)

            case .roundedRectangle:
                let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
                let radius = min(CGFloat(shape.style.cornerRadius), min(rect.width, rect.height) / 2)
                let path = roundedRectPath(in: rect, radius: radius)
                fillAndHatch(path: path)
                ctx.addPath(path)
                ctx.strokePath()
                drawShapeTextIfNeeded(shape, in: rect, clipPath: path)

            case .ellipse:
                let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
                let path = CGPath(ellipseIn: rect, transform: nil)
                fillAndHatch(path: path)
                ctx.strokeEllipse(in: rect)
                drawShapeTextIfNeeded(shape, in: rect, clipPath: path)

            case .arrow:
                drawArrow(ctx: ctx, start: shape.start.asCGPoint(), end: shape.end.asCGPoint(), lineWidth: CGFloat(shape.style.strokeWidth), fillColor: strokeColor)

            case .curvedArrow:
                drawCurvedArrow(ctx: ctx, start: shape.start.asCGPoint(), end: shape.end.asCGPoint(), lineWidth: CGFloat(shape.style.strokeWidth), strokeColor: strokeColor)
            }

            if selectedShapeId == shape.id {
                drawSelectionOutline(for: shape, ctx: ctx)
            }
        }

        for item in cachedItems {
            switch item {
            case .stroke(let s): draw(stroke: s)
            case .shape(let sh): draw(shape: sh)
            }
        }
        if let s = activeStroke {
            draw(stroke: s)
        }
        if let sh = activeShape {
            draw(shape: sh)
        }
    }

    func clearAll() {
        _ = commitTextEditingIfNeeded()
        document.clearAll()
        refreshItems()
        setNeedsDisplay(bounds)
    }

    func undo() {
        _ = commitTextEditingIfNeeded()
        guard document.undo() else { return }
        refreshItems()
        setNeedsDisplay(bounds)
    }

    func redo() {
        _ = commitTextEditingIfNeeded()
        guard document.redo() else { return }
        refreshItems()
        setNeedsDisplay(bounds)
    }

    private func commit(stroke: FfiStroke) {
        document.commitStroke(stroke: stroke)
        refreshItems()
        setNeedsDisplay(bounds)
    }

    private func commit(shape: FfiShape) {
        document.commitShape(shape: shape)
        refreshItems()
        setNeedsDisplay(bounds)
    }

    private func erase(at point: CGPoint) {
        let radius = max(8, penWidth * 2)
        guard document.eraseAt(point: point.asFfiPoint(), radius: Float(radius)) else { return }
        refreshItems()
        setNeedsDisplay(bounds)
    }

    private func refreshItems() {
        cachedItems = document.items()

        if let selectedShapeId, !cachedItems.contains(where: { item in
            if case .shape(let sh) = item { return sh.id == selectedShapeId }
            return false
        }) {
            clearSelection()
        } else {
            updateAlignmentHud()
        }
    }

    private func beginDragGesture(at start: CGPoint) {
        clearSelection()
        switch selectedTool {
        case .pen:
            activeStroke = document.beginStroke(color: penColor.asFfiColor(), width: Float(penWidth), start: start.asFfiPoint())
        case .eraser:
            break
        case .rectangle:
            activeShape = document.beginShape(kind: .rectangle, style: currentShapeStyle(), start: start.asFfiPoint())
        case .roundedRectangle:
            activeShape = document.beginShape(kind: .roundedRectangle, style: currentShapeStyle(), start: start.asFfiPoint())
        case .ellipse:
            activeShape = document.beginShape(kind: .ellipse, style: currentShapeStyle(), start: start.asFfiPoint())
        case .arrow:
            activeShape = document.beginShape(kind: .arrow, style: currentShapeStyle(), start: start.asFfiPoint())
        case .curvedArrow:
            activeShape = document.beginShape(kind: .curvedArrow, style: currentShapeStyle(), start: start.asFfiPoint())
        }
    }

    private struct ShapeHit {
        let shape: FfiShape
        let rect: CGRect
        let path: CGPath?
        let isClosed: Bool
    }

    private func isClosedShape(_ kind: FfiShapeKind) -> Bool {
        switch kind {
        case .rectangle, .roundedRectangle, .ellipse:
            return true
        case .arrow, .curvedArrow:
            return false
        }
    }

    private func shapePathAndRect(for shape: FfiShape) -> (rect: CGRect, path: CGPath?) {
        let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
        switch shape.kind {
        case .rectangle:
            return (rect, CGPath(rect: rect, transform: nil))
        case .roundedRectangle:
            let radius = min(CGFloat(shape.style.cornerRadius), min(rect.width, rect.height) / 2)
            return (rect, roundedRectPath(in: rect, radius: radius))
        case .ellipse:
            return (rect, CGPath(ellipseIn: rect, transform: nil))
        case .arrow, .curvedArrow:
            return (rect, nil)
        }
    }

    private func hitTestShape(at point: CGPoint) -> ShapeHit? {
        // Iterate in reverse so the most recently-added items win.
        for item in cachedItems.reversed() {
            guard case .shape(let shape) = item else { continue }
            let (rect, path) = shapePathAndRect(for: shape)
            let closed = isClosedShape(shape.kind)
            if closed, let path {
                if path.contains(point) {
                    return ShapeHit(shape: shape, rect: rect, path: path, isClosed: true)
                }
            } else {
                // Fallback: bounding box hit-test (for arrows too).
                if rect.contains(point) {
                    return ShapeHit(shape: shape, rect: rect, path: path, isClosed: closed)
                }
            }
        }
        return nil
    }

    private func selectShape(_ id: UInt64) {
        selectedShapeId = id
        updateAlignmentHud()
        setNeedsDisplay(bounds)
    }

    private func clearSelection() {
        selectedShapeId = nil
        updateAlignmentHud()
        setNeedsDisplay(bounds)
    }

    private func updateAlignmentHud() {
        guard let selectedShapeId,
              let hit = cachedItems.compactMap({ item -> ShapeHit? in
                  guard case .shape(let sh) = item else { return nil }
                  guard sh.id == selectedShapeId else { return nil }
                  let (rect, path) = shapePathAndRect(for: sh)
                  return ShapeHit(shape: sh, rect: rect, path: path, isClosed: isClosedShape(sh.kind))
              }).first,
              hit.isClosed
        else {
            alignmentHud?.removeFromSuperview()
            alignmentHud = nil
            return
        }

        if alignmentHud == nil {
            let hud = AlignmentHUDView()
            hud.onAlignH = { [weak self] align in
                self?.applyTextAlignment(h: align)
            }
            hud.onAlignV = { [weak self] align in
                self?.applyTextAlignment(v: align)
            }
            addSubview(hud)
            alignmentHud = hud
        }

        alignmentHud?.setSelected(alignH: hit.shape.textAlignH, alignV: hit.shape.textAlignV)

        // Position near the top-left of the shape bounds.
        let hudSize = alignmentHud?.intrinsicContentSize ?? CGSize(width: 150, height: 44)
        let origin = CGPoint(
            x: min(max(8, hit.rect.minX + 8), bounds.maxX - hudSize.width - 8),
            y: min(max(8, hit.rect.minY + 8), bounds.maxY - hudSize.height - 8)
        )
        alignmentHud?.frame = CGRect(origin: origin, size: hudSize)
    }

    private func applyTextAlignment(h: FfiTextAlignH? = nil, v: FfiTextAlignV? = nil) {
        guard let selectedShapeId else { return }
        guard var shape = cachedItems.compactMap({ item -> FfiShape? in
            if case .shape(let sh) = item, sh.id == selectedShapeId { return sh }
            return nil
        }).first else { return }

        if let h { shape.textAlignH = h }
        if let v { shape.textAlignV = v }

        document.commitShape(shape: shape)
        refreshItems()
        setNeedsDisplay(bounds)
    }

    private func beginEditingTextIfNeeded(at point: CGPoint) -> Bool {
        guard let hit = hitTestShape(at: point) else { return false }
        guard hit.isClosed else { return false }

        selectShape(hit.shape.id)
        beginTextEditing(shape: hit.shape, shapeRect: hit.rect, clipPath: hit.path)
        return true
    }

    private func beginTextEditing(shape: FfiShape, shapeRect: CGRect, clipPath: CGPath?) {
        endTextEditing()

        let padding: CGFloat = 10
        let editorRect = shapeRect.insetBy(dx: padding, dy: padding)
        guard editorRect.width >= 24, editorRect.height >= 20 else { return }

        let textView = NSTextView(frame: editorRect)
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.insertionPointColor = .labelColor
        textView.textColor = .labelColor
        textView.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.textContainerInset = CGSize(width: 6, height: 6)
        textView.string = shape.text
        textView.alignment = shape.textAlignH.asNSTextAlignment()

        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = true
            container.heightTracksTextView = false
        }
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView(frame: editorRect)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autoresizingMask = []
        scroll.documentView = textView

        // Clip to the closed shape so typing stays "inside".
        if let clipPath {
            scroll.wantsLayer = true
            scroll.layer?.masksToBounds = true
            let maskLayer = CAShapeLayer()
            var t = CGAffineTransform(translationX: -editorRect.origin.x, y: -editorRect.origin.y)
            maskLayer.path = clipPath.copy(using: &t)
            scroll.layer?.mask = maskLayer
        }

        addSubview(scroll)
        textEditorScrollView = scroll
        textEditor = textView
        editingShapeId = shape.id

        // Ensure the overlay can actually accept key events while editing.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(textView)
        setNeedsDisplay(bounds)
    }

    private func commitTextEditingIfNeeded() -> Bool {
        guard let editingShapeId, let textView = textEditor else { return true }
        guard var shape = cachedItems.compactMap({ item -> FfiShape? in
            if case .shape(let sh) = item, sh.id == editingShapeId { return sh }
            return nil
        }).first else {
            endTextEditing()
            return false
        }

        shape.text = textView.string
        document.commitShape(shape: shape)
        refreshItems()
        endTextEditing()
        setNeedsDisplay(bounds)
        return true
    }

    private func endTextEditing() {
        textEditor = nil
        editingShapeId = nil
        textEditorScrollView?.removeFromSuperview()
        textEditorScrollView = nil
    }

    private func _commitTextEditingAndTearDown() -> Bool {
        let ok = commitTextEditingIfNeeded()
        endTextEditing()
        return ok
    }

    func textDidEndEditing(_ notification: Notification) {
        _ = commitTextEditingIfNeeded()
    }

    private func drawShapeTextIfNeeded(_ shape: FfiShape, in rect: CGRect, clipPath: CGPath?) {
        guard isClosedShape(shape.kind) else { return }
        let text = shape.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let insetRect = rect.insetBy(dx: 10, dy: 10)
        guard insetRect.width > 6, insetRect.height > 6 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = shape.textAlignH.asNSTextAlignment()
        paragraph.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]

        let nsText = text as NSString
        let measured = nsText.boundingRect(
            with: CGSize(width: insetRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )

        let textHeight = min(insetRect.height, ceil(measured.height))
        let y: CGFloat
        switch shape.textAlignV {
        case .top:
            y = insetRect.minY
        case .middle:
            y = insetRect.minY + (insetRect.height - textHeight) / 2
        case .bottom:
            y = insetRect.maxY - textHeight
        }

        let drawRect = CGRect(x: insetRect.minX, y: y, width: insetRect.width, height: textHeight)

        // Clip using CoreGraphics so we support macOS 13 (NSBezierPath(cgPath:) is macOS 14+).
        guard let cgContext = NSGraphicsContext.current?.cgContext else {
            nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            return
        }

        cgContext.saveGState()
        if let clipPath {
            cgContext.addPath(clipPath)
            cgContext.clip()
        }
        nsText.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        cgContext.restoreGState()
    }

    private func drawSelectionOutline(for shape: FfiShape, ctx: CGContext) {
        let (rect, path) = shapePathAndRect(for: shape)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.selectedControlColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])

        if let path {
            ctx.addPath(path)
            ctx.strokePath()
        } else {
            ctx.stroke(rect)
        }

        ctx.restoreGState()
    }
    private func currentShapeStyle() -> FfiShapeStyle {
        FfiShapeStyle(
            strokeColor: penColor.asFfiColor(),
            strokeWidth: Float(penWidth),
            fillEnabled: shapeFillEnabled,
            fillColor: shapeFillColor.asFfiColor(),
            hatchEnabled: shapeHatchEnabled,
            cornerRadius: Float(shapeCornerRadius)
        )
    }

    private func rectFromPoints(a: CGPoint, b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func drawArrow(ctx: CGContext, start: CGPoint, end: CGPoint, lineWidth: CGFloat, fillColor: CGColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.5 else { return }

        // Shaft
        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Head
        let ux = dx / len
        let uy = dy / len
        let headLength = max(10, lineWidth * 4)
        let headWidth = max(8, lineWidth * 3)

        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let perp = CGPoint(x: -uy, y: ux)

        let left = CGPoint(x: base.x + perp.x * (headWidth / 2), y: base.y + perp.y * (headWidth / 2))
        let right = CGPoint(x: base.x - perp.x * (headWidth / 2), y: base.y - perp.y * (headWidth / 2))

        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.setFillColor(fillColor)
        ctx.fillPath()
    }

    private func drawCurvedArrow(ctx: CGContext, start: CGPoint, end: CGPoint, lineWidth: CGFloat, strokeColor: CGColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.5 else { return }

        let control = controlPointForCurve(start: start, end: end)

        ctx.saveGState()
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.beginPath()
        ctx.move(to: start)
        ctx.addQuadCurve(to: end, control: control)
        ctx.strokePath()
        ctx.restoreGState()

        // Arrowhead: align to the tangent at the end of the quadratic.
        let tx = end.x - control.x
        let ty = end.y - control.y
        let tlen = sqrt(tx * tx + ty * ty)
        guard tlen > 0.5 else { return }
        let ux = tx / tlen
        let uy = ty / tlen

        let headLength = max(10, lineWidth * 4)
        let headWidth = max(8, lineWidth * 3)
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let perp = CGPoint(x: -uy, y: ux)
        let left = CGPoint(x: base.x + perp.x * (headWidth / 2), y: base.y + perp.y * (headWidth / 2))
        let right = CGPoint(x: base.x - perp.x * (headWidth / 2), y: base.y - perp.y * (headWidth / 2))

        ctx.saveGState()
        ctx.setFillColor(strokeColor)
        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func controlPointForCurve(start: CGPoint, end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.5 else { return mid }

        let ux = dx / len
        let uy = dy / len
        let perp = CGPoint(x: -uy, y: ux)

        // Pick a stable side for the curve.
        let sign: CGFloat = (dx * dy >= 0) ? 1 : -1
        let magnitude = min(160, max(18, len * 0.22))
        return CGPoint(x: mid.x + perp.x * magnitude * sign, y: mid.y + perp.y * magnitude * sign)
    }

    private func approximateQuadraticBezier(start: CGPoint, control: CGPoint, end: CGPoint, steps: Int) -> [CGPoint] {
        guard steps >= 1 else { return [start, end] }
        return (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            let u = 1 - t
            let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
            let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
            return CGPoint(x: x, y: y)
        }
    }

    private func roundedRectPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let r = max(0, radius)

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY

        path.move(to: CGPoint(x: minX + r, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY + r), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addQuadCurve(to: CGPoint(x: maxX - r, y: maxY), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addQuadCurve(to: CGPoint(x: minX, y: maxY - r), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addQuadCurve(to: CGPoint(x: minX + r, y: minY), control: CGPoint(x: minX, y: minY))
        path.closeSubpath()

        return path
    }

    private func drawHatch(ctx: CGContext, in rect: CGRect, strokeColor: CGColor, lineWidth: CGFloat) {
        let spacing: CGFloat = 10
        let hatchColor = NSColor(cgColor: strokeColor)?.withAlphaComponent(0.35).cgColor ?? strokeColor

        ctx.saveGState()
        ctx.setStrokeColor(hatchColor)
        ctx.setLineWidth(lineWidth)

        // 45-degree lines: x - y = c. Iterate c over a range that covers the rect.
        let minC = rect.minX - rect.maxY
        let maxC = rect.maxX - rect.minY

        var c = minC - spacing
        while c <= maxC + spacing {
            // Intersections of x - y = c with the rect.
            var points: [CGPoint] = []

            // x = rect.minX => y = x - c
            let yAtMinX = rect.minX - c
            if yAtMinX >= rect.minY && yAtMinX <= rect.maxY {
                points.append(CGPoint(x: rect.minX, y: yAtMinX))
            }

            // x = rect.maxX
            let yAtMaxX = rect.maxX - c
            if yAtMaxX >= rect.minY && yAtMaxX <= rect.maxY {
                points.append(CGPoint(x: rect.maxX, y: yAtMaxX))
            }

            // y = rect.minY => x = c + y
            let xAtMinY = c + rect.minY
            if xAtMinY >= rect.minX && xAtMinY <= rect.maxX {
                points.append(CGPoint(x: xAtMinY, y: rect.minY))
            }

            // y = rect.maxY
            let xAtMaxY = c + rect.maxY
            if xAtMaxY >= rect.minX && xAtMaxY <= rect.maxX {
                points.append(CGPoint(x: xAtMaxY, y: rect.maxY))
            }

            if points.count >= 2 {
                // Use the first two distinct points.
                let p0 = points[0]
                var p1 = points[1]
                if abs(p0.x - p1.x) < 0.001 && abs(p0.y - p1.y) < 0.001, points.count >= 3 {
                    p1 = points[2]
                }
                ctx.beginPath()
                ctx.move(to: p0)
                ctx.addLine(to: p1)
                ctx.strokePath()
            }

            c += spacing
        }
        ctx.restoreGState()
    }
}

private extension CGPoint {
    func asFfiPoint() -> FfiPoint {
        FfiPoint(x: Float(x), y: Float(y))
    }
}

private extension FfiPoint {
    func asCGPoint() -> CGPoint {
        CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}

private extension NSColor {
    func asFfiColor() -> FfiColorRgba8 {
        let c = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)

        func u8(_ v: CGFloat) -> UInt8 {
            let scaled = Int((v * 255.0).rounded())
            return UInt8(max(0, min(255, scaled)))
        }

        return FfiColorRgba8(r: u8(r), g: u8(g), b: u8(b), a: u8(a))
    }
}

private extension FfiColorRgba8 {
    func asNSColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

private extension FfiTextAlignH {
    func asNSTextAlignment() -> NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

private final class AlignmentHUDView: NSVisualEffectView {
    var onAlignH: ((FfiTextAlignH) -> Void)?
    var onAlignV: ((FfiTextAlignV) -> Void)?

    private let leftButton = NSButton()
    private let centerButton = NSButton()
    private let rightButton = NSButton()
    private let topButton = NSButton()
    private let middleButton = NSButton()
    private let bottomButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10

        let hStack = NSStackView(views: [leftButton, centerButton, rightButton])
        hStack.orientation = .horizontal
        hStack.spacing = 6
        hStack.alignment = .centerY

        let vStack = NSStackView(views: [topButton, middleButton, bottomButton])
        vStack.orientation = .horizontal
        vStack.spacing = 6
        vStack.alignment = .centerY

        let root = NSStackView(views: [hStack, vStack])
        root.orientation = .vertical
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        addSubview(root)
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        configureButton(leftButton, symbol: "text.alignleft", fallback: nil, tooltip: "Align Left")
        configureButton(centerButton, symbol: "text.aligncenter", fallback: nil, tooltip: "Align Center")
        configureButton(rightButton, symbol: "text.alignright", fallback: nil, tooltip: "Align Right")

        configureButton(topButton, symbol: "align.vertical.top", fallback: "arrow.up.to.line", tooltip: "Align Top")
        configureButton(middleButton, symbol: "align.vertical.center", fallback: "arrow.up.and.down", tooltip: "Align Middle")
        configureButton(bottomButton, symbol: "align.vertical.bottom", fallback: "arrow.down.to.line", tooltip: "Align Bottom")

        leftButton.target = self
        leftButton.action = #selector(tapLeft)
        centerButton.target = self
        centerButton.action = #selector(tapCenter)
        rightButton.target = self
        rightButton.action = #selector(tapRight)

        topButton.target = self
        topButton.action = #selector(tapTop)
        middleButton.target = self
        middleButton.action = #selector(tapMiddle)
        bottomButton.target = self
        bottomButton.action = #selector(tapBottom)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 152, height: 72)
    }

    func setSelected(alignH: FfiTextAlignH, alignV: FfiTextAlignV) {
        setHighlighted(leftButton, alignH == .left)
        setHighlighted(centerButton, alignH == .center)
        setHighlighted(rightButton, alignH == .right)

        setHighlighted(topButton, alignV == .top)
        setHighlighted(middleButton, alignV == .middle)
        setHighlighted(bottomButton, alignV == .bottom)
    }

    private func configureButton(_ button: NSButton, symbol: String, fallback: String?, tooltip: String) {
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.contentTintColor = .labelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 8

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            ?? (fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: tooltip) })
        button.image = image
    }

    private func setHighlighted(_ button: NSButton, _ highlighted: Bool) {
        button.layer?.backgroundColor = highlighted
            ? NSColor.selectedControlColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    @objc private func tapLeft() { onAlignH?(.left) }
    @objc private func tapCenter() { onAlignH?(.center) }
    @objc private func tapRight() { onAlignH?(.right) }
    @objc private func tapTop() { onAlignV?(.top) }
    @objc private func tapMiddle() { onAlignV?(.middle) }
    @objc private func tapBottom() { onAlignV?(.bottom) }
}
