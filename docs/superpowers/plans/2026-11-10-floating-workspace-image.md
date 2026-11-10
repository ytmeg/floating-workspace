# Floating Workspace Image Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local PNG/JPEG import, non-destructive crop/zoom and brush/text/arrow annotations, with schema-v3 persistence and CoreGraphics PNG export.

**Architecture:** `ImageDocumentStore` owns file safety and schema-v3 models; `ImageCanvasView` and `ImageEditController` own editing; a shared renderer maps normalized image coordinates to canvas/export pixels; `ImageExporter` writes composite PNGs independently of screenshots or screen recording.

**Tech Stack:** Swift 6.3.3, SwiftPM, AppKit, CoreGraphics, ImageIO, Combine, XCTest, Xcode 27.2.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-11-10-floating-workspace-image-design.md`; local PNG/JPEG only, no network, screen recording, third-party image library, or remote editing.
- Import limit 50MB. Copy files into Application Support `FloatingWorkspace/Images/<uuid>.<ext>`; never overwrite or delete the user's original.
- Scale 0.1–4.0 with preserved aspect ratio. Crop x/y/width/height and all annotation coordinates are normalized to original-image space and clamped to 0...1.
- Models are non-destructive: original copy, optional crop, and separate annotations. Export uses cropped original pixel dimensions with no upscaling.
- `WorkspaceContent.schemaVersion = 3`, optional `imageDocument`; v1/v2 migrate to v3 while preserving note/blank/webDrafts/pin/frame. Save accepts only v3 and reuses exact-byte migration backup logic.
- Reject invalid format/decode/path/traversal/empty text/invalid points without mutating state. Export/save failure preserves dirty content and never overwrites the destination silently.
- Preserve all existing web behavior, glass themes, hotkeys, persistence, frame restore, and original eight acceptance groups.
- Build/test with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; local evidence under `.artifacts/`; no push or publication.

---

## File Map

- `Sources/FloatingWorkspaceCore/ImageDocument.swift`: document, point/rect, annotations, validation.
- `Sources/FloatingWorkspaceCore/ImageDocumentStore.swift`: import/replace/delete/path safety and updates.
- `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`: optional imageDocument and schema 3.
- `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`: v1/v2→v3 migration.
- `Sources/FloatingWorkspaceCore/ImageRenderer.swift`: shared layout and CoreGraphics drawing.
- `Sources/FloatingWorkspaceCore/ImageCanvasView.swift`: preview and mouse coordinate mapping.
- `Sources/FloatingWorkspaceCore/ImageEditController.swift`: toolbar and edit actions.
- `Sources/FloatingWorkspaceCore/ImageExporter.swift`: cropped composite and atomic PNG write.
- `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`: image container and mode state.
- `Sources/FloatingWorkspace/AppDelegate.swift`: open-panel import wiring.
- `Tests/FloatingWorkspaceCoreTests/ImageDocumentTests.swift`: models, migration, import/path safety.
- `Tests/FloatingWorkspaceCoreTests/ImageRendererTests.swift`: layout and pixel output.
- `Tests/FloatingWorkspaceCoreTests/ImageExporterTests.swift`: crop/annotation/export failures.
- `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`: image enablement and preservation.
- `Tests/Fixtures/images/`: generated PNG/JPEG fixtures for acceptance.
- `README.md` and `docs/testing/floating-workspace-phase1-acceptance.md`: image usage and final checks.

### Task 1: Image Document Model, Migration, and Safe Import

**Files:**
- Create: `Sources/FloatingWorkspaceCore/ImageDocument.swift`
- Create: `Sources/FloatingWorkspaceCore/ImageDocumentStore.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/ImageDocumentTests.swift`

**Interfaces:**
- Consumes: existing schema v2, RGBAColor, ContentStore, and migration backup logic.
- Produces: `ImageDocument`, `ImagePoint`, `ImageRect`, `ImageAnnotation`, and `ImageDocumentStore` for Tasks 2–4.

- [ ] **Step 1: Write failing model, migration, and import tests**

Cover:
- v1 and v2 migration to schema 3, preserving note/blank/webDrafts/pin and leaving original bytes/backup identical.
- Scale clamp to 0.1–4.0, crop clamp to unit bounds, invalid/empty text rejection, and finite point/color validation.
- PNG/JPEG import copies into `Images/<uuid>.<ext>` and decodes before model mutation.
- File >50MB, unsupported extension, invalid image data, absolute path/traversal, and delete outside the managed directory do not mutate state or touch external files.
- Replace creates a new UUID; delete removes only the managed copy.

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ImageDocumentTests`; expected missing-type failures.

- [ ] **Step 2: Implement normalized models**

Create:

```swift
public struct ImagePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
}

public struct ImageRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public static let full = ImageRect(x: 0, y: 0, width: 1, height: 1)
}

public enum ImageAnnotation: Codable, Equatable, Sendable {
    case pencil(points: [ImagePoint], color: RGBAColor, width: Double)
    case text(content: String, color: RGBAColor, fontSize: Double, position: ImagePoint)
    case arrow(start: ImagePoint, end: ImagePoint, color: RGBAColor, width: Double)
}

public struct ImageDocument: Codable, Equatable, Sendable {
    public var id: String
    public var originalRelativePath: String
    public var displayScale: Double
    public var cropRect: ImageRect
    public var annotations: [ImageAnnotation]
    public var updatedAt: Date
}
```

Provide public initializers and validation/clamping helpers for scale/crop/annotations. Coordinates and widths must be finite and nonnegative; text must trim to nonempty content.

- [ ] **Step 3: Implement schema v3 and safe store**

Add optional `imageDocument` to `WorkspaceContent`, default schema 3, and decode v1/v2 with nil imageDocument. `WorkspaceFileStore.load` migrates either to v3 with the existing exact-byte/no-duplicate/no-overwrite backup strategy; `save` accepts only v3.

`ImageDocumentStore` provides:

```swift
func importImage(at url: URL) throws -> ImageDocument
func replaceImage(at url: URL) throws -> ImageDocument
func deleteDocument() throws
func update(_ mutation: (inout ImageDocument) -> Void)
```

Validate extension and size, decode with ImageIO before model mutation, copy atomically into a new UUID destination, and resolve managed paths without following `..` or deleting outside `Images/`. Updates go through `ContentStore.update` so dirty/save/termination behavior is shared.

- [ ] **Step 4: Run focused/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ImageDocumentTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/ImageDocument.swift Sources/FloatingWorkspaceCore/ImageDocumentStore.swift Sources/FloatingWorkspaceCore/WorkspaceModels.swift Sources/FloatingWorkspaceCore/WorkspaceFileStore.swift Tests/FloatingWorkspaceCoreTests/ImageDocumentTests.swift
git commit -m "feat: add safe image document model and migration" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: model/import/migration and all previous tests PASS.

### Task 2: Image Canvas and Editing Controller

**Files:**
- Create: `Sources/FloatingWorkspaceCore/ImageRenderer.swift`
- Create: `Sources/FloatingWorkspaceCore/ImageCanvasView.swift`
- Create: `Sources/FloatingWorkspaceCore/ImageEditController.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/ImageRendererTests.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/ImageEditControllerTests.swift`

**Interfaces:**
- Consumes: `ImageDocumentStore` and normalized models.
- Produces: `ImageRenderer`, `ImageCanvasView`, and `ImageEditController` for Tasks 3–4.

- [ ] **Step 1: Write failing layout and edit-action tests**

Verify layout preserves aspect ratio at multiple scales and view sizes, normalized crop maps correctly to original pixels, and pencil/text/arrow coordinates map back after zoom/crop. Test displayScale/crop updates, undo last, clear all, reset crop, and no invalid mutation from empty text or out-of-range points.

- [ ] **Step 2: Implement shared layout and canvas**

`ImageRenderer` provides a value-type `Layout` with `imageRect`, `cropRect`, and scale conversions between normalized and display/original coordinates. `ImageCanvasView` uses that layout for preview and mouse handling. It displays the original image, crop frame, and all annotations, and emits normalized crop/pencil/arrow/text callbacks without touching files.

- [ ] **Step 3: Implement editing actions**

`ImageEditController` provides import/replace/delete, zoom slider, crop toggle/reset, brush/text/arrow selection, color well, undo/clear, and export action (Task 3 implements the actual export). Each action updates the model through the store and triggers shared persistence, not a parallel save path.

- [ ] **Step 4: Run focused/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'ImageRendererTests|ImageEditControllerTests'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/ImageRenderer.swift Sources/FloatingWorkspaceCore/ImageCanvasView.swift Sources/FloatingWorkspaceCore/ImageEditController.swift Tests/FloatingWorkspaceCoreTests/ImageRendererTests.swift Tests/FloatingWorkspaceCoreTests/ImageEditControllerTests.swift
git commit -m "feat: add image canvas and editing actions" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: layout/edit tests and all previous tests PASS.

### Task 3: CoreGraphics Composite PNG Export

**Files:**
- Create: `Sources/FloatingWorkspaceCore/ImageExporter.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/ImageExporterTests.swift`
- Modify: `Sources/FloatingWorkspaceCore/ImageRenderer.swift`
- Modify: `Sources/FloatingWorkspaceCore/ImageEditController.swift`

**Interfaces:**
- Consumes: `ImageRenderer` and `ImageDocument`.
- Produces: `ImageExporter.export(document:to:)` used by the export toolbar action.

- [ ] **Step 1: Write failing pixel and failure tests**

Use a tiny generated original with known pixels and annotations. Assert cropped output pixel dimensions, untouched original pixels, pencil/arrow color, text position, alpha channel, and JPEG-to-PNG conversion. Add an unwritable/invalid destination test proving the old destination bytes remain unchanged.

- [ ] **Step 2: Implement shared CoreGraphics rendering**

Extend `ImageRenderer` to draw the source crop, pencil paths, arrows with arrowheads, and text using scaled fonts/line widths in the same coordinate model used by the canvas. Render into an RGBA sRGB context with explicit alpha and no screenshot APIs.

- [ ] **Step 3: Implement atomic PNG export**

`ImageExporter.export(document:to:)` reads the managed original, computes the crop in original pixels with integer clamping, renders to a bitmap, creates PNG via `CGImageDestination`, finalizes before writing, and writes atomically with `Data.write(options: .atomic)`. Any decode/render/destination failure throws without replacing the target.

- [ ] **Step 4: Run focused/full tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter ImageExporterTests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/ImageExporter.swift Sources/FloatingWorkspaceCore/ImageRenderer.swift Sources/FloatingWorkspaceCore/ImageEditController.swift Tests/FloatingWorkspaceCoreTests/ImageExporterTests.swift
git commit -m "feat: export cropped annotated PNG images" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: pixel/failure tests and all previous tests PASS.

### Task 4: Workspace Integration and Full Acceptance

**Files:**
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceModels.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`
- Modify: `Sources/FloatingWorkspaceCore/ImageEditController.swift`
- Modify: `Sources/FloatingWorkspace/AppDelegate.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`
- Create: `Tests/Fixtures/images/generate-fixtures.swift`
- Modify: `README.md`
- Modify: `docs/testing/floating-workspace-phase1-acceptance.md`

**Interfaces:**
- Consumes: all image model/canvas/export code.
- Produces: enabled image mode and final signed-app evidence.

- [ ] **Step 1: Enable image mode and wire import/export**

Set `WorkspaceMode.image.isEnabledInPhase1 = true`. Add the image container/controller to `WorkspaceViewController` with cheap idempotent state/visibility updates. Keep note/blank/web modes and no-restyle-per-keystroke behavior. Wire open-panel import, drag/drop file URLs, export save panel, and all error labels. Panel title/background resets correctly on blank→image.

- [ ] **Step 2: Generate fixtures and document behavior**

`generate-fixtures.swift` creates a small colored PNG and JPEG with known pixels. README documents import/replace/delete, zoom/crop, annotations, undo/clear, export, original-file preservation, 50MB limit, and no network/screen recording. Acceptance docs add real image workflows and error paths.

- [ ] **Step 3: Run automated and signed-app acceptance**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
codesign --verify --verbose=2 dist/FloatingWorkspace.app
git diff --check
```

On the final signed app, verify PNG/JPEG import after moving the original, zoom/resize/crop, all annotations, undo/clear, export dimensions/colors, original-file immutability, replace/delete, invalid/oversize/decode/save/export failures, light/dark/reduced transparency, and all eight original groups. No failed check may be hidden by another passing check.

- [ ] **Step 4: Commit and perform whole-branch review**

```bash
git add Sources Tests README.md docs/testing/floating-workspace-phase1-acceptance.md
git commit -m "feat: enable image editing workspace mode" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Generate the full diff and dispatch the most capable available reviewer. Address Critical/Important findings through one reviewed fix wave. Local completion does not authorize push or publication.

---

## Completion Gate

Completion requires model/import/migration correctness, all automated tests, signed-package image editing/export evidence, and all eight original acceptance groups. Network images, video, screen recording, and remote editing remain outside this completion claim.
