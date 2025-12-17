# AGENTS.md

This file defines how coding agents should work in this repository.
Treat it as a README for agents: workflows, commands, boundaries, and stack decisions.

## Scaffolding rule for non-empty folders

If you are scaffolding the project and the target folder is not empty, check why.
If the folder is non-empty only because it already contains this `AGENTS.md` (and optionally other harmless repo metadata like `.gitignore`, `LICENSE`, or a `README.md`), continue scaffolding anyway.

Do not stop, error, or ask to delete the folder in that case.
Preserve existing files and add or merge new files safely.

## Quick commands (keep this section accurate)

Run the relevant commands for any change you make. If the repo structure changes, update these commands first.

### Rust (shared core)

* Format: `cargo fmt --all`
* Lint: `cargo clippy --workspace --all-targets --all-features -- -D warnings`
* Test: `cargo test --workspace`

### macOS (app shell)

* Build: `xcodebuild -scheme <AppSchemeName> -destination 'platform=macOS' build`
* Test: `xcodebuild -scheme <AppSchemeName> -destination 'platform=macOS' test`

### FFI and bindings

* Regenerate bindings: `./scripts/gen-bindings.sh`

### One command entrypoint (recommended)

Prefer a `justfile` or `makefile` that wraps the above commands into:

* `just fmt`
* `just lint`
* `just test`
* `just build`

If you add a wrapper, keep it thin, deterministic, and cross-platform where possible.

## Boundaries and non-negotiables

* Do not introduce network calls, telemetry, analytics, or remote logging unless explicitly requested.
* Do not add heavy dependencies without strong justification. Prefer standard libraries and small, focused crates.
* Never write secrets to disk, logs, source code, or CI output.
* Do not edit generated code by hand. Regenerate it from source definitions.
* Avoid large refactors unless asked. Keep changes minimal, reviewable, and easy to revert.
* Do not run destructive commands unless the user explicitly asked for them and the command is clearly scoped.

## Tech stack (authoritative)

This is the intended stack. If you propose deviating, explain why, compare tradeoffs, and keep the change localized.

### Shared core (portable)

* Language: Rust (stable toolchain)
* Build: Cargo workspace
* Formatting and linting: rustfmt, clippy
* Toolchain pinning: `rust-toolchain.toml`
* Core responsibilities:

  * Stroke data model and editing operations (ink, erase, shapes if supported)
  * Smoothing and simplification algorithms
  * Undo and redo
  * Serialization and file format (versioned)

Recommended Rust crates (choose conservatively):

* `serde` for serialization (document the chosen on-disk format)
* `thiserror` for typed errors
* `proptest` for property tests where invariants matter

### FFI boundary (portable)

* UniFFI for Swift bindings on macOS
* A small C ABI surface for other shells (Windows and Linux), used via:

  * C# P/Invoke on Windows
  * C or C++ FFI on Linux, as needed

FFI principles:

* Treat the FFI surface as a public API. Keep it small, stable, and versioned.
* Prefer simple value types, explicit ownership, and deterministic behavior.
* Add tests that exercise round-trips through the boundary.

### macOS shell (v1)

* Language: Swift
* UI: SwiftUI for settings and controls
* Windowing and overlay: AppKit
* Rendering: CoreGraphics and Quartz first, optionally Metal for performance
* Input: system event APIs (global shortcuts, event taps) with minimal permissions
* Build and packaging: Xcode, Swift Package Manager for Swift dependencies
* Formatting: `swift-format`
* Linting: SwiftLint (optional, prefer low-friction)

### Windows shell (later)

* UI: WinUI 3 (C#) for controls and settings
* Overlay windowing: Win32 interop as needed for transparent, always-on-top overlays and click-through modes
* Input: appropriate low-level hooks where required
* Bindings: Rust C ABI via P/Invoke

### Linux shell (later)

* UI: GTK 4 or Qt 6 for controls and settings
* Overlay: compositor and display-server-aware approach

  * Wayland: layer-shell where supported, with explicit constraints
  * X11: transparent composited overlay window where applicable
* Bindings: Rust C ABI

### CI (recommended)

* GitHub Actions
* Minimum checks:

  * Rust: fmt, clippy, test
  * macOS: build, test
* Add Windows and Linux checks when those shells exist.

## Research-first requirement

Before scaffolding or introducing a new component in this stack, do a short research pass:

1. Read the official documentation for the relevant API or tool.
2. Read one reputable best-practices reference.
3. Apply those practices when implementing, and codify any repo conventions you introduce.

At minimum, do this research pass when touching a component for the first time:

* SwiftUI state and architecture patterns, plus Swift concurrency
* AppKit overlay windows, transparency, click-through behavior, multi-display handling
* Rust library design, error handling, module boundaries, and public API design
* UniFFI interface design and Swift binding generation workflow
* Cross-platform CI patterns for Rust plus native shells

## How to work in this repo (agent workflow)

1. Read AGENTS.md and README.md, then scan `scripts/`, CI workflows, and the repo structure.
2. Propose a short plan (3 to 7 steps) before writing code.
3. Implement in small, coherent edits. Prefer incremental commits.
4. Run relevant commands from "Quick commands" and fix failures.
5. Update docs when behavior, APIs, permissions, or build steps change.

## Architecture guidelines

### Separation of concerns

* Platform shells own:

  * Overlay windows and z-order
  * Permissions and OS prompts
  * Global input and shortcuts
  * Display and multi-monitor handling
  * Rendering integration (the glue to draw on screen)

* Rust core owns:

  * Tool and stroke models
  * Smoothing, simplification, and edit operations
  * Undo and redo
  * Serialization and migrations
  * Deterministic behavior and testable logic

### Keep platform code out of the core

Do not introduce OS-specific concepts into the Rust core unless there is no alternative.
If the core needs timing or input metadata, represent it as platform-neutral data.

## Code style expectations

### Swift

* Avoid force unwraps and force tries.
* Prefer value types and clear state ownership.
* Keep UI updates on the main actor.
* Use Swift concurrency for background work.

Example (style, not a requirement):

```swift
struct ToolState: Equatable {
    var inkEnabled: Bool
    var activeTool: Tool
}
```

### Rust

* Avoid panics for expected failures in library code.
* Use `Result<T, E>` with typed errors for recoverable problems.
* Keep modules cohesive and document public types.

Example (style, not a requirement):

```rust
pub fn add_point(&mut self, point: Point) -> Result<(), StrokeError> {
    // ...
    Ok(())
}
```

## Testing expectations

* Rust:

  * Unit tests for core algorithms
  * Property tests for invariants (when it pays off)
* macOS:

  * Unit tests for non-UI logic
  * A small set of integration tests for mode toggling and serialization round trips

When fixing a bug, add a regression test where practical.

## Security and privacy expectations

* Default to local-only operation.
* Request the minimum OS permissions needed for the current feature set.
* Avoid logging user content. If logs are needed, keep them opt-in and scrubbed.
* Do not introduce background upload, external reporting, or surprise data collection.

## Record useful insights for future sessions

If you encounter non-obvious constraints, tricky OS behavior, performance traps, or decisions that would help a future agent session, append a short note to `docs/agent-insights.md`.

Only record insights that are important, durable, and likely to save time or prevent mistakes later.
Keep entries brief: date, context, and the takeaway.
