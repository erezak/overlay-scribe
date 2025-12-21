uniffi::setup_scaffolding!();

mod types;

pub use types::{
    CoreDocument, FfiColorRgba8, FfiItem, FfiPoint, FfiShape, FfiShapeKind, FfiShapeStyle,
    FfiStroke,
};
