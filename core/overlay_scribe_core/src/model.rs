use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ColorRgba8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Stroke {
    pub id: u64,
    pub color: ColorRgba8,
    pub width: f32,
    pub points: Vec<Point>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShapeKind {
    Rectangle,
    RoundedRectangle,
    Ellipse,
    Arrow,
    CurvedArrow,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ShapeStyle {
    pub stroke_color: ColorRgba8,
    pub stroke_width: f32,
    pub fill_enabled: bool,
    pub fill_color: ColorRgba8,
    pub hatch_enabled: bool,
    pub corner_radius: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TextAlignH {
    Left,
    #[default]
    Center,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum TextAlignV {
    Top,
    #[default]
    Middle,
    Bottom,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Shape {
    pub id: u64,
    pub kind: ShapeKind,
    pub style: ShapeStyle,
    pub start: Point,
    pub end: Point,

    // Optional connector anchors for arrow-like shapes.
    // When set, the corresponding endpoint should be resolved against the target shape.
    #[serde(default)]
    pub start_attach_id: Option<u64>,

    #[serde(default)]
    pub end_attach_id: Option<u64>,

    // Shape-local attachment locations for arrow-like shapes.
    // Interpreted as normalized UV in the target shape's axis-aligned rect:
    // u,v in [0,1]. When present, this is used to resolve the exact boundary
    // point the user dropped onto (instead of recomputing from the opposite end).
    #[serde(default)]
    pub start_attach_uv: Option<Point>,

    #[serde(default)]
    pub end_attach_uv: Option<Point>,

    #[serde(default)]
    pub text: String,

    #[serde(default)]
    pub text_align_h: TextAlignH,

    #[serde(default)]
    pub text_align_v: TextAlignV,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "data", rename_all = "snake_case")]
pub enum Item {
    Stroke(Stroke),
    Shape(Shape),
}
