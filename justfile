set shell := ["bash", "-cu"]

fmt:
  cargo fmt --all

lint:
  cargo clippy --workspace --all-targets --all-features -- -D warnings

test:
  cargo test --workspace

macos-build:
  xcodebuild \
    -project apps/macos/OverlayScribe/OverlayScribe.xcodeproj \
    -scheme OverlayScribe \
    -destination 'platform=macOS' \
    build

macos-run:
  bash scripts/run-macos.sh

gen-bindings:
  bash scripts/gen-bindings.sh
