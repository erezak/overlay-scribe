use overlay_scribe_core::{
    ArrowPath, ArrowRender, ColorRgba8, Document, Item, Point, Shape, ShapeKind, ShapeStyle, Store,
    Stroke, TextAlignH, TextAlignV,
};
use std::sync::Mutex;

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiColorRgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl From<FfiColorRgba8> for ColorRgba8 {
    fn from(value: FfiColorRgba8) -> Self {
        Self {
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

impl From<ColorRgba8> for FfiColorRgba8 {
    fn from(value: ColorRgba8) -> Self {
        Self {
            r: value.r,
            g: value.g,
            b: value.b,
            a: value.a,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiPoint {
    pub x: f32,
    pub y: f32,
}

impl From<FfiPoint> for Point {
    fn from(value: FfiPoint) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

impl From<Point> for FfiPoint {
    fn from(value: Point) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiStroke {
    pub id: u64,
    pub color: FfiColorRgba8,
    pub width: f32,
    pub points: Vec<FfiPoint>,
}

impl From<FfiStroke> for Stroke {
    fn from(value: FfiStroke) -> Self {
        Self {
            id: value.id,
            color: value.color.into(),
            width: value.width,
            points: value.points.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<Stroke> for FfiStroke {
    fn from(value: Stroke) -> Self {
        Self {
            id: value.id,
            color: value.color.into(),
            width: value.width,
            points: value.points.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum FfiShapeKind {
    Rectangle,
    RoundedRectangle,
    Ellipse,
    Arrow,
    CurvedArrow,
}

impl From<FfiShapeKind> for ShapeKind {
    fn from(value: FfiShapeKind) -> Self {
        match value {
            FfiShapeKind::Rectangle => ShapeKind::Rectangle,
            FfiShapeKind::RoundedRectangle => ShapeKind::RoundedRectangle,
            FfiShapeKind::Ellipse => ShapeKind::Ellipse,
            FfiShapeKind::Arrow => ShapeKind::Arrow,
            FfiShapeKind::CurvedArrow => ShapeKind::CurvedArrow,
        }
    }
}

impl From<ShapeKind> for FfiShapeKind {
    fn from(value: ShapeKind) -> Self {
        match value {
            ShapeKind::Rectangle => FfiShapeKind::Rectangle,
            ShapeKind::RoundedRectangle => FfiShapeKind::RoundedRectangle,
            ShapeKind::Ellipse => FfiShapeKind::Ellipse,
            ShapeKind::Arrow => FfiShapeKind::Arrow,
            ShapeKind::CurvedArrow => FfiShapeKind::CurvedArrow,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiShapeStyle {
    pub stroke_color: FfiColorRgba8,
    pub stroke_width: f32,
    pub fill_enabled: bool,
    pub fill_color: FfiColorRgba8,
    pub hatch_enabled: bool,
    pub corner_radius: f32,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum FfiTextAlignH {
    Left,
    Center,
    Right,
}

impl From<FfiTextAlignH> for TextAlignH {
    fn from(value: FfiTextAlignH) -> Self {
        match value {
            FfiTextAlignH::Left => TextAlignH::Left,
            FfiTextAlignH::Center => TextAlignH::Center,
            FfiTextAlignH::Right => TextAlignH::Right,
        }
    }
}

impl From<TextAlignH> for FfiTextAlignH {
    fn from(value: TextAlignH) -> Self {
        match value {
            TextAlignH::Left => FfiTextAlignH::Left,
            TextAlignH::Center => FfiTextAlignH::Center,
            TextAlignH::Right => FfiTextAlignH::Right,
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum FfiTextAlignV {
    Top,
    Middle,
    Bottom,
}

impl From<FfiTextAlignV> for TextAlignV {
    fn from(value: FfiTextAlignV) -> Self {
        match value {
            FfiTextAlignV::Top => TextAlignV::Top,
            FfiTextAlignV::Middle => TextAlignV::Middle,
            FfiTextAlignV::Bottom => TextAlignV::Bottom,
        }
    }
}

impl From<TextAlignV> for FfiTextAlignV {
    fn from(value: TextAlignV) -> Self {
        match value {
            TextAlignV::Top => FfiTextAlignV::Top,
            TextAlignV::Middle => FfiTextAlignV::Middle,
            TextAlignV::Bottom => FfiTextAlignV::Bottom,
        }
    }
}

impl From<FfiShapeStyle> for ShapeStyle {
    fn from(value: FfiShapeStyle) -> Self {
        Self {
            stroke_color: value.stroke_color.into(),
            stroke_width: value.stroke_width,
            fill_enabled: value.fill_enabled,
            fill_color: value.fill_color.into(),
            hatch_enabled: value.hatch_enabled,
            corner_radius: value.corner_radius,
        }
    }
}

impl From<ShapeStyle> for FfiShapeStyle {
    fn from(value: ShapeStyle) -> Self {
        Self {
            stroke_color: value.stroke_color.into(),
            stroke_width: value.stroke_width,
            fill_enabled: value.fill_enabled,
            fill_color: value.fill_color.into(),
            hatch_enabled: value.hatch_enabled,
            corner_radius: value.corner_radius,
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiShape {
    pub id: u64,
    pub kind: FfiShapeKind,
    pub style: FfiShapeStyle,
    pub start: FfiPoint,
    pub end: FfiPoint,
    pub start_attach_id: Option<u64>,
    pub end_attach_id: Option<u64>,
    pub start_attach_uv: Option<FfiPoint>,
    pub end_attach_uv: Option<FfiPoint>,
    pub text: String,
    pub text_align_h: FfiTextAlignH,
    pub text_align_v: FfiTextAlignV,
}

impl From<FfiShape> for Shape {
    fn from(value: FfiShape) -> Self {
        Self {
            id: value.id,
            kind: value.kind.into(),
            style: value.style.into(),
            start: value.start.into(),
            end: value.end.into(),
            start_attach_id: value.start_attach_id,
            end_attach_id: value.end_attach_id,
            start_attach_uv: value.start_attach_uv.map(Into::into),
            end_attach_uv: value.end_attach_uv.map(Into::into),
            text: value.text,
            text_align_h: value.text_align_h.into(),
            text_align_v: value.text_align_v.into(),
        }
    }
}

impl From<Shape> for FfiShape {
    fn from(value: Shape) -> Self {
        Self {
            id: value.id,
            kind: value.kind.into(),
            style: value.style.into(),
            start: value.start.into(),
            end: value.end.into(),
            start_attach_id: value.start_attach_id,
            end_attach_id: value.end_attach_id,
            start_attach_uv: value.start_attach_uv.map(Into::into),
            end_attach_uv: value.end_attach_uv.map(Into::into),
            text: value.text,
            text_align_h: value.text_align_h.into(),
            text_align_v: value.text_align_v.into(),
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum FfiArrowPathKind {
    Line,
    Quadratic,
    Cubic,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiArrowPath {
    pub kind: FfiArrowPathKind,
    // For quadratic, c1 is the control point.
    // For cubic, c1/c2 are control1/control2.
    pub c1: Option<FfiPoint>,
    pub c2: Option<FfiPoint>,
}

impl From<ArrowPath> for FfiArrowPath {
    fn from(value: ArrowPath) -> Self {
        match value {
            ArrowPath::Line => Self {
                kind: FfiArrowPathKind::Line,
                c1: None,
                c2: None,
            },
            ArrowPath::Quadratic { control } => Self {
                kind: FfiArrowPathKind::Quadratic,
                c1: Some(control.into()),
                c2: None,
            },
            ArrowPath::Cubic { c1, c2 } => Self {
                kind: FfiArrowPathKind::Cubic,
                c1: Some(c1.into()),
                c2: Some(c2.into()),
            },
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiArrowRender {
    pub shape_id: u64,
    pub style: FfiShapeStyle,
    pub start: FfiPoint,
    pub end: FfiPoint,
    pub path: FfiArrowPath,
    pub head_left: FfiPoint,
    pub head_right: FfiPoint,
}

impl From<ArrowRender> for FfiArrowRender {
    fn from(value: ArrowRender) -> Self {
        Self {
            shape_id: value.shape_id,
            style: value.style.into(),
            start: value.start.into(),
            end: value.end.into(),
            path: value.path.into(),
            head_left: value.head_left.into(),
            head_right: value.head_right.into(),
        }
    }
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum FfiItem {
    Stroke(FfiStroke),
    Shape(FfiShape),
}

impl From<FfiItem> for Item {
    fn from(value: FfiItem) -> Self {
        match value {
            FfiItem::Stroke(s) => Item::Stroke(s.into()),
            FfiItem::Shape(sh) => Item::Shape(sh.into()),
        }
    }
}

impl From<Item> for FfiItem {
    fn from(value: Item) -> Self {
        match value {
            Item::Stroke(s) => FfiItem::Stroke(s.into()),
            Item::Shape(sh) => FfiItem::Shape(sh.into()),
        }
    }
}

#[derive(uniffi::Object)]
pub struct CoreDocument {
    store: Mutex<Store>,
}

impl Default for CoreDocument {
    fn default() -> Self {
        Self::new()
    }
}

#[uniffi::export]
impl CoreDocument {
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            store: Mutex::new(Store::new()),
        }
    }

    pub fn items(&self) -> Vec<FfiItem> {
        self.store
            .lock()
            .expect("mutex poisoned")
            .items()
            .iter()
            .cloned()
            .map(Into::into)
            .collect()
    }

    pub fn arrow_renders(&self) -> Vec<FfiArrowRender> {
        let store = self.store.lock().expect("mutex poisoned");
        overlay_scribe_core::render::render_arrows(store.items())
            .into_iter()
            .map(Into::into)
            .collect()
    }

    pub fn begin_stroke(&self, color: FfiColorRgba8, width: f32, start: FfiPoint) -> FfiStroke {
        self.store
            .lock()
            .expect("mutex poisoned")
            .begin_stroke(color.into(), width, start.into())
            .into()
    }

    pub fn commit_stroke(&self, stroke: FfiStroke) {
        self.store
            .lock()
            .expect("mutex poisoned")
            .commit_stroke(stroke.into());
    }

    pub fn begin_shape(
        &self,
        kind: FfiShapeKind,
        style: FfiShapeStyle,
        start: FfiPoint,
    ) -> FfiShape {
        self.store
            .lock()
            .expect("mutex poisoned")
            .begin_shape(kind.into(), style.into(), start.into())
            .into()
    }

    pub fn commit_shape(&self, shape: FfiShape) {
        self.store
            .lock()
            .expect("mutex poisoned")
            .commit_shape(shape.into());
    }

    pub fn erase_at(&self, point: FfiPoint, radius: f32) -> bool {
        self.store
            .lock()
            .expect("mutex poisoned")
            .erase_at(point.into(), radius)
    }

    pub fn clear_all(&self) {
        self.store.lock().expect("mutex poisoned").clear_all();
    }

    pub fn can_undo(&self) -> bool {
        self.store.lock().expect("mutex poisoned").can_undo()
    }

    pub fn can_redo(&self) -> bool {
        self.store.lock().expect("mutex poisoned").can_redo()
    }

    pub fn undo(&self) -> bool {
        self.store.lock().expect("mutex poisoned").undo().is_ok()
    }

    pub fn redo(&self) -> bool {
        self.store.lock().expect("mutex poisoned").redo().is_ok()
    }

    pub fn to_json(&self) -> String {
        self.store
            .lock()
            .expect("mutex poisoned")
            .to_json()
            .unwrap_or_else(|_| serde_json::to_string(&Document::empty()).unwrap())
    }

    pub fn load_json(&self, json: String) -> bool {
        match Store::from_json(&json) {
            Ok(doc) => {
                self.store
                    .lock()
                    .expect("mutex poisoned")
                    .load_document(doc);
                true
            }
            Err(_) => false,
        }
    }
}
