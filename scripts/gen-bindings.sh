#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

out_dir="$root_dir/apps/macos/OverlayScribe/Generated/OverlayScribeCore"
mkdir -p "$out_dir"

echo "==> Building UniFFI dylib (release)"
cargo build -p overlay_scribe_ffi --release

lib_path="$root_dir/target/release/liboverlay_scribe_ffi.dylib"
if [[ ! -f "$lib_path" ]]; then
  echo "Expected library at: $lib_path" >&2
  echo "If you're on Apple Silicon and building a different target, adjust this script." >&2
  exit 1
fi

echo "==> Generating Swift bindings via uniffi-bindgen"
cargo run -p overlay_scribe_ffi --release --bin uniffi-bindgen -- \
  generate \
  --library "$lib_path" \
  --language swift \
  --out-dir "$out_dir"

echo "==> Done. Swift bindings in: $out_dir"
