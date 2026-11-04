# Floating Workspace Glass Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the approved light-C/dark-B glass visual system, floating-badge icon, accessible fallbacks, and packaged icon resources without changing Phase 1 behavior.

**Architecture:** A centralized `WorkspaceAppearance` produces dynamic palettes, and a reusable `GlassBackgroundView` owns public `NSVisualEffectView` rendering. Existing controllers keep their behavior while adopting the new surfaces and icons. A deterministic CoreGraphics generator creates light/dark app icons and a monochrome menu template before `actool` packages them.

**Tech Stack:** Swift 6.3.3, SwiftPM, AppKit, CoreGraphics, Combine, XCTest, Xcode 27.2 `actool`, `codesign`.

## Global Constraints

- Approved spec: `docs/superpowers/specs/2026-11-04-floating-workspace-glass-design.md`; this is a visual-only refresh with no future-mode implementation.
- Light mode is C: `#E0F4FF` at alpha 0.68 and `#EEE4FF` at alpha 0.60. Dark mode is B: `#121926` at alpha 0.64 with accent `#8BD0FF`.
- Follow effective AppKit appearance automatically; no manual theme setting and no polling timer.
- Use public AppKit/CoreGraphics only. No private APIs, new app permissions, continuous animation, or high-frequency redraw loop.
- Preserve the 76 pt left rail, 16 pt note font, current controls, data schema, global hotkey, persistence, frame restoration, and all eight acceptance behaviors.
- Blank mode's user-selected color takes precedence over the blue/purple gradient.
- `NSVisualEffectView` is behind all controls and never intercepts editing. Content/editor surfaces remain more opaque than the glass rail/background.
- Respect `accessibilityDisplayShouldReduceTransparency` with solid fallback and `accessibilityDisplayShouldIncreaseContrast` with stronger borders.
- App icon uses the custom floating-badge concept with light/dark variants; menu bar uses a monochrome template; mode buttons keep Chinese text and add line icons.
- Build/test commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Missing icon resources fail the build with a specific filename.
- Keep `.artifacts/` out of commits. Do not push or publish to GitHub.

---

## File Map

- `Sources/FloatingWorkspaceCore/WorkspaceAppearance.swift`: palette model and dynamic theme selection.
- `Sources/FloatingWorkspaceCore/GlassBackgroundView.swift`: visual-effect background and gradient/solid fallback.
- `Sources/FloatingWorkspaceCore/FloatingWindowController.swift`: transparent panel integration and pin-state preservation.
- `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`: glass surfaces, mode icons, appearance-change handling.
- `Sources/FloatingWorkspaceCore/MenuBarController.swift`: monochrome template with SF Symbol fallback for test/debug contexts.
- `Sources/FloatingWorkspace/AppDelegate.swift`: isolated appearance/accessibility acceptance overrides.
- `Scripts/generate-icons.swift`: deterministic CoreGraphics vector icon generator.
- `Resources/Assets.xcassets/`: generated light/dark AppIcon and MenuBarTemplate resources, committed for review.
- `Resources/Info.plist`: icon metadata.
- `Scripts/build-app.sh`: generator, validation, `actool`, app assembly, signing.
- `Tests/FloatingWorkspaceCoreTests/WorkspaceAppearanceTests.swift`: palette and fallback tests.
- `Tests/FloatingWorkspaceCoreTests/GlassBackgroundViewTests.swift`: material and gradient tests.
- `Tests/FloatingWorkspaceCoreTests/IconResourceTests.swift`: dimensions, alpha, manifest, dark variants.
- Existing UI/controller tests: visual integration and behavior preservation.
- `docs/testing/floating-workspace-phase1-acceptance.md`: glass/accessibility additions without weakening original groups.
- `README.md`: visual system and icon regeneration commands.

### Task 1: Dynamic Palette and Glass Background

**Files:**
- Create: `Sources/FloatingWorkspaceCore/WorkspaceAppearance.swift`
- Create: `Sources/FloatingWorkspaceCore/GlassBackgroundView.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/WorkspaceAppearanceTests.swift`
- Create: `Tests/FloatingWorkspaceCoreTests/GlassBackgroundViewTests.swift`

**Interfaces:**
- Consumes: public AppKit appearance and accessibility settings.
- Produces: `WorkspacePalette`, `WorkspaceAppearance.make`, and `GlassBackgroundView.apply(_:blankColor:)` for Task 2.

- [ ] **Step 1: Write failing palette and material tests**

Create tests that verify:

```swift
let light = WorkspaceAppearance.make(
    appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
    reduceTransparency: false,
    increaseContrast: false
)
XCTAssertTrue(light.usesTransparency)
XCTAssertEqual(light.gradientColors.count, 2)
XCTAssertEqual(light.gradientColors[0].alphaComponent, 0.68, accuracy: 0.001)
XCTAssertEqual(light.gradientColors[1].alphaComponent, 0.60, accuracy: 0.001)

let dark = WorkspaceAppearance.make(
    appearance: try XCTUnwrap(NSAppearance(named: .darkAqua)),
    reduceTransparency: false,
    increaseContrast: false
)
XCTAssertEqual(dark.accentColor, NSColor(srgbRed: 0x8B / 255, green: 0xD0 / 255, blue: 0xFF / 255, alpha: 1))

let solid = WorkspaceAppearance.make(
    appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
    reduceTransparency: true,
    increaseContrast: false
)
XCTAssertFalse(solid.usesTransparency)
XCTAssertTrue(solid.gradientColors.isEmpty)

let contrast = WorkspaceAppearance.make(
    appearance: try XCTUnwrap(NSAppearance(named: .aqua)),
    reduceTransparency: false,
    increaseContrast: true
)
XCTAssertGreaterThan(contrast.borderColor.alphaComponent, light.borderColor.alphaComponent)
```

Add view tests asserting `GlassBackgroundView` installs an `NSVisualEffectView` with `.popover`, `.behindWindow`, active state, and emphasis; reduced transparency hides the effect/gradient and shows a solid background; a supplied blank color suppresses the blue/purple gradient.

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'WorkspaceAppearanceTests|GlassBackgroundViewTests'`. Expected: missing-type failures.

- [ ] **Step 2: Implement the palette contract**

Create these exact public/internal types:

```swift
public struct WorkspacePalette {
    public let gradientColors: [NSColor]
    public let solidBackgroundColor: NSColor
    public let contentBackgroundColor: NSColor
    public let railBackgroundColor: NSColor
    public let accentColor: NSColor
    public let borderColor: NSColor
    public let shadowColor: NSColor
    public let usesTransparency: Bool
}

public enum WorkspaceAppearance {
    public static func make(
        appearance: NSAppearance,
        reduceTransparency: Bool,
        increaseContrast: Bool
    ) -> WorkspacePalette
}
```

Use the exact light/dark values from Global Constraints. Return a solid light or dark fallback when reduction is requested; increase border alpha and preserve text/accent contrast when contrast is requested. Provide a `static func current(appearance: NSAppearance) -> WorkspacePalette` that reads both accessibility flags from `NSWorkspace.shared`.

- [ ] **Step 3: Implement GlassBackgroundView**

Create `GlassBackgroundView` with child `effectView` and a custom `GradientView`. It must expose:

```swift
func apply(_ palette: WorkspacePalette, blankColor: NSColor? = nil)
```

The normal state uses `NSVisualEffectView` material `.popover`, blending `.behindWindow`, active state, and emphasis. `GradientView` draws once with `NSGradient.draw(in:angle:)` using palette colors. If `blankColor` is non-nil, suppress the palette gradient and use the user color as the tint/fallback. If reduction is requested, hide effect and gradient and set `solidBackgroundColor`. The view returns `false` from `isOpaque` and accepts no events.

- [ ] **Step 4: Run tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'WorkspaceAppearanceTests|GlassBackgroundViewTests'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/WorkspaceAppearance.swift Sources/FloatingWorkspaceCore/GlassBackgroundView.swift Tests/FloatingWorkspaceCoreTests/WorkspaceAppearanceTests.swift Tests/FloatingWorkspaceCoreTests/GlassBackgroundViewTests.swift
git commit -m "feat: add dynamic glass appearance foundation" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: new tests and all 52 existing tests PASS.

### Task 2: Apply Glass Surfaces and Mode Icons

**Files:**
- Modify: `Sources/FloatingWorkspaceCore/FloatingWindowController.swift`
- Modify: `Sources/FloatingWorkspaceCore/WorkspaceViewController.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/FloatingWindowControllerTests.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift`

**Interfaces:**
- Consumes: `WorkspaceAppearance.current` and `GlassBackgroundView.apply` from Task 1.
- Produces: the complete light/dark editing UI without model changes.

- [ ] **Step 1: Add failing integration tests**

Add tests that prove:

- The workspace root contains a `GlassBackgroundView` behind other content.
- The panel is non-opaque; note uses a clear panel background while blank still exposes the exact user sRGB background color.
- Mode buttons have non-nil images and keep their Chinese titles; image/web remain disabled.
- `viewDidChangeEffectiveAppearance` refreshes the palette without calling the saver, marking dirty, or changing note/mode/pin state.
- The title-bar pin, menu checkmark, note text, and disabled-mode guard remain unchanged after light/dark changes.

Run focused controller tests; expected missing glass/image behavior failures.

- [ ] **Step 2: Integrate glass below the existing content**

Install one `GlassBackgroundView` as the backmost subview with constraints to all root edges. Keep the existing `WorkspaceViewController` ownership. Set `panel.isOpaque = false`; note panel background is `.clear`, blank remains the exact user sRGB color. `WorkspaceViewController` owns `updateGlassAppearance()` and calls it from content application and `viewDidChangeEffectiveAppearance`.

Use `WorkspaceAppearance.current(appearance: view.effectiveAppearance)` and pass the blank color only in blank mode. Apply `contentBackgroundColor` to note/status/editor surfaces and `railBackgroundColor` to the left rail. Do not add a redraw or appearance polling timer.

- [ ] **Step 3: Add mode icons and dynamic selected-state styling**

Use SF Symbols `note.text`, `photo`, `globe`, and `square` with `.imageLeading`, preserving titles, identifiers, 44 pt heights, and disabled states. Apply the palette accent to selected controls and readable label colors to all controls. Keep the existing mode-switch actions and business state unchanged.

- [ ] **Step 4: Run all controller tests and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'FloatingWindowControllerTests|WorkspaceViewControllerTests'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Sources/FloatingWorkspaceCore/FloatingWindowController.swift Sources/FloatingWorkspaceCore/WorkspaceViewController.swift Tests/FloatingWorkspaceCoreTests/FloatingWindowControllerTests.swift Tests/FloatingWorkspaceCoreTests/WorkspaceViewControllerTests.swift
git commit -m "feat: apply glass surfaces and mode icons" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: all tests PASS with no extra save on appearance-only changes.

### Task 3: Generate and Package Icon Resources

**Files:**
- Create: `Scripts/generate-icons.swift`
- Create: `Resources/Assets.xcassets/AppIcon.appiconset/`
- Create: `Resources/Assets.xcassets/MenuBarTemplate.imageset/`
- Create: `Tests/FloatingWorkspaceCoreTests/IconResourceTests.swift`
- Modify: `Resources/Info.plist`
- Modify: `Scripts/build-app.sh`
- Modify: `Sources/FloatingWorkspaceCore/MenuBarController.swift`

**Interfaces:**
- Consumes: the approved floating-badge vector geometry and Task 2 UI.
- Produces: deterministic icon resources, compiled `Assets.car`, and a menu template with SF Symbol fallback in test/debug bundles.

- [ ] **Step 1: Implement deterministic vector generation**

Create `Scripts/generate-icons.swift` using CoreGraphics drawing functions for two overlapping rounded panes and a small pin badge. It accepts the asset-catalog root as its only argument and creates:

- AppIcon light/dark PNGs at 16, 32, 64, 128, 256, 512, and 1024 pixels with the ten required macOS size/scale entries.
- MenuBarTemplate black-alpha PNGs at 16 and 32 pixels, marked as template in `Contents.json`.
- `Contents.json` manifests with dark `luminosity` appearances for AppIcon and template rendering intent for MenuBarTemplate.

The generator is the editable vector source of truth. Use deterministic coordinates and colors so repeated runs produce byte-identical PNGs.

- [ ] **Step 2: Add resource tests**

Create `IconResourceTests.swift` that locates the repository from `#filePath`, runs the generator, and verifies:

- Every required AppIcon file exists with the expected pixel dimensions and nontransparent content.
- Light and dark manifest entries exist for every size/scale pair.
- MenuBarTemplate uses black pixels with alpha and template rendering intent.
- `Resources/Info.plist` contains `CFBundleIconFile` and `CFBundleIconName` set to `AppIcon`.

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter IconResourceTests`. Expected: failures until resources and metadata are complete.

- [ ] **Step 3: Compile and validate assets in the build**

Update `Scripts/build-app.sh` to run the generator, `plutil -lint` on every `Contents.json`, fail on any missing required filename, and compile with:

```zsh
mkdir -p "$APP/Contents/Resources"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun actool \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --compile "$APP/Contents/Resources" \
  "$ROOT/Resources/Assets.xcassets"
```

The build must fail with the exact missing filename if a resource is absent. Add `CFBundleIconFile` and `CFBundleIconName` as `AppIcon`. In `MenuBarController`, load `MenuBarTemplate` with `isTemplate = true`, falling back to the existing SF Symbol only when running outside a packaged app.

- [ ] **Step 4: Build, verify, and commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
codesign --verify --verbose=2 dist/FloatingWorkspace.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
git add Scripts/generate-icons.swift Resources Tests/FloatingWorkspaceCoreTests/IconResourceTests.swift Scripts/build-app.sh Sources/FloatingWorkspaceCore/MenuBarController.swift
git commit -m "feat: package adaptive glass icon resources" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Expected: `Assets.car` exists, icon metadata validates, signature verifies, and all tests PASS.

### Task 4: Visual, Accessibility, and Full Acceptance

**Files:**
- Modify: `Sources/FloatingWorkspace/AppDelegate.swift`
- Modify: `Tests/FloatingWorkspaceCoreTests/AppDelegateTests.swift`
- Modify: `docs/testing/floating-workspace-phase1-acceptance.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: all visual/resource changes from Tasks 1–3.
- Produces: final signed app with visual, accessibility, and all original behavior evidence.

- [ ] **Step 1: Add isolated visual acceptance overrides**

Add test-only environment handling for `FLOATING_WORKSPACE_APPEARANCE=light|dark`, `FLOATING_WORKSPACE_REDUCE_TRANSPARENCY=1`, and `FLOATING_WORKSPACE_INCREASE_CONTRAST=1`. `AppDelegate` applies the appearance value through `NSApp.appearance` before creating the window, and assigns optional static flags `WorkspaceAppearance.acceptanceReduceTransparency` and `WorkspaceAppearance.acceptanceIncreaseContrast` before palette creation. `WorkspaceAppearance.current` uses these optional overrides when non-nil and otherwise reads the real system flags; tests reset both to nil. Defaults must use actual system settings; overrides only affect isolated acceptance processes. Add `AppDelegateTests` for parsing and invalid-value fallback. Do not change global macOS appearance or accessibility preferences.

- [ ] **Step 2: Update documentation**

README explains light C, dark B, floating-badge icons, accessibility fallbacks, `Scripts/generate-icons.swift` regeneration, and the three visual acceptance overrides. The acceptance procedure adds light/dark, reduced-transparency, increased-contrast, small-icon, and blank-color preservation checks while retaining all eight original groups.

- [ ] **Step 3: Run automated, visual, and resource checks**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-app.sh
codesign --verify --verbose=2 dist/FloatingWorkspace.app
git diff --check
```

Launch isolated final-app instances for light, dark, reduced-transparency, and increased-contrast modes. Verify actual palette/material values through public view state and AX labels; capture screenshots only if the existing harness permission allows it without granting new app permission. Do not claim a screenshot was captured if it was unavailable.

- [ ] **Step 4: Re-run all eight original acceptance groups**

Execute every original group on the final styled app, plus the new visual checks. Confirm no new save on appearance changes, no disabled-mode enablement, no continuous animation/redraw loop, and no Dock icon. Any failed group blocks completion and enters a reviewed fix cycle.

- [ ] **Step 5: Commit and perform the whole-branch review**

```bash
git add Sources/FloatingWorkspace/AppDelegate.swift Tests/FloatingWorkspaceCoreTests/AppDelegateTests.swift docs/testing/floating-workspace-phase1-acceptance.md README.md
git commit -m "test: verify glass appearance and accessibility" -m "Co-Authored-By: Kimi Code <noreply@moonshot.cn>"
```

Run the full test suite again, generate the whole-branch diff, and dispatch the most capable available reviewer. Address any Critical/Important findings through one reviewed fix wave. Do not merge, push, or publish merely because acceptance passed; the user goal authorizes local completion, not publication.

---

## Completion Gate

Completion requires all automated tests, resource/signature checks, light/dark/accessibility verification, and all eight original acceptance groups on the final styled app. Image/web remain disabled and are not part of this completion claim.
