uniffi::setup_scaffolding!();

mod types;

pub use types::{
    CoreDocument, FfiArrowPath, FfiArrowPathKind, FfiArrowRender, FfiColorRgba8, FfiItem, FfiPoint,
    FfiShape, FfiShapeKind, FfiShapeStyle, FfiStroke,
};
