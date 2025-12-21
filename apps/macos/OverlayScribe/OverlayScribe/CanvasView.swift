import AppKit

@MainActor
final class CanvasView: NSView {
    var inkModeEnabled: Bool = false
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
            activeStroke = document.beginStroke(color: penColor.asFfiColor(), width: Float(penWidth), start: p.asFfiPoint())
        case .eraser:
            erase(at: p)
        case .rectangle:
            activeShape = document.beginShape(kind: .rectangle, style: currentShapeStyle(), start: p.asFfiPoint())
        case .roundedRectangle:
            activeShape = document.beginShape(kind: .roundedRectangle, style: currentShapeStyle(), start: p.asFfiPoint())
        case .ellipse:
            activeShape = document.beginShape(kind: .ellipse, style: currentShapeStyle(), start: p.asFfiPoint())
        case .arrow:
            activeShape = document.beginShape(kind: .arrow, style: currentShapeStyle(), start: p.asFfiPoint())
        case .curvedArrow:
            activeShape = document.beginShape(kind: .curvedArrow, style: currentShapeStyle(), start: p.asFfiPoint())
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard inkModeEnabled else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch selectedTool {
        case .pen:
            activeStroke?.points.append(p.asFfiPoint())
            setNeedsDisplay(bounds)
        case .eraser:
            erase(at: p)
        case .rectangle, .roundedRectangle, .ellipse, .arrow, .curvedArrow:
            activeShape?.end = p.asFfiPoint()
            setNeedsDisplay(bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard inkModeEnabled else { return }
        if var stroke = activeStroke {
            stroke.points.append(convert(event.locationInWindow, from: nil).asFfiPoint())
            commit(stroke: stroke)
            activeStroke = nil
        } else if var shape = activeShape {
            shape.end = convert(event.locationInWindow, from: nil).asFfiPoint()
            commit(shape: shape)
            activeShape = nil
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

            case .roundedRectangle:
                let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
                let radius = min(CGFloat(shape.style.cornerRadius), min(rect.width, rect.height) / 2)
                let path = roundedRectPath(in: rect, radius: radius)
                fillAndHatch(path: path)
                ctx.addPath(path)
                ctx.strokePath()

            case .ellipse:
                let rect = rectFromPoints(a: shape.start.asCGPoint(), b: shape.end.asCGPoint())
                let path = CGPath(ellipseIn: rect, transform: nil)
                fillAndHatch(path: path)
                ctx.strokeEllipse(in: rect)

            case .arrow:
                drawArrow(ctx: ctx, start: shape.start.asCGPoint(), end: shape.end.asCGPoint(), lineWidth: CGFloat(shape.style.strokeWidth), fillColor: strokeColor)

            case .curvedArrow:
                drawCurvedArrow(ctx: ctx, start: shape.start.asCGPoint(), end: shape.end.asCGPoint(), lineWidth: CGFloat(shape.style.strokeWidth), strokeColor: strokeColor)
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
        document.clearAll()
        refreshItems()
        setNeedsDisplay(bounds)
    }

    func undo() {
        guard document.undo() else { return }
        refreshItems()
        setNeedsDisplay(bounds)
    }

    func redo() {
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
