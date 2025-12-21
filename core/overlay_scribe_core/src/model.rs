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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Shape {
    pub id: u64,
    pub kind: ShapeKind,
    pub style: ShapeStyle,
    pub start: Point,
    pub end: Point,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "data", rename_all = "snake_case")]
pub enum Item {
    Stroke(Stroke),
    Shape(Shape),
}
