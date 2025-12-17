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
        case roundedRectangle
        case ellipse
        case arrow
        case curvedArrow
    }

    struct Shape {
        var kind: ShapeKind
        var color: NSColor
        var width: CGFloat
        var fillEnabled: Bool
        var fillColor: NSColor
        var hatchEnabled: Bool
        var cornerRadius: CGFloat
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

    // Shape styling (applied when a shape is created).
    var shapeFillEnabled: Bool = true
    var shapeFillColor: NSColor = NSColor.systemGreen.withAlphaComponent(0.35)
    var shapeHatchEnabled: Bool = false
    var shapeCornerRadius: CGFloat = 18

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

        func makeShape(kind: ShapeKind) -> Shape {
            Shape(
                kind: kind,
                color: penColor,
                width: penWidth,
                fillEnabled: shapeFillEnabled,
                fillColor: shapeFillColor,
                hatchEnabled: shapeHatchEnabled,
                cornerRadius: shapeCornerRadius,
                start: p,
                end: p
            )
        }
        switch selectedTool {
        case .pen:
            activeStroke = Stroke(color: penColor, width: penWidth, points: [p])
        case .eraser:
            erase(at: p)
        case .rectangle:
            activeShape = makeShape(kind: .rectangle)
        case .roundedRectangle:
            activeShape = makeShape(kind: .roundedRectangle)
        case .ellipse:
            activeShape = makeShape(kind: .ellipse)
        case .arrow:
            activeShape = makeShape(kind: .arrow)
        case .curvedArrow:
            activeShape = makeShape(kind: .curvedArrow)
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
        case .rectangle, .roundedRectangle, .ellipse, .arrow, .curvedArrow:
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

            func fillAndHatch(path: CGPath) {
                guard shape.fillEnabled else { return }

                ctx.saveGState()
                ctx.addPath(path)
                ctx.setFillColor(shape.fillColor.cgColor)
                ctx.fillPath()
                ctx.restoreGState()

                guard shape.hatchEnabled else { return }

                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                drawHatch(ctx: ctx, in: path.boundingBox, strokeColor: strokeColor, lineWidth: max(1, shape.width * 0.6))
                ctx.restoreGState()
            }

            switch shape.kind {
            case .rectangle:
                let rect = rectFromPoints(a: shape.start, b: shape.end)
                let path = CGPath(rect: rect, transform: nil)
                fillAndHatch(path: path)
                ctx.stroke(rect)

            case .roundedRectangle:
                let rect = rectFromPoints(a: shape.start, b: shape.end)
                let radius = min(shape.cornerRadius, min(rect.width, rect.height) / 2)
                let path = roundedRectPath(in: rect, radius: radius)
                fillAndHatch(path: path)
                ctx.addPath(path)
                ctx.strokePath()

            case .ellipse:
                let rect = rectFromPoints(a: shape.start, b: shape.end)
                let path = CGPath(ellipseIn: rect, transform: nil)
                fillAndHatch(path: path)
                ctx.strokeEllipse(in: rect)

            case .arrow:
                drawArrow(ctx: ctx, start: shape.start, end: shape.end, lineWidth: shape.width, fillColor: strokeColor)

            case .curvedArrow:
                drawCurvedArrow(ctx: ctx, start: shape.start, end: shape.end, lineWidth: shape.width, strokeColor: strokeColor)
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

        case .roundedRectangle:
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

        case .curvedArrow:
            let samples = approximateQuadraticBezier(
                start: shape.start,
                control: controlPointForCurve(start: shape.start, end: shape.end),
                end: shape.end,
                steps: 16
            )
            guard samples.count >= 2 else { return false }
            for i in 0..<(samples.count - 1) {
                if distanceSquaredPointToSegment(p: point, a: samples[i], b: samples[i + 1]) <= r2 {
                    return true
                }
            }
            return false
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
