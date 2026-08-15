# Agent Guidelines

How we work in Pinwheel. Portable iOS conventions live one level up (`~/code/<org>/ios/AGENTS.md`) and
are inherited, so they are not repeated. **Why** any of this is the way it is — the measurements, the
traps, the bugs behind each rule — is in `LEARNINGS.md`; read the part that covers whatever you are
about to change.

## The five that matter

1. **Measure and reproduce before fixing.** A cause is something a run showed you, not something the
   code suggests. Guessing costs a build and a launch per round, and a wrong guess looks exactly like a
   right one that changed nothing.
2. **A bug gets a failing test first.** Red, run it, confirm it fails for the right reason, then fix.
   Never edit source and test in the same step. Only bugs get this; everywhere else, prefer making the
   mistake unrepresentable over asserting it is absent.
3. **Test at the lowest rung that can hold the fact** — `PinwheelTests`, then `DemoTests`, then a UI
   test. Moving up a rung needs a reason, and "it was easier" is not one.
4. **Reach for the instruments before writing one.** They are listed below. Never measure this app off
   an image.
5. **Verify before claiming done**, and say what you actually observed, failures included.

## The rungs

| Target | Holds | Runs |
|---|---|---|
| **`PinwheelTests`** | the library's own behaviour — logic, geometry, tokens, rendering, the capture engine. **The default home.** | hostless SwiftPM, whole suite in seconds |
| **`DemoTests`** | facts needing a live app: anything **presented**, anything needing a real scene, a real keyboard, or Demo-target code the package cannot see | **hosted by `Demo.app`** |
| **`DemoUITests`** | throwaway probes only, **empty at rest** | XCUITest, ~10s a test |

- **`DemoTests` is hosted and has a harness.** `DemoTests/HostedView.swift`: `window(showing:)` flips
  `_AXSSetAutomationEnabled` so SwiftUI fills its accessibility tree and labels, frames and
  `accessibilityActivate()` become readable; `presentation(in:)` waits for a presented view to join the
  window; `settledPresentation(in:)` waits for a detent to stop moving. If a fact needs an app, it goes
  here — do not conclude it is untestable.
- **`PinwheelTests` cannot be given a host** (SwiftPM target; a host is an Xcode setting). That is a
  design gate, not a limitation: the day a library test needs `Demo.app`, something leaked out of the
  library.
- **`DemoTests` must not link the package products.** It loads them from its host; `@testable import
  Pinwheel` needs no product dependency, and adding one breaks `DemoUITests`.
- **A probe never lands.** It is an instrument: red while the fix is absent, deleted in the change that
  fixes what it found. What stays is the unit test for what it localised. A UI test earns a commit only
  by guarding an Apple-framework workaround.
- **Teeth, always.** Prove the test fails against the un-fixed code. Commit the fix *before* teeth-testing
  it, or the revert silently eats it. When a fix ships without a red first, say so plainly.

## The instruments

- **`PinwheelRecorder`** — `-PinwheelRecord` writes `session.log` to the app's tmp: every touch with the
  name of what it hit, every navigation, every reaction with its state, keyboard frames, and geometry
  when it changes. For anything a person drove by hand. Appends across launches; read it with
  `xcrun simctl get_app_container <udid> <bundle> data`.
- **`PinDisplayListCapture`** (SwiftUI tree) and **`PinUIKitCapture`** (UIView tree) — real frames for
  any layout question. A layout fact is a test, not a look.
- **A `CADisplayLink` tape** for motion: sample `layer.presentation()` and write to
  `NSTemporaryDirectory()`. `simctl io recordVideo` drops frames badly enough to be useless.
- **`RenderPreview`** on the catalog's permanent `#Preview`, `simctl launch -PinwheelPreview <id>`, and
  `Scripts/sweep.sh --preview` for a full sweep. To re-check one component's Figma IR use
  `Scripts/sweep.sh --capture --only=<id>` — never hand-roll `simctl` against a pinned UDID.
- **Build/verify via the Xcode MCP** (`BuildProject`, `RenderPreview`, `RunSomeTests`,
  `tabIdentifier: "windowtab1"`); `xcodebuild`/`simctl` are the fallback. See the `xcode-mcp` skill.
- **Never measure this app off a screenshot.** Images are for external references. Pixel-scanning your
  own app has produced contradictory numbers, numbers off the home screen, and wrong scales.
- **A probe must not pass `-UITestingNoAnimations`** — it disables animations, so every motion reads as
  an instant snap and the measurement blames the code for the harness.

## The merge gate

GitHub Actions is paused, so the gate is local. Run both tiers and only merge a commit whose message
states they ran green:

```
xcodebuild test -project Demo.xcodeproj -scheme PinwheelTests -destination "platform=iOS Simulator,id=<udid>" CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Demo.xcodeproj -scheme Demo -only-testing:DemoTests -destination "platform=iOS Simulator,id=<udid>" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''
```

The `Tests: unit NN/NN + hosted NN/NN green (local xcodebuild)` trailer is the merge signal, enforced by
`.claude/hooks/green-commit-gate.py`. `DemoUITests` is not a tier.

## House style

- **SwiftUI-first with UIKit compatibility.** No `import UIKit` in SwiftUI-first views, examples or call
  sites; keep UIKit to compatibility types and clearly named bridges.
- **Theme is law.** Every surface resolves provider-backed tokens (`PinwheelTheme`), never Apple's system
  styles, and API is shaped so the system-style path is unrepresentable — `PinLabel.font` takes a themed
  `PinTextStyle`, not a `Font`.
- **One implementation per component**: a SwiftUI `Pin*` plus a thin `UIPin*` shell that hosts it.
- **Shared vocabularies are top-level types** (`PinTextStyle`, `PinState`).
- **SwiftUI-native API**: bare initializer plus chained themed modifiers, mirroring SwiftUI's own names.
  Unprefixed on our types; `pinwheel`-prefixed only when extending a SwiftUI type.
- **A comment that explains a behaviour becomes a named test, then the comment dies.**
- **Keep `LEARNINGS.md` current** as you learn; keep this file to what a session needs nine times in ten.

## Pinwheel — decisions

Durable design decisions and why they were made.

### Component surface (when a `Pin*` exists)

- Add a SwiftUI `Pin*` (with a thin `UIPin*` shell) **only when** SwiftUI lacks a first-class primitive, so styling would be hand-rolled anyway (`PinButton` — pill, variants, loading, symbol, haptics), **or** there's real imperative / UIKit-hosting value to bridge (`PinStateView` as a state machine a UIKit table can drive). If SwiftUI's primitive + `PinwheelTheme` already covers it and nothing needs to host it in UIKit, don't wrap it.
- **Exception — theme footguns get a wrapper anyway.** `Label → PinLabel` because raw `Text(...).font(.body)` silently resolves to Apple's system style (see Theme below). The test is "does the raw primitive bypass the theme?", not just "does a primitive exist?".
- **Switch → `Toggle`** (no standalone `PinSwitch`; the only switch lives inside the `UIPinTableView` family). **Tokens (Font/Color/Spacing)** are *tokens*, never components, in either world.
- **`Stepper → PinStepper`** (a `−`/value/`+` pill). SwiftUI's `Stepper` renders a system `±` control that bypasses the theme and can't be the pill shape a design system wants — a theme footgun, same test as `PinLabel`. `PinStepper(value:)` + `.onDecrement/.onIncrement` modifiers; bordered capsule, SF-Symbol `±` (mirrors `PinButton`'s `systemImage:`), themed value. Migrated from tienda-ios's Kolibri `KStepper`. No `UIPinStepper` — no UIKit-hosting need yet.

### Trays

A UIKit chassis (`PinTrayOverlay`) hosting SwiftUI content, driven by a pure `PinTrayMachine` over a
pure `PinTrayGeometry`. Two rules carry most of it: **one place draws** (`apply`), and **anything
arriving from SwiftUI mid-move is recorded, not drawn**. Everything else — why the keyboard is an
actor, what a filling tray is, the dozen bugs behind each rule — is in `LEARNINGS.md`. Read it before
changing the chassis.

### Bridging

- **The UIKit twin of a `Pin*` component is `UIPin*`, not `UIKitPin*`.** Mirrors Apple's own prefix — it's `UILabel`, never `UIKitLabel` — and next to the SwiftUI `PinLabel` reads as "the UIKit one" to any iOS dev; the `Pin` brand token right after `UI` keeps it from colliding with Apple's `UI*` namespace. The spelled-out `UIKit` survives only as a *descriptive qualifier*, never a component prefix: `PinUIKitCapture`/`PinUIKitListCapture` (which capture path), `PinwheelUIKit*` (the hosting bridge), `isUIKitHosted` (what an item hosts). A raw-control demo with no `Pin` token to disambiguate keeps a non-`UI` name (`CollectionViewGridDemo`, not `UICollectionViewDemo`) so it can't be read as an Apple type.
- **One implementation per bridgeable component.** A `Pin*` SwiftUI source plus a thin `UIPin*` shell that hosts it (via `PinHostView`), never two parallel reimplementations. Theming, light/dark, and Dynamic Type cross the bridge for free because both worlds read the same `Config` providers.
- **Bridged: Button, StateView.** `UIPinButton` / `UIPinStateView` host the SwiftUI implementation. Trade-off: one `UIHostingController` per instance — acceptable for these leaf/overlay components; revisit for dense reused contexts (e.g. table cells).
- **State overlay centers via `centerY` in the shell**, not by filling. `PinHostView` sizes to intrinsic content, so a fill approach collapses to the top; centering lives in the shell, mirroring the old UIKit layout.
- **UIKit `view:` catalog items host at full bounds** via `PinwheelUIKitContainerViewController` (a `UIViewControllerRepresentable` handed the full proposed size), not a bare `UIViewRepresentable` (which sized to the fitting size and collapsed edge-pinned / table-backed examples to the top-left).
- **UIKit `Tweakable` options bridge into the playground.** A hosted `view:` item's UIKit `Tweak`s map to `PinwheelTweak`s (`TextTweak` → action, `BoolTweak` → toggle) and surface in the settings sheet.
- **A hosted UIKit `view:` is built once and reused.** `makeSwiftUIView` is called on every playground re-render; it must hand back the *same* `ViewType` instance each time. The bridged tweak closures capture that instance and the hosting controller displays it — a fresh instance per render makes the tweaks mutate an off-screen copy, so UIKit tweaks silently do nothing under nested presentation.
- **`viewController:` items follow the same rule** — both `PinwheelItem(_:viewController:)` inits build the controller once and bridge `Tweakable` (reading its `tweaks` into the playground), mirroring `view:`. A `UIViewController` that conforms to `Tweakable` gets its tweaks in the settings sheet, and they drive the live (on-screen) instance — not an off-screen copy.

### Intentional UIKit surface (kept on purpose)

These stay UIKit because no SwiftUI primitive matches their ergonomics/perf:

- **`UIPinView` base** — `setup()` lifecycle, open subclassing.
- **`UIPinFullscreenView`** — a base class for keyboard-aware full-screen screens (forms/editors): bottom-anchored content rides above the keyboard, plus a synthesized `viewDidFirstAppear()` hook. Kept UIKit and has **no SwiftUI demo on purpose** — SwiftUI gives keyboard avoidance and `onAppear` for free, so there's nothing to build; a SwiftUI "FullscreenView" example would only imply a component that shouldn't exist.
- **`UIPinTableView` family** — cell recycling, dataSource/delegate contract, `UISwitch` items, A–Z section indexer; no `List` equivalent with comparable perf.

### Theme & shared vocabularies

- A theme is a named value in the environment, plural by default: `PinwheelTheme` (name + providers),
  supplied as `PinwheelCatalog(themes:)`, resolved through `EnvironmentValues.pinwheelTheme`, and bridged
  to a `PinwheelThemeTrait` so UIKit-hosted items resolve the same selection. Equatable **by name**.
- A theme carries component shape as well as tokens (`buttonShape`), because a silhouette is as much a
  brand's signature as its palette.
- Spacing and radius are global `static let` constants, not per-theme.
- Colours are trait-reactive for free; **fonts are not** — a font token resolves once against the traits
  current at the read, so SwiftUI font call sites take the theme explicitly (`PinTextStyle.font(in:)`).
- A custom trait must declare `affectsColorAppearance` or dynamic colours go stale.
- A sheet takes its traits from the **window**, so the theme is written there, never on sheet content.
- Menus cannot be themed, so every picker is a pushed list of themed rows.
- Colour tokens have a `ShapeStyle` shorthand (`.background(.primaryBackground)`); the `UIColor`
  extension stays canonical.

### Figma capture

- **Components capture with zero cooperation.** Every `Pin*` is byte-for-byte identical to `main`: no
  capture code, no markers. The engine derives structure from the DisplayList, names from reflection, and
  token bindings by value-matching what was rendered. A consumer drops their components in and they work.
- **The engine is chosen by the item's hosted world** (`PinwheelItem.isUIKitHosted`), never its display
  tag: `view:`/`viewController:` walk the real `UIView` tree, `content:` reads the DisplayList.
- **Build capturable demos eagerly** — `ScrollView { VStack { ForEach } }`. A raw `List` captures too (the
  engine force-realizes its cells), but `LazyVStack`/`LazyVGrid` are viewport-gated.
- **Capture from the live on-screen host**: a UIKit-backed control only populates the DisplayList once it
  has rendered on a window.
- **Never force a synchronous render-server commit** — `drawHierarchy(afterScreenUpdates: true)` exhausts
  the simulator's render server and controls silently stop compositing. Read the front buffer instead.
- **The sweep owns a dedicated simulator, resolved by UDID**, and a stale sweep build silently ships an
  old capture — `rm -rf /tmp/pinwheel-sweep-dd` when a capture contradicts a test.
- Dark mode is two sweep rounds merged; both themes tokenize via per-theme variables, not modes.

### Project layout

- **Sources organized by domain, not access level.** `API/` (public surface), `Tokens/` (tokens, both worlds, incl. SwiftUI `PinwheelTheme`), `Components/SwiftUI` + `Components/UIKit` (split by world; `TableView/` under UIKit), `Catalog/` (the one, pure-SwiftUI catalog + FAB + device/state), `Bridge/` (SwiftUI↔UIKit), `Extensions/`.
- **Demo mirrors the split** — `Demo/Demos/SwiftUI` + `Demo/Demos/UIKit`. Every catalog demo screen lives here (the Figma-capture demos included); `Demo/FigmaCapture/` holds only the capture *engine* (host/IR, scroll-stitch, the sweep harness), never a browsable screen.
- **Both targets are file-system-synchronized groups**, so the folder layout *is* the project structure — moving/adding files needs no `project.pbxproj` edits. (The Demo app target's synced group excludes `Info.plist` so it isn't double-copied as a resource.)
- **Distribution nesting left as-is (deliberate):** the package lives in `Pinwheel/` (the Demo references it locally); a second root `Package.swift` re-exposes it for external `.package(url:)` consumers. Awkward (`Pinwheel/Sources/Pinwheel/`, two manifests) but changing it touches external import paths — not worth it now.

### Catalog, FAB & settings

- One pure-SwiftUI catalog and one SwiftUI settings sheet; the legacy UIKit catalog is gone.
- **Ids derive from title + tags** — there is no manual `id:`. `PinwheelItem.generatedID(title:tags:)` is
  the public builder; persistence and deep links key off these, so titles must be unique within scope.
- **Sections are concept buckets, axes are tags.** `PinTag` is an open `RawRepresentable` struct so a
  consumer adds its own axis.
- **Typed identifiers**: the library ships `PinwheelComponent`; the consumer declares one `String` enum in
  a module both the app and its UI tests import (`DemoCatalog`) — a UI test cannot `@testable import` the
  app, which is the whole reason that package exists.
- One FAB, hosted in a pass-through overlay window so it floats over presentations.
- `PinwheelChrome` is the SwiftUI↔window seam; hosted items are built once.
- **The device-frame resize snaps, never implicitly animated** — an `.animation(_:value:)` on the
  playground overflows SwiftUI's layout engine into a stack overflow.

### Open follow-ups

- **Bridged-component cost** — one `UIHostingController` per `UIPinButton`/`UIPinStateView`; revisit only if used in dense reused contexts (table cells). A watch-item, not actionable now.

(The "Recyclable" section was renamed from the misspelled "Reciclable"; its persisted id changed `reciclable` → `recyclable`, a one-time selection reset.)
