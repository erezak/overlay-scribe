use crate::model::{ColorRgba8, Item, Point, Shape, ShapeKind, ShapeStyle, Stroke};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub version: u32,
    pub items: Vec<Item>,
}

impl Document {
    pub const CURRENT_VERSION: u32 = 2;

    pub fn empty() -> Self {
        Self {
            version: Self::CURRENT_VERSION,
            items: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DocumentV1 {
    version: u32,
    strokes: Vec<Stroke>,
}

#[derive(Debug, Error)]
pub enum StoreError {
    #[error("cannot undo")]
    CannotUndo,
    #[error("cannot redo")]
    CannotRedo,
    #[error("serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

#[derive(Debug, Clone)]
enum Edit {
    AddItem(Item),
    RemoveItem {
        index: usize,
        item: Item,
    },
    ReplaceItem {
        index: usize,
        before: Item,
        after: Item,
    },
    ReplaceAll {
        before: Vec<Item>,
        after: Vec<Item>,
    },
}

#[derive(Debug, Default)]
pub struct Store {
    items: Vec<Item>,
    undo: Vec<Edit>,
    redo: Vec<Edit>,
    next_id: u64,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn document(&self) -> Document {
        Document {
            version: Document::CURRENT_VERSION,
            items: self.items.clone(),
        }
    }

    pub fn load_document(&mut self, doc: Document) {
        self.items = doc.items;
        self.undo.clear();
        self.redo.clear();
        self.next_id = self
            .items
            .iter()
            .map(|item| match item {
                Item::Stroke(s) => s.id,
                Item::Shape(sh) => sh.id,
            })
            .max()
            .unwrap_or(0)
            .saturating_add(1);
    }

    pub fn to_json(&self) -> Result<String, StoreError> {
        Ok(serde_json::to_string(&self.document())?)
    }

    pub fn from_json(json: &str) -> Result<Document, StoreError> {
        let v2: Result<Document, serde_json::Error> = serde_json::from_str(json);
        if let Ok(doc) = v2 {
            return Ok(doc);
        }
        let v1: DocumentV1 = serde_json::from_str(json)?;
        Ok(Document {
            version: Document::CURRENT_VERSION,
            items: v1.strokes.into_iter().map(Item::Stroke).collect(),
        })
    }

    pub fn begin_stroke(&mut self, color: ColorRgba8, width: f32, start: Point) -> Stroke {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        Stroke {
            id,
            color,
            width,
            points: vec![start],
        }
    }

    pub fn commit_stroke(&mut self, stroke: Stroke) {
        self.apply(Edit::AddItem(Item::Stroke(stroke)));
    }

    pub fn begin_shape(&mut self, kind: ShapeKind, style: ShapeStyle, start: Point) -> Shape {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);
        Shape {
            id,
            kind,
            style,
            start,
            end: start,
            text: String::new(),
            text_align_h: Default::default(),
            text_align_v: Default::default(),
        }
    }

    pub fn commit_shape(&mut self, shape: Shape) {
        // If a shape with this id already exists, treat this as an update.
        // This supports editing operations (e.g., text changes) without duplicating items.
        if let Some((index, before)) =
            self.items
                .iter()
                .enumerate()
                .find_map(|(i, item)| match item {
                    Item::Shape(sh) if sh.id == shape.id => Some((i, Item::Shape(sh.clone()))),
                    _ => None,
                })
        {
            self.apply(Edit::ReplaceItem {
                index,
                before,
                after: Item::Shape(shape),
            });
        } else {
            self.apply(Edit::AddItem(Item::Shape(shape)));
        }
    }

    pub fn clear_all(&mut self) {
        let before = self.items.clone();
        self.apply(Edit::ReplaceAll {
            before,
            after: Vec::new(),
        });
    }

    pub fn items(&self) -> &[Item] {
        &self.items
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }

    pub fn undo(&mut self) -> Result<(), StoreError> {
        let edit = self.undo.pop().ok_or(StoreError::CannotUndo)?;
        let inverse = self.unapply(&edit);
        self.redo.push(inverse);
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), StoreError> {
        let edit = self.redo.pop().ok_or(StoreError::CannotRedo)?;
        let inverse = self.unapply(&edit);
        self.undo.push(inverse);
        Ok(())
    }

    pub fn erase_at(&mut self, point: Point, radius: f32) -> bool {
        if self.items.is_empty() {
            return false;
        }

        let before = self.items.clone();
        let r2 = radius * radius;
        self.items
            .retain(|item| !item_intersects_point(item, point, r2));
        let after = self.items.clone();

        if before == after {
            return false;
        }
        self.apply(Edit::ReplaceAll { before, after });
        true
    }

    fn apply(&mut self, edit: Edit) {
        self.redo.clear();
        self.apply_no_history(&edit);
        self.undo.push(edit);
    }

    fn apply_no_history(&mut self, edit: &Edit) {
        match edit {
            Edit::AddItem(item) => self.items.push(item.clone()),
            Edit::RemoveItem { index, .. } => {
                if *index < self.items.len() {
                    self.items.remove(*index);
                }
            }
            Edit::ReplaceItem { index, after, .. } => {
                if *index < self.items.len() {
                    self.items[*index] = after.clone();
                }
            }
            Edit::ReplaceAll { after, .. } => self.items = after.clone(),
        }
    }

    fn unapply(&mut self, edit: &Edit) -> Edit {
        match edit {
            Edit::AddItem(item) => {
                let index = self
                    .items
                    .iter()
                    .position(|x| x == item)
                    .unwrap_or_else(|| self.items.len().saturating_sub(1));
                if index < self.items.len() {
                    self.items.remove(index);
                }
                Edit::RemoveItem {
                    index,
                    item: item.clone(),
                }
            }
            Edit::RemoveItem { index, item } => {
                let insert_at = (*index).min(self.items.len());
                self.items.insert(insert_at, item.clone());
                Edit::AddItem(item.clone())
            }
            Edit::ReplaceItem {
                index,
                before,
                after,
            } => {
                if *index < self.items.len() {
                    self.items[*index] = before.clone();
                }
                Edit::ReplaceItem {
                    index: *index,
                    before: after.clone(),
                    after: before.clone(),
                }
            }
            Edit::ReplaceAll { before, after } => {
                self.items = before.clone();
                Edit::ReplaceAll {
                    before: after.clone(),
                    after: before.clone(),
                }
            }
        }
    }
}

fn item_intersects_point(item: &Item, p: Point, r2: f32) -> bool {
    match item {
        Item::Stroke(stroke) => stroke_intersects_point(stroke, p, r2),
        Item::Shape(shape) => shape_intersects_point(shape, p, r2),
    }
}

fn stroke_intersects_point(stroke: &Stroke, p: Point, r2: f32) -> bool {
    let pts = &stroke.points;
    if pts.len() == 1 {
        return dist2(pts[0], p) <= r2;
    }
    for w in pts.windows(2) {
        if dist2_point_to_segment(p, w[0], w[1]) <= r2 {
            return true;
        }
    }
    false
}

fn shape_intersects_point(shape: &Shape, p: Point, r2: f32) -> bool {
    match shape.kind {
        ShapeKind::Rectangle | ShapeKind::RoundedRectangle => {
            let (min_x, max_x) = if shape.start.x <= shape.end.x {
                (shape.start.x, shape.end.x)
            } else {
                (shape.end.x, shape.start.x)
            };
            let (min_y, max_y) = if shape.start.y <= shape.end.y {
                (shape.start.y, shape.end.y)
            } else {
                (shape.end.y, shape.start.y)
            };
            let tl = Point { x: min_x, y: min_y };
            let tr = Point { x: max_x, y: min_y };
            let br = Point { x: max_x, y: max_y };
            let bl = Point { x: min_x, y: max_y };
            dist2_point_to_segment(p, tl, tr) <= r2
                || dist2_point_to_segment(p, tr, br) <= r2
                || dist2_point_to_segment(p, br, bl) <= r2
                || dist2_point_to_segment(p, bl, tl) <= r2
        }
        ShapeKind::Ellipse => {
            let (min_x, max_x) = if shape.start.x <= shape.end.x {
                (shape.start.x, shape.end.x)
            } else {
                (shape.end.x, shape.start.x)
            };
            let (min_y, max_y) = if shape.start.y <= shape.end.y {
                (shape.start.y, shape.end.y)
            } else {
                (shape.end.y, shape.start.y)
            };
            let w = (max_x - min_x).abs();
            let h = (max_y - min_y).abs();
            if w <= f32::EPSILON || h <= f32::EPSILON {
                return dist2_point_to_segment(p, shape.start, shape.end) <= r2;
            }
            let cx = (min_x + max_x) * 0.5;
            let cy = (min_y + max_y) * 0.5;
            let a = w * 0.5;
            let b = h * 0.5;
            let dx = p.x - cx;
            let dy = p.y - cy;
            let value = (dx * dx) / (a * a) + (dy * dy) / (b * b);
            let approx_dist = (value - 1.0).abs() * a.min(b);
            approx_dist * approx_dist <= r2
        }
        ShapeKind::Arrow => dist2_point_to_segment(p, shape.start, shape.end) <= r2,
        ShapeKind::CurvedArrow => {
            let control = control_point_for_curve(shape.start, shape.end);
            let samples = approximate_quadratic(shape.start, control, shape.end, 16);
            for w in samples.windows(2) {
                if dist2_point_to_segment(p, w[0], w[1]) <= r2 {
                    return true;
                }
            }
            false
        }
    }
}

fn control_point_for_curve(start: Point, end: Point) -> Point {
    let mid = Point {
        x: (start.x + end.x) * 0.5,
        y: (start.y + end.y) * 0.5,
    };
    let dx = end.x - start.x;
    let dy = end.y - start.y;
    let len = (dx * dx + dy * dy).sqrt();
    if len <= 0.5 {
        return mid;
    }
    let ux = dx / len;
    let uy = dy / len;
    let perp_x = -uy;
    let perp_y = ux;
    let sign = if dx * dy >= 0.0 { 1.0 } else { -1.0 };
    let magnitude = (len * 0.22).clamp(18.0, 160.0);
    Point {
        x: mid.x + perp_x * magnitude * sign,
        y: mid.y + perp_y * magnitude * sign,
    }
}

fn approximate_quadratic(start: Point, control: Point, end: Point, steps: usize) -> Vec<Point> {
    let steps = steps.max(1);
    let mut out = Vec::with_capacity(steps + 1);
    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let u = 1.0 - t;
        out.push(Point {
            x: u * u * start.x + 2.0 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2.0 * u * t * control.y + t * t * end.y,
        });
    }
    out
}

fn dist2(a: Point, b: Point) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    dx * dx + dy * dy
}

fn dist2_point_to_segment(p: Point, a: Point, b: Point) -> f32 {
    let abx = b.x - a.x;
    let aby = b.y - a.y;
    let apx = p.x - a.x;
    let apy = p.y - a.y;
    let ab_len2 = abx * abx + aby * aby;
    if ab_len2 <= f32::EPSILON {
        return apx * apx + apy * apy;
    }
    let mut t = (apx * abx + apy * aby) / ab_len2;
    t = t.clamp(0.0, 1.0);
    let cx = a.x + t * abx;
    let cy = a.y + t * aby;
    let dx = p.x - cx;
    let dy = p.y - cy;
    dx * dx + dy * dy
}

#[cfg(test)]
mod tests {
    use super::*;

    fn red() -> ColorRgba8 {
        ColorRgba8 {
            r: 255,
            g: 0,
            b: 0,
            a: 255,
        }
    }

    fn green_fill() -> ColorRgba8 {
        ColorRgba8 {
            r: 0,
            g: 255,
            b: 0,
            a: 96,
        }
    }

    #[test]
    fn undo_redo_add_item_roundtrip() {
        let mut store = Store::new();
        let s = store.begin_stroke(red(), 3.0, Point { x: 1.0, y: 2.0 });
        store.commit_stroke(s.clone());
        assert_eq!(store.items().len(), 1);
        assert!(store.can_undo());

        store.undo().unwrap();
        assert_eq!(store.items().len(), 0);
        assert!(store.can_redo());

        store.redo().unwrap();
        assert_eq!(store.items().len(), 1);
        match &store.items()[0] {
            Item::Stroke(ss) => assert_eq!(ss.id, s.id),
            _ => panic!("expected stroke"),
        }
    }

    #[test]
    fn clear_all_is_undoable() {
        let mut store = Store::new();
        for i in 0..3 {
            let mut s = store.begin_stroke(
                red(),
                2.0,
                Point {
                    x: i as f32,
                    y: 0.0,
                },
            );
            s.points.push(Point {
                x: i as f32,
                y: 1.0,
            });
            store.commit_stroke(s);
        }
        assert_eq!(store.items().len(), 3);
        store.clear_all();
        assert_eq!(store.items().len(), 0);
        store.undo().unwrap();
        assert_eq!(store.items().len(), 3);
    }

    #[test]
    fn json_v1_roundtrip_loads() {
        let v1 = DocumentV1 {
            version: 1,
            strokes: vec![Stroke {
                id: 7,
                color: red(),
                width: 4.0,
                points: vec![Point { x: 1.0, y: 2.0 }],
            }],
        };
        let json = serde_json::to_string(&v1).unwrap();
        let doc = Store::from_json(&json).unwrap();
        assert_eq!(doc.items.len(), 1);
    }

    #[test]
    fn erase_removes_shape_and_is_undoable() {
        let mut store = Store::new();
        let style = ShapeStyle {
            stroke_color: red(),
            stroke_width: 3.0,
            fill_enabled: true,
            fill_color: green_fill(),
            hatch_enabled: false,
            corner_radius: 10.0,
        };
        let mut sh = store.begin_shape(ShapeKind::Rectangle, style, Point { x: 10.0, y: 10.0 });
        sh.end = Point { x: 50.0, y: 50.0 };
        store.commit_shape(sh);

        assert_eq!(store.items().len(), 1);
        assert!(store.erase_at(Point { x: 10.0, y: 10.0 }, 10.0));
        assert_eq!(store.items().len(), 0);
        store.undo().unwrap();
        assert_eq!(store.items().len(), 1);
    }
}
