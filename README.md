# OverlayScribe

OverlayScribe is a local-only macOS menu bar app for drawing an always-on-top annotation overlay (no screenshotting).

## Requirements

- macOS 13+
- Xcode (for building/running the macOS app)
- Rust toolchain (pinned via `rust-toolchain.toml`)

## Build + test (Rust core)

From the repo root:

- Format: `cargo fmt --all`
- Lint: `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- Test: `cargo test --workspace`

## Build (macOS app)

From the repo root:

```sh
xcodebuild \
  -project apps/macos/OverlayScribe/OverlayScribe.xcodeproj \
  -scheme OverlayScribe \
  -destination 'platform=macOS' \
  build
```

To run, open the Xcode project and click Run:

- `apps/macos/OverlayScribe/OverlayScribe.xcodeproj`

## Run without opening Xcode

If you have `just` installed:

```sh
just macos-run
```

Or directly via `xcodebuild` (this keeps build products in `.derived-data/`):

```sh
xcodebuild \
  -project apps/macos/OverlayScribe/OverlayScribe.xcodeproj \
  -scheme OverlayScribe \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  build

open -n .derived-data/Build/Products/Debug/OverlayScribe.app
```

If you want logs in your terminal instead of launching via Finder, run the binary directly:

```sh
.derived-data/Build/Products/Debug/OverlayScribe.app/Contents/MacOS/OverlayScribe
```

## Usage

- Toggle Overlay: Shows/hides the transparent overlay window(s) (one per display).
- Toggle Ink Mode: Enables drawing (overlay captures mouse); when off, the overlay is click-through.
- Pen/Eraser: Pen draws strokes; eraser removes strokes/shapes by proximity.
- Shapes: Rectangle, ellipse, and arrow tools draw basic outlined shapes.
- Undo/Redo/Clear: Operate on the overlay contents.
- Color + Width: Adjust pen stroke appearance.
- Toolbox: Optional floating panel for faster tool/style switching.

### Keyboard shortcuts

Defaults (system-wide, via Carbon hotkeys):

- Toggle overlay: Ctrl+Shift+O
- Toggle ink mode: Ctrl+Shift+I
- Undo: Ctrl+Shift+Z
- Clear: Ctrl+Shift+X
- Toggle toolbox: Ctrl+Shift+T

When the app is active: Escape exits ink mode.

## UniFFI Swift bindings

Bindings can be generated locally (output is gitignored):

```sh
bash scripts/gen-bindings.sh
```

This generates Swift bindings under:

- `apps/macos/OverlayScribe/Generated/OverlayScribeCore/`

Notes:

- Generated files are not meant to be edited by hand.
- The current macOS app can build without generating bindings; wiring the Rust core into Swift is an incremental next step.
