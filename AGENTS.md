# Repository Guidelines

## Project Structure & Module Organization
- App code sits in `VolumeRendering-iOS/Source/`: `Core` hosts Metal shaders and transfer functions, `Helper` provides math plus SceneKit utilities, and `View` contains SwiftUI entry points with controller glue.
- Dataset bundles live in `VolumeRendering-iOS/Resource/Images` and transfer function presets in `VolumeRendering-iOS/Resource/TransferFunction`; keep large assets under Git LFS.
- UI assets use `Assets.xcassets`, while SwiftUI previews rely on `Preview Content`.

## Build, Test, and Development Commands
- `brew install git-lfs && git lfs pull` — ensure bundled datasets and TF presets are available locally.
- `open VolumeRendering-iOS.xcodeproj` — launch Xcode with the `VolumeRendering-iOS` scheme preconfigured.
- `xcodebuild -project VolumeRendering-iOS.xcodeproj -scheme VolumeRendering-iOS -configuration Debug build` — CI-friendly build of the app target.
- `xcodebuild -project VolumeRendering-iOS.xcodeproj -scheme VolumeRendering-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15 Pro' test` — placeholder until an XCTest target exists.

## Coding Style & Naming Conventions
- Use Swift 5 defaults: 4-space indentation, braces on the same line as declarations, and `guard` statements before any forced unwraps.
- Types and enums stay `UpperCamelCase`, properties and functions `lowerCamelCase`; keep `enum` raw values lowercase strings to match UI labels.
- Localize strings and comments in English, remove ad hoc debug prints when merging.
- Keep Metal shader files (`*.metal`) synchronized with their Swift wrappers; document shader parameters inline with concise comments.

## Testing Guidelines
- No automated tests ship today; prioritize UI smoke checks in the iOS Simulator (iPhone 15 Pro) before submitting changes.
- When adding tests, create an `XCTest` target mirroring `Source` packages, adopt the naming pattern `FeatureNameTests`, and cover both rendering configuration and transfer-function parsing.
- Record new manual validation steps in pull requests until XCTest coverage exists.

## Commit & Pull Request Guidelines
- Follow the existing history: imperative, concise commit titles (e.g., `Add dynamic MPR plane selection`) with optional detail in the body for shader/math tweaks.
- Each PR should include a summary of visual changes, test evidence (simulator log or screenshots), any new assets noted in `Resource/`, and links to related issues.
- Request review from at least one Metal/SceneKit contributor and flag breaking shader changes explicitly in the description.

## Asset & Data Handling
- Keep RAW volume files compressed (ZIP) under `Resource/Images/`; document acquisition source and voxel format in `README` updates.
- For new transfer functions, validate JSON against `TransferFunction` schema and include a representative screenshot demonstrating the preset.
