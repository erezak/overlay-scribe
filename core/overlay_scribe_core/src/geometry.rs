use crate::model::{Item, Point, Shape, ShapeKind};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub min_x: f32,
    pub min_y: f32,
    pub max_x: f32,
    pub max_y: f32,
}

impl Rect {
    pub fn from_points(a: Point, b: Point) -> Self {
        let min_x = a.x.min(b.x);
        let max_x = a.x.max(b.x);
        let min_y = a.y.min(b.y);
        let max_y = a.y.max(b.y);
        Self {
            min_x,
            min_y,
            max_x,
            max_y,
        }
    }

    pub fn width(&self) -> f32 {
        self.max_x - self.min_x
    }

    pub fn height(&self) -> f32 {
        self.max_y - self.min_y
    }

    pub fn center(&self) -> Point {
        Point {
            x: (self.min_x + self.max_x) * 0.5,
            y: (self.min_y + self.max_y) * 0.5,
        }
    }

    pub fn contains(&self, p: Point) -> bool {
        p.x >= self.min_x && p.x <= self.max_x && p.y >= self.min_y && p.y <= self.max_y
    }

    pub fn inflate(&self, dx: f32, dy: f32) -> Self {
        Self {
            min_x: self.min_x - dx,
            min_y: self.min_y - dy,
            max_x: self.max_x + dx,
            max_y: self.max_y + dy,
        }
    }

    pub fn union(&self, other: Rect) -> Rect {
        Rect {
            min_x: self.min_x.min(other.min_x),
            min_y: self.min_y.min(other.min_y),
            max_x: self.max_x.max(other.max_x),
            max_y: self.max_y.max(other.max_y),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClosedShapeKind {
    Rectangle,
    RoundedRectangle,
    Ellipse,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ClosedShapeHit {
    pub id: u64,
    pub kind: ClosedShapeKind,
    pub rect: Rect,
}

pub fn is_closed_shape(kind: ShapeKind) -> bool {
    matches!(
        kind,
        ShapeKind::Rectangle | ShapeKind::RoundedRectangle | ShapeKind::Ellipse
    )
}

pub fn closed_shape_kind(kind: ShapeKind) -> Option<ClosedShapeKind> {
    match kind {
        ShapeKind::Rectangle => Some(ClosedShapeKind::Rectangle),
        ShapeKind::RoundedRectangle => Some(ClosedShapeKind::RoundedRectangle),
        ShapeKind::Ellipse => Some(ClosedShapeKind::Ellipse),
        _ => None,
    }
}

pub fn rect_for_shape(shape: &Shape) -> Rect {
    Rect::from_points(shape.start, shape.end)
}

pub fn collect_closed_shapes(items: &[Item]) -> Vec<ClosedShapeHit> {
    let mut out = Vec::new();
    for it in items {
        let Item::Shape(sh) = it else { continue };
        let Some(kind) = closed_shape_kind(sh.kind) else {
            continue;
        };
        out.push(ClosedShapeHit {
            id: sh.id,
            kind,
            rect: rect_for_shape(sh),
        });
    }
    out
}
