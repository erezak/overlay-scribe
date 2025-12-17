use overlay_scribe_core::{ColorRgba8, Document, Point, Stroke, StrokeStore};
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

#[derive(uniffi::Object)]
pub struct CoreDocument {
    store: Mutex<StrokeStore>,
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
            store: Mutex::new(StrokeStore::new()),
        }
    }

    pub fn strokes(&self) -> Vec<FfiStroke> {
        self.store
            .lock()
            .expect("mutex poisoned")
            .strokes()
            .iter()
            .cloned()
            .map(Into::into)
            .collect()
    }

    pub fn add_stroke(&self, stroke: FfiStroke) {
        self.store
            .lock()
            .expect("mutex poisoned")
            .commit_stroke(stroke.into());
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
        match StrokeStore::from_json(&json) {
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
