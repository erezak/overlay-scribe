use crate::model::{ColorRgba8, Point, Stroke};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub version: u32,
    pub strokes: Vec<Stroke>,
}

impl Document {
    pub const CURRENT_VERSION: u32 = 1;

    pub fn empty() -> Self {
        Self {
            version: Self::CURRENT_VERSION,
            strokes: Vec::new(),
        }
    }
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
    AddStroke(Stroke),
    RemoveStroke {
        index: usize,
        stroke: Stroke,
    },
    ReplaceAll {
        before: Vec<Stroke>,
        after: Vec<Stroke>,
    },
}

#[derive(Debug, Default)]
pub struct StrokeStore {
    strokes: Vec<Stroke>,
    undo: Vec<Edit>,
    redo: Vec<Edit>,
    next_id: u64,
}

impl StrokeStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn document(&self) -> Document {
        Document {
            version: Document::CURRENT_VERSION,
            strokes: self.strokes.clone(),
        }
    }

    pub fn load_document(&mut self, doc: Document) {
        self.strokes = doc.strokes;
        self.undo.clear();
        self.redo.clear();
        self.next_id = self
            .strokes
            .iter()
            .map(|s| s.id)
            .max()
            .unwrap_or(0)
            .saturating_add(1);
    }

    pub fn to_json(&self) -> Result<String, StoreError> {
        Ok(serde_json::to_string(&self.document())?)
    }

    pub fn from_json(json: &str) -> Result<Document, StoreError> {
        Ok(serde_json::from_str(json)?)
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
        self.apply(Edit::AddStroke(stroke));
    }

    pub fn remove_stroke_by_id(&mut self, stroke_id: u64) -> Option<()> {
        let index = self.strokes.iter().position(|s| s.id == stroke_id)?;
        let stroke = self.strokes[index].clone();
        self.apply(Edit::RemoveStroke { index, stroke });
        Some(())
    }

    pub fn clear_all(&mut self) {
        let before = self.strokes.clone();
        self.apply(Edit::ReplaceAll {
            before,
            after: Vec::new(),
        });
    }

    pub fn strokes(&self) -> &[Stroke] {
        &self.strokes
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

    fn apply(&mut self, edit: Edit) {
        self.redo.clear();
        self.apply_no_history(&edit);
        self.undo.push(edit);
    }

    fn apply_no_history(&mut self, edit: &Edit) {
        match edit {
            Edit::AddStroke(stroke) => self.strokes.push(stroke.clone()),
            Edit::RemoveStroke { index, .. } => {
                if *index < self.strokes.len() {
                    self.strokes.remove(*index);
                }
            }
            Edit::ReplaceAll { after, .. } => self.strokes = after.clone(),
        }
    }

    fn unapply(&mut self, edit: &Edit) -> Edit {
        match edit {
            Edit::AddStroke(stroke) => {
                let index = self
                    .strokes
                    .iter()
                    .position(|s| s.id == stroke.id)
                    .unwrap_or_else(|| self.strokes.len().saturating_sub(1));
                if index < self.strokes.len() {
                    self.strokes.remove(index);
                }
                Edit::RemoveStroke {
                    index,
                    stroke: stroke.clone(),
                }
            }
            Edit::RemoveStroke { index, stroke } => {
                let insert_at = (*index).min(self.strokes.len());
                self.strokes.insert(insert_at, stroke.clone());
                Edit::AddStroke(stroke.clone())
            }
            Edit::ReplaceAll { before, after } => {
                self.strokes = before.clone();
                Edit::ReplaceAll {
                    before: after.clone(),
                    after: before.clone(),
                }
            }
        }
    }
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

    #[test]
    fn undo_redo_add_stroke_roundtrip() {
        let mut store = StrokeStore::new();
        let s = store.begin_stroke(red(), 3.0, Point { x: 1.0, y: 2.0 });
        store.commit_stroke(s.clone());
        assert_eq!(store.strokes().len(), 1);
        assert!(store.can_undo());

        store.undo().unwrap();
        assert_eq!(store.strokes().len(), 0);
        assert!(store.can_redo());

        store.redo().unwrap();
        assert_eq!(store.strokes().len(), 1);
        assert_eq!(store.strokes()[0].id, s.id);
    }

    #[test]
    fn clear_all_is_undoable() {
        let mut store = StrokeStore::new();
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
        assert_eq!(store.strokes().len(), 3);
        store.clear_all();
        assert_eq!(store.strokes().len(), 0);
        store.undo().unwrap();
        assert_eq!(store.strokes().len(), 3);
    }
}
