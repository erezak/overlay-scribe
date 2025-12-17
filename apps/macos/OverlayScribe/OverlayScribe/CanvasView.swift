import AppKit

@MainActor
final class CanvasView: NSView {
    struct Stroke {
        var color: NSColor
        var width: CGFloat
        var points: [CGPoint]
    }

    enum ShapeKind {
        case rectangle
        case ellipse
        case arrow
    }

    struct Shape {
        var kind: ShapeKind
        var color: NSColor
        var width: CGFloat
        var start: CGPoint
        var end: CGPoint
    }

    enum Item {
        case stroke(Stroke)
        case shape(Shape)
    }

    var inkModeEnabled: Bool = false
    var selectedTool: OverlayState.Tool = .pen
    var penWidth: CGFloat = 4
    var penColor: NSColor = .systemRed

    private var items: [Item] = []
    private var redoStack: [[Item]] = []
    private var activeStroke: Stroke?
    private var activeShape: Shape?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Allow click-through when not in ink mode.
        guard inkModeEnabled else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard inkModeEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch selectedTool {
        case .pen:
            activeStroke = Stroke(color: penColor, width: penWidth, points: [p])
        case .eraser:
            erase(at: p)
        case .rectangle:
            activeShape = Shape(kind: .rectangle, color: penColor, width: penWidth, start: p, end: p)
        case .ellipse:
            activeShape = Shape(kind: .ellipse, color: penColor, width: penWidth, start: p, end: p)
        case .arrow:
            activeShape = Shape(kind: .arrow, color: penColor, width: penWidth, start: p, end: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard inkModeEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch selectedTool {
        case .pen:
            activeStroke?.points.append(p)
            setNeedsDisplay(bounds)
        case .eraser:
            erase(at: p)
        case .rectangle, .ellipse, .arrow:
            activeShape?.end = p
            setNeedsDisplay(bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard inkModeEnabled else { return }
        if var stroke = activeStroke {
            stroke.points.append(convert(event.locationInWindow, from: nil))
            commit(stroke: stroke)
            activeStroke = nil
        } else if var shape = activeShape {
            shape.end = convert(event.locationInWindow, from: nil)
            commit(shape: shape)
            activeShape = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)

        func draw(stroke: Stroke) {
            guard let first = stroke.points.first else { return }
            ctx.beginPath()
            ctx.move(to: first)
            for point in stroke.points.dropFirst() {
                ctx.addLine(to: point)
            }
            ctx.setStrokeColor(stroke.color.cgColor)
            ctx.setLineWidth(stroke.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }

        func draw(shape: Shape) {
            let strokeColor = shape.color.cgColor
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(shape.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            switch shape.kind {
            case .rectangle:
                let rect = rectFromPoints(a: shape.start, b: shape.end)
                ctx.stroke(rect)

            case .ellipse:
                let rect = rectFromPoints(a: shape.start, b: shape.end)
                ctx.strokeEllipse(in: rect)

            case .arrow:
                drawArrow(ctx: ctx, start: shape.start, end: shape.end, lineWidth: shape.width, fillColor: strokeColor)
            }
        }

        for item in items {
            switch item {
            case .stroke(let s):
                draw(stroke: s)
            case .shape(let sh):
                draw(shape: sh)
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
        guard !items.isEmpty else { return }
        redoStack.removeAll()
        items.removeAll()
        setNeedsDisplay(bounds)
    }

    func undo() {
        guard !items.isEmpty else { return }
        redoStack.append(items)
        _ = items.popLast()
        setNeedsDisplay(bounds)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        items = snapshot
        setNeedsDisplay(bounds)
    }

    private func commit(stroke: Stroke) {
        redoStack.removeAll()
        items.append(.stroke(stroke))
        setNeedsDisplay(bounds)
    }

    private func commit(shape: Shape) {
        redoStack.removeAll()
        items.append(.shape(shape))
        setNeedsDisplay(bounds)
    }

    private func erase(at point: CGPoint) {
        guard !items.isEmpty else { return }

        redoStack.removeAll()

        let radius = max(8, penWidth * 2)
        items.removeAll { item in
            itemIntersectsPoint(item: item, point: point, radius: radius)
        }
        setNeedsDisplay(bounds)
    }

    private func itemIntersectsPoint(item: Item, point: CGPoint, radius: CGFloat) -> Bool {
        switch item {
        case .stroke(let stroke):
            return strokeIntersectsPoint(stroke: stroke, point: point, radius: radius)
        case .shape(let shape):
            return shapeIntersectsPoint(shape: shape, point: point, radius: radius)
        }
    }

    private func strokeIntersectsPoint(stroke: Stroke, point: CGPoint, radius: CGFloat) -> Bool {
        let r2 = radius * radius
        let pts = stroke.points
        if pts.count == 1 {
            return (pts[0].x - point.x) * (pts[0].x - point.x) + (pts[0].y - point.y) * (pts[0].y - point.y) <= r2
        }
        for i in 0..<(pts.count - 1) {
            if distanceSquaredPointToSegment(p: point, a: pts[i], b: pts[i + 1]) <= r2 {
                return true
            }
        }
        return false
    }

    private func shapeIntersectsPoint(shape: Shape, point: CGPoint, radius: CGFloat) -> Bool {
        let r2 = radius * radius

        switch shape.kind {
        case .rectangle:
            let rect = rectFromPoints(a: shape.start, b: shape.end)
            let tl = CGPoint(x: rect.minX, y: rect.minY)
            let tr = CGPoint(x: rect.maxX, y: rect.minY)
            let br = CGPoint(x: rect.maxX, y: rect.maxY)
            let bl = CGPoint(x: rect.minX, y: rect.maxY)
            return (
                distanceSquaredPointToSegment(p: point, a: tl, b: tr) <= r2 ||
                distanceSquaredPointToSegment(p: point, a: tr, b: br) <= r2 ||
                distanceSquaredPointToSegment(p: point, a: br, b: bl) <= r2 ||
                distanceSquaredPointToSegment(p: point, a: bl, b: tl) <= r2
            )

        case .ellipse:
            let rect = rectFromPoints(a: shape.start, b: shape.end)
            guard rect.width > 1, rect.height > 1 else {
                return distanceSquaredPointToSegment(p: point, a: shape.start, b: shape.end) <= r2
            }
            let cx = rect.midX
            let cy = rect.midY
            let a = rect.width / 2
            let b = rect.height / 2
            let dx = point.x - cx
            let dy = point.y - cy
            let value = (dx * dx) / (a * a) + (dy * dy) / (b * b)
            // Rough boundary check: treat |value - 1| scaled by min(a,b) as distance.
            let approxDist = abs(value - 1) * min(a, b)
            return approxDist * approxDist <= r2

        case .arrow:
            return distanceSquaredPointToSegment(p: point, a: shape.start, b: shape.end) <= r2
        }
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

    private func distanceSquaredPointToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y

        let abLen2 = abx * abx + aby * aby
        if abLen2 <= .leastNonzeroMagnitude {
            return apx * apx + apy * apy
        }

        var t = (apx * abx + apy * aby) / abLen2
        t = max(0, min(1, t))
        let closest = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        let dx = p.x - closest.x
        let dy = p.y - closest.y
        return dx * dx + dy * dy
    }
}
