use crate::geometry::{
    collect_closed_shapes, is_closed_shape, ClosedShapeHit, ClosedShapeKind, Rect,
};
use crate::model::{Item, Point, Shape, ShapeKind, ShapeStyle};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ArrowPath {
    Line,
    Quadratic { control: Point },
    Cubic { c1: Point, c2: Point },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ArrowRender {
    pub shape_id: u64,
    pub style: ShapeStyle,
    pub start: Point,
    pub end: Point,
    pub path: ArrowPath,
    pub head_left: Point,
    pub head_right: Point,
}

fn clamp01(v: f32) -> f32 {
    v.clamp(0.0, 1.0)
}

fn hypot(dx: f32, dy: f32) -> f32 {
    (dx * dx + dy * dy).sqrt()
}

fn vec_norm(dx: f32, dy: f32) -> Option<(f32, f32)> {
    let len = hypot(dx, dy);
    if len <= 1e-6 {
        None
    } else {
        Some((dx / len, dy / len))
    }
}

fn intersect_rect(rect: Rect, dx: f32, dy: f32) -> Point {
    let center = rect.center();
    let hx = rect.width() * 0.5;
    let hy = rect.height() * 0.5;
    let adx = dx.abs().max(1e-6);
    let ady = dy.abs().max(1e-6);
    let sx = hx / adx;
    let sy = hy / ady;
    let s = sx.min(sy);
    Point {
        x: center.x + dx * s,
        y: center.y + dy * s,
    }
}

fn intersect_ellipse(rect: Rect, dx: f32, dy: f32) -> Point {
    let center = rect.center();
    let rx = (rect.width() * 0.5).max(1e-6);
    let ry = (rect.height() * 0.5).max(1e-6);
    let sx = (dx.abs() / rx).max(1e-6);
    let sy = (dy.abs() / ry).max(1e-6);
    let s = sx.max(sy);
    Point {
        x: center.x + dx / s,
        y: center.y + dy / s,
    }
}

fn point_from_uv(rect: Rect, uv: Point) -> Point {
    Point {
        x: rect.min_x + clamp01(uv.x) * rect.width(),
        y: rect.min_y + clamp01(uv.y) * rect.height(),
    }
}

fn anchor_point_uv(target: &ClosedShapeHit, uv: Point) -> Point {
    let center = target.rect.center();
    let local = point_from_uv(target.rect, uv);
    let dx = local.x - center.x;
    let dy = local.y - center.y;
    if dx * dx + dy * dy <= 1e-6 {
        return center;
    }
    match target.kind {
        ClosedShapeKind::Ellipse => intersect_ellipse(target.rect, dx, dy),
        ClosedShapeKind::Rectangle | ClosedShapeKind::RoundedRectangle => {
            intersect_rect(target.rect, dx, dy)
        }
    }
}

fn compute_arrowhead(
    end: Point,
    tangent_dx: f32,
    tangent_dy: f32,
    stroke_width: f32,
) -> (Point, Point) {
    let Some((ux, uy)) = vec_norm(tangent_dx, tangent_dy) else {
        return (end, end);
    };
    let head_length = (stroke_width * 4.0).max(10.0);
    let head_width = (stroke_width * 3.0).max(8.0);
    let base = Point {
        x: end.x - ux * head_length,
        y: end.y - uy * head_length,
    };
    let px = -uy;
    let py = ux;
    let left = Point {
        x: base.x + px * (head_width * 0.5),
        y: base.y + py * (head_width * 0.5),
    };
    let right = Point {
        x: base.x - px * (head_width * 0.5),
        y: base.y - py * (head_width * 0.5),
    };
    (left, right)
}

fn point_at_quadratic(start: Point, control: Point, end: Point, t: f32) -> Point {
    let mt = 1.0 - t;
    let a = mt * mt;
    let b = 2.0 * mt * t;
    let c = t * t;
    Point {
        x: a * start.x + b * control.x + c * end.x,
        y: a * start.y + b * control.y + c * end.y,
    }
}

fn point_at_cubic(start: Point, c1: Point, c2: Point, end: Point, t: f32) -> Point {
    let mt = 1.0 - t;
    let a = mt * mt * mt;
    let b = 3.0 * mt * mt * t;
    let c = 3.0 * mt * t * t;
    let d = t * t * t;
    Point {
        x: a * start.x + b * c1.x + c * c2.x + d * end.x,
        y: a * start.y + b * c1.y + c * c2.y + d * end.y,
    }
}

fn cubic_controls_through_midpoint(start: Point, end: Point, waypoint: Point) -> (Point, Point) {
    // Symmetric construction so B(0.5)=waypoint.
    let k = 4.0 / 3.0;
    let c1 = Point {
        x: start.x + (waypoint.x - start.x) * k,
        y: start.y + (waypoint.y - start.y) * k,
    };
    let c2 = Point {
        x: end.x + (waypoint.x - end.x) * k,
        y: end.y + (waypoint.y - end.y) * k,
    };
    (c1, c2)
}

fn cubic_controls_pull_toward_waypoint(
    start: Point,
    end: Point,
    waypoint: Point,
) -> (Point, Point) {
    let d1 = hypot(waypoint.x - start.x, waypoint.y - start.y);
    let d2 = hypot(waypoint.x - end.x, waypoint.y - end.y);
    let d = (d1 + d2).max(1e-6);
    let a = (d / (d + 140.0)).clamp(0.50, 0.78);
    let c1 = Point {
        x: start.x + (waypoint.x - start.x) * a,
        y: start.y + (waypoint.y - start.y) * a,
    };
    let c2 = Point {
        x: end.x + (waypoint.x - end.x) * a,
        y: end.y + (waypoint.y - end.y) * a,
    };
    (c1, c2)
}

fn sample_inside_hits(
    start: Point,
    end: Point,
    attached_ids: &[u64],
    obstacles: &[ClosedShapeHit],
    point_at: impl Fn(f32) -> Point,
) -> (Vec<(u64, i32)>, i32) {
    let endpoint_allowance = 14.0;
    let steps = 800;
    let margin = 18.0;

    let mut hits_by_id: Vec<(u64, i32)> = Vec::new();
    let mut total = 0;

    let mut expanded: Vec<(u64, Rect)> = Vec::new();
    for o in obstacles {
        expanded.push((o.id, o.rect.inflate(margin, margin)));
    }

    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let p = point_at(t);

        for (id, rect) in expanded.iter().copied() {
            if attached_ids.contains(&id) {
                let ds = hypot(p.x - start.x, p.y - start.y);
                let de = hypot(p.x - end.x, p.y - end.y);
                if ds <= endpoint_allowance || de <= endpoint_allowance {
                    continue;
                }
            }

            if !rect.contains(p) {
                continue;
            }

            // Use the original rect containment as our inside test.
            let Some(ob) = obstacles.iter().find(|o| o.id == id) else {
                continue;
            };
            if ob.rect.contains(p) {
                total += 1;
                if let Some((_k, v)) = hits_by_id.iter_mut().find(|(k, _)| *k == id) {
                    *v += 1;
                } else {
                    hits_by_id.push((id, 1));
                }
            }
        }
    }

    (hits_by_id, total)
}

fn waypoint_candidates(start: Point, end: Point, obstacles: &[ClosedShapeHit]) -> Vec<Point> {
    let margin = 26.0;
    let mid = Point {
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5,
    };

    let primary: Vec<ClosedShapeHit> = obstacles.iter().take(6).copied().collect();
    let mut union: Option<Rect> = None;

    let mut points: Vec<Point> = Vec::new();
    for hit in &primary {
        let r = hit.rect.inflate(margin, margin);
        union = Some(union.map(|u| u.union(r)).unwrap_or(r));

        // Midpoints.
        points.push(Point {
            x: (r.min_x + r.max_x) * 0.5,
            y: r.min_y - margin,
        });
        points.push(Point {
            x: (r.min_x + r.max_x) * 0.5,
            y: r.max_y + margin,
        });
        points.push(Point {
            x: r.min_x - margin,
            y: (r.min_y + r.max_y) * 0.5,
        });
        points.push(Point {
            x: r.max_x + margin,
            y: (r.min_y + r.max_y) * 0.5,
        });

        // Corners.
        points.push(Point {
            x: r.min_x - margin,
            y: r.min_y - margin,
        });
        points.push(Point {
            x: r.max_x + margin,
            y: r.min_y - margin,
        });
        points.push(Point {
            x: r.min_x - margin,
            y: r.max_y + margin,
        });
        points.push(Point {
            x: r.max_x + margin,
            y: r.max_y + margin,
        });

        // Midline.
        points.push(Point {
            x: mid.x,
            y: r.min_y - margin,
        });
        points.push(Point {
            x: mid.x,
            y: r.max_y + margin,
        });
    }

    if let Some(u) = union {
        points.push(Point {
            x: (u.min_x + u.max_x) * 0.5,
            y: u.min_y - margin * 2.0,
        });
        points.push(Point {
            x: (u.min_x + u.max_x) * 0.5,
            y: u.max_y + margin * 2.0,
        });
        points.push(Point {
            x: u.min_x - margin * 2.0,
            y: (u.min_y + u.max_y) * 0.5,
        });
        points.push(Point {
            x: u.max_x + margin * 2.0,
            y: (u.min_y + u.max_y) * 0.5,
        });
    }

    // Filter out waypoints that are inside any obstacle.
    points.retain(|p| {
        !obstacles
            .iter()
            .any(|o| o.rect.inflate(margin, margin).contains(*p))
    });

    // Dedup-ish and cap.
    let mut out: Vec<Point> = Vec::new();
    for p in points {
        if !out.iter().any(|q| hypot(q.x - p.x, q.y - p.y) < 3.0) {
            out.push(p);
            if out.len() >= 24 {
                break;
            }
        }
    }
    out
}

fn choose_curved_path(
    start: Point,
    end: Point,
    quad_control: Point,
    attached_ids: &[u64],
    obstacles: &[ClosedShapeHit],
) -> ArrowPath {
    let (hits_by_id, quad_hits) = sample_inside_hits(start, end, attached_ids, obstacles, |t| {
        point_at_quadratic(start, quad_control, end, t)
    });
    if quad_hits == 0 {
        return ArrowPath::Quadratic {
            control: quad_control,
        };
    }

    // Order obstacles by hit severity.
    let mut ordered = obstacles.to_vec();
    ordered.sort_by_key(|o| {
        let hits = hits_by_id
            .iter()
            .find(|(id, _)| *id == o.id)
            .map(|(_, v)| *v)
            .unwrap_or(0);
        -hits
    });

    let candidates = waypoint_candidates(start, end, &ordered);
    let mut best: Option<(ArrowPath, i32, f32)> = None;

    for w in candidates {
        let pairs = [
            cubic_controls_through_midpoint(start, end, w),
            cubic_controls_pull_toward_waypoint(start, end, w),
        ];
        for (c1, c2) in pairs {
            let (_, hits) = sample_inside_hits(start, end, attached_ids, obstacles, |t| {
                point_at_cubic(start, c1, c2, end, t)
            });

            let length_score =
                hypot(c1.x - start.x, c1.y - start.y) + hypot(c2.x - end.x, c2.y - end.y);
            let score = length_score;
            match best {
                None => best = Some((ArrowPath::Cubic { c1, c2 }, hits, score)),
                Some((_, best_hits, best_score)) => {
                    if hits < best_hits || (hits == best_hits && score < best_score) {
                        best = Some((ArrowPath::Cubic { c1, c2 }, hits, score));
                    }
                }
            }

            if hits == 0 {
                return ArrowPath::Cubic { c1, c2 };
            }
        }
    }

    if let Some((path, hits, _)) = best {
        if hits < quad_hits {
            return path;
        }
    }

    ArrowPath::Quadratic {
        control: quad_control,
    }
}

fn quad_control_simple(start: Point, end: Point) -> Point {
    let mid = Point {
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5,
    };
    let dx = end.x - start.x;
    let dy = end.y - start.y;
    let len = hypot(dx, dy);
    if len <= 1e-3 {
        return mid;
    }
    let ux = dx / len;
    let uy = dy / len;
    let perp = Point { x: -uy, y: ux };
    let magnitude = (len * 0.22).clamp(18.0, 160.0);

    // Legacy-ish sign rule.
    let sign = if dx * dy >= 0.0 { 1.0 } else { -1.0 };
    Point {
        x: mid.x + perp.x * magnitude * sign,
        y: mid.y + perp.y * magnitude * sign,
    }
}

fn resolve_endpoints(shape: &Shape, closed: &[ClosedShapeHit]) -> (Point, Point, Vec<u64>) {
    let mut start = shape.start;
    let mut end = shape.end;
    let mut attached = Vec::new();

    if let Some(id) = shape.start_attach_id {
        if let Some(target) = closed.iter().find(|s| s.id == id) {
            attached.push(id);
            if let Some(uv) = shape.start_attach_uv {
                start = anchor_point_uv(target, uv);
            } else {
                let c = target.rect.center();
                let dx = end.x - c.x;
                let dy = end.y - c.y;
                start = match target.kind {
                    ClosedShapeKind::Ellipse => intersect_ellipse(target.rect, dx, dy),
                    ClosedShapeKind::Rectangle | ClosedShapeKind::RoundedRectangle => {
                        intersect_rect(target.rect, dx, dy)
                    }
                };
            }
        }
    }

    if let Some(id) = shape.end_attach_id {
        if let Some(target) = closed.iter().find(|s| s.id == id) {
            if !attached.contains(&id) {
                attached.push(id);
            }
            if let Some(uv) = shape.end_attach_uv {
                end = anchor_point_uv(target, uv);
            } else {
                let c = target.rect.center();
                let dx = start.x - c.x;
                let dy = start.y - c.y;
                end = match target.kind {
                    ClosedShapeKind::Ellipse => intersect_ellipse(target.rect, dx, dy),
                    ClosedShapeKind::Rectangle | ClosedShapeKind::RoundedRectangle => {
                        intersect_rect(target.rect, dx, dy)
                    }
                };
            }
        }
    }

    (start, end, attached)
}

pub fn render_arrows(items: &[Item]) -> Vec<ArrowRender> {
    let closed = collect_closed_shapes(items);
    let mut out = Vec::new();

    for it in items {
        let Item::Shape(shape) = it else { continue };
        if !matches!(shape.kind, ShapeKind::Arrow | ShapeKind::CurvedArrow) {
            continue;
        }

        let (start, end, attached_ids) = resolve_endpoints(shape, &closed);
        let dx = end.x - start.x;
        let dy = end.y - start.y;
        let len = hypot(dx, dy);
        if len <= 0.5 {
            continue;
        }

        let path = match shape.kind {
            ShapeKind::Arrow => ArrowPath::Line,
            ShapeKind::CurvedArrow => {
                let quad = quad_control_simple(start, end);
                choose_curved_path(start, end, quad, &attached_ids, &closed)
            }
            _ => ArrowPath::Line,
        };

        // Compute tangent at end for arrowhead.
        let (tx, ty) = match path {
            ArrowPath::Line => (dx, dy),
            ArrowPath::Quadratic { control } => (end.x - control.x, end.y - control.y),
            ArrowPath::Cubic { c2, .. } => (end.x - c2.x, end.y - c2.y),
        };
        let (hl, hr) = compute_arrowhead(end, tx, ty, shape.style.stroke_width);

        out.push(ArrowRender {
            shape_id: shape.id,
            style: shape.style,
            start,
            end,
            path,
            head_left: hl,
            head_right: hr,
        });
    }

    out
}

pub fn arrow_obstacle_ids(items: &[Item], arrow_shape_id: u64) -> Vec<u64> {
    // Helper for shells that want debug info (or future usage).
    let closed = collect_closed_shapes(items);
    for it in items {
        let Item::Shape(sh) = it else { continue };
        if sh.id != arrow_shape_id {
            continue;
        }
        if !matches!(sh.kind, ShapeKind::Arrow | ShapeKind::CurvedArrow) {
            return Vec::new();
        }
        let (_, _, attached_ids) = resolve_endpoints(sh, &closed);
        let mut out: Vec<u64> = closed
            .iter()
            .map(|s| s.id)
            .filter(|id| !attached_ids.contains(id))
            .collect();
        out.sort_unstable();
        return out;
    }
    Vec::new()
}

pub fn is_arrow_like(kind: ShapeKind) -> bool {
    matches!(kind, ShapeKind::Arrow | ShapeKind::CurvedArrow)
}

pub fn is_closed(kind: ShapeKind) -> bool {
    is_closed_shape(kind)
}
