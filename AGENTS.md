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
- **A UI test does not land.** Driving the app to watch a change work is an instrument: red while the fix
  is absent, deleted in the change that fixes what it found. What stays is the unit test for what it
  localised. Coverage is never a reason to keep one.
- **The one exception costs two things.** A workaround held against SwiftUI or UIKit that nothing lower
  can reach may keep a permanent UI test — but only if it has **teeth** (it fails with the workaround
  removed) *and* a place in the **merge gate**. `DemoUITests` is not in the gate, so a permanent test
  there is one nobody runs: the last one passed with its own crash restored and had been guarding nothing
  for months before anyone looked. Either put it where it runs, or do not write it.
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
- **`UIPin*` is the UIKit twin of a `Pin*`**, never `UIKitPin*`; spelled-out `UIKit` is a descriptive
  qualifier only (`PinUIKitCapture`, `isUIKitHosted`).
- **Colours are trait-reactive, fonts are not.** A font token resolves once against the traits current at
  the read, so SwiftUI font call sites take the theme explicitly (`PinTextStyle.font(in:)`).
- **A presentation takes its traits from the window**, so the theme is written there, never on sheet
  content.
- **Catalog ids derive from title + tags** — there is no manual `id:`, and deep links and persistence key
  off them, so a title must be unique within its scope.
- **A comment that explains a behaviour becomes a named test, then the comment dies.**

## The merge gate

Actions is paused, so the gate is local: run both tiers and only merge a commit whose message says they
ran green.

```
~/bin/test-sim -s PinwheelTests
~/bin/test-sim -s Demo -o DemoTests
```

The `Tests: unit NN/NN + hosted NN/NN green (local xcodebuild)` trailer is the signal, enforced by
`.claude/hooks/green-commit-gate.py`. `DemoUITests` is not a tier.

## Where things live

- **Sources by domain, not access level**: `API/`, `Tokens/`, `Components/SwiftUI` + `Components/UIKit`,
  `Catalog/`, `Bridge/`, `Recording/`, `Capture/`, `Extensions/`.
- **Demo mirrors the split** — `Demo/Demos/SwiftUI` + `Demo/Demos/UIKit` hold every catalog screen;
  `Demo/FigmaCapture/` holds only the capture engine, never a browsable screen.
- **Both targets are file-system-synchronized groups**, so the folder layout *is* the project structure —
  adding or moving files needs no `project.pbxproj` edit.
- The package lives in `Pinwheel/`; a second root `Package.swift` re-exposes it to external consumers.

## Read before you change

`LEARNINGS.md`, the section that covers it — trays, bridging, theming, the capture engine, the catalog,
component surface. Each one is the measurements and the traps behind rules that otherwise look arbitrary.
Add to it as you learn; keep *this* file to what a session needs nine times in ten.
