# Agent Guidelines

How we work in Pinwheel. Portable iOS conventions live one level up (`~/code/<org>/ios/AGENTS.md`) and are
inherited, so they are not repeated here. **Why** any of this is the way it is — the measurements, the
traps, the bugs behind each rule — is in `LEARNINGS.md`. Read the section covering whatever you are about
to change, add to it as you learn, and keep *this* file to what a session needs nine times in ten.

## Working rules

- **Measure and reproduce before fixing.** A cause is something a run showed you, not something the code
  suggests. Guessing costs a build and a launch per round, and a wrong guess looks exactly like a right
  one that changed nothing.
- **Ask the app, never an image.** Screenshots are for external references. Pixel-scanning this app has
  produced contradictory numbers, numbers taken off the home screen, and wrong point scales. Every
  question has an instrument below — reach for it before writing one.
- **Verify before claiming done**, and report what you actually observed, failures included.
- **Adding or moving a file needs no `project.pbxproj` edit** — both targets are file-system-synchronized
  groups, so the folder layout *is* the project structure and a new folder is a real decision.
- **Linear ownership.** Nothing reaches more than one level up or down. Downward is direct; upward is a
  closure or a protocol. A parent coordinates and its children have one job each and are pure where they
  can be — the tray's geometry and its machine are pure values, and the chassis that draws them owns
  nothing else.
- **A child answers to its own delegate and reports upward in its own words.** The body is its scroll
  view's delegate; what it tells the tray is "pulled down by 40", never `scrollViewDidScroll`. A parent
  adopting its child's protocol drags the child's vocabulary a level up where it does not belong.
- **Containment is a UIKit job.** SwiftUI supplies leaves — a row, a title, a field. Anything that holds,
  lays out, scrolls or routes a gesture is a `UIView` we own. Asking SwiftUI to contain is what makes
  gestures fight across the seam, representables vanish without a scene, and children findable only by
  walking a tree somebody else owns.
- **One file per abstraction.**
- **Dependencies arrive through `init`** — no optionals, no defaults, no two-phase setup. If a thing
  cannot exist without a container, a clock and something to show, it takes all three at birth. Every
  protocol ships a real implementation and a stub, so the seam is usable from a test the day it is made.
- **No behaviour behind a delay.** A timer is a guess about the world. If something must happen when a
  motion ends, use the animation's completion; if it depends on what the world is doing, ask the world —
  a private API answering outright beats a stopwatch estimating.
- **One place draws, one place decides.** Most bugs here have been the same shape: a second copy of some
  state, or a second path that animates. Delete the copy rather than syncing it.

## Testing

Write the test at the lowest rung that can hold the fact. Moving up needs a reason, and "it was easier"
is not one.

| Target | Holds | Runs |
|---|---|---|
| **`PinwheelTests`** | the library's own behaviour — logic, geometry, tokens, rendering, the capture engine. **The default home.** | hostless SwiftPM |
| **`DemoTests`** | facts needing a live app: anything **presented**, anything needing a real scene or a real keyboard, and Demo-target code the package cannot see | **hosted by `Demo.app`** |
| **`DemoUITests`** | throwaway probes only, **empty at rest** | XCUITest |

- **A bug gets a failing test first.** Red, run it, confirm it fails for the right reason, then fix. Never
  edit source and test in the same step. Only bugs get this; everywhere else prefer making the mistake
  unrepresentable over asserting it is absent.
- **Teeth, always.** Prove the test fails against the un-fixed code. Commit the fix *before* teeth-testing
  it, or the revert silently eats it. When a fix ships without a red first, say so plainly.
- **`DemoTests` is hosted and ships a harness**, `HostedView`. Its `window(showing:)` flips
  `_AXSSetAutomationEnabled` so SwiftUI fills its accessibility tree and labels, frames and
  `accessibilityActivate()` become readable; `presentation(in:)` waits for a presented view to join the
  window; `settledPresentation(in:)` waits for a detent to stop moving. If a fact needs an app it goes
  here — do not conclude it is untestable.
- **A UI test does not land.** Driving the app to watch a change work is an instrument: red while the fix
  is absent, deleted in the change that fixes what it found. What stays is the unit test for what it
  localised. Coverage is never a reason to keep one.
- **The one exception costs two things.** A workaround held against SwiftUI or UIKit that nothing lower
  can reach may keep a permanent UI test — but only with teeth *and* a place in the merge gate. A guard
  outside the gate is one nobody runs, and it rots without telling you. Either put it where it runs, or
  do not write it.
- **Assert arrival before measuring anything.** A probe that never reached the state proves nothing, and
  reads exactly like one that did — a drag aimed at a list that was never populated landed on a button
  and produced confident, worthless numbers.
- **A probe must not pass `-UITestingNoAnimations`.** It disables animations, so motion reads as an
  instant snap and the measurement blames the code for the harness.
- **A comment that explains a behaviour becomes a named test, then the comment dies.**

## Instruments

- **`PinwheelRecorder`** — `-PinwheelRecord` writes `session.log` to the app's tmp: every touch with the
  name of what it hit, every navigation, every reaction with its state, keyboard frames, and geometry
  when it changes. For anything a person drove by hand. Appends across launches; read it with
  `xcrun simctl get_app_container <udid> <bundle> data`.
- **`PinDisplayListCapture`** (SwiftUI tree) and **`PinUIKitCapture`** (UIView tree) — real frames for any
  layout question. A layout fact is a test, not a look.
- **A `CADisplayLink` tape** for motion: sample `layer.presentation()` and write to
  `NSTemporaryDirectory()`. `simctl io recordVideo` drops frames badly enough to be useless.
- **`RenderPreview`** on the catalog's permanent `#Preview`, and `simctl launch -PinwheelPreview <id>` to
  deep-link a booted simulator.
- **`Scripts/sweep.sh --preview`** snapshots every component and tweak variant; `--capture --only=<id>`
  re-checks one component's Figma IR. Never hand-roll `simctl` against a pinned UDID — the sweep owns its
  own simulator, and a hardcoded device launches nowhere while you read a stale result.
- **Dump the runtime rather than stopping at a search result.** Two private keyboard flags looked right
  and both were wrong; enumerating every property on the live object, twice, settled it in one run.
- **The Xcode MCP** for build and verify (`BuildProject`, `RenderPreview`, `RunSomeTests`);
  `xcodebuild`/`simctl` are the fallback. Setup and its gotchas live in the `xcode-mcp` skill.

## Merge gate

Actions is paused, so the gate is local: run both tiers and only merge a commit whose message says they
ran green.

```
~/bin/test-sim -s PinwheelTests
~/bin/test-sim -s Demo -o DemoTests
```

The `Tests: unit NN/NN + hosted NN/NN green (local xcodebuild)` trailer is the signal, and a PreToolUse
hook blocks a merge whose tip commit lacks it.

## House style

- **SwiftUI-first with UIKit compatibility.** No `import UIKit` in SwiftUI-first views, examples or call
  sites; keep UIKit to compatibility types and clearly named bridges.
- **Theme is law.** Every surface resolves provider-backed tokens (`PinwheelTheme`), never Apple's system
  styles, and API is shaped so the system-style path is unrepresentable — `PinLabel.font` takes a themed
  `PinTextStyle`, not a `Font`.
- **Colours are trait-reactive, fonts are not.** A font token resolves once against the traits current at
  the read, so SwiftUI font call sites take the theme explicitly (`PinTextStyle.font(in:)`).
- **A presentation takes its traits from the window**, so the theme is written there, never on sheet
  content.
- **One implementation per component**: a SwiftUI `Pin*` plus a thin `UIPin*` shell that hosts it. The
  UIKit twin is `UIPin*`, never `UIKitPin*`; spelled-out `UIKit` is a descriptive qualifier only
  (`PinUIKitCapture`, `isUIKitHosted`).
- **Shared vocabularies are top-level types** (`PinTextStyle`, `PinState`).
- **SwiftUI-native API**: bare initializer plus chained themed modifiers, mirroring SwiftUI's own names.
  Unprefixed on our types; `pinwheel`-prefixed only when extending a SwiftUI type.
- **Catalog ids derive from title + tags** — there is no manual `id:`, and deep links and persistence key
  off them, so a title must be unique within its scope.
