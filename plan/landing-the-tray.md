# Landing the tray

Temporary. Delete before merge.

## How we work while this lands

- Don't ask permission to fix a regression I caused — fix it.
- Don't bend a precise requirement into something easier to build.
- Don't agree with a correction and then continue down the same path.
- Read the recorder instead of asking what you did. Set it up, clear it, hand it over, keep off the
  simulator until you say done.
- QA once, at the end, against the final architecture — not before and after every step.

## Where it stands

Branch `elvis/pin-tray`, 49 commits, no PR opened (team repo — only on your say-so). Both tiers green.

The tray works: it presents, pushes, pops, rides the keyboard up and down, dismisses from the backdrop
and from a drag, and holds its top through an interactive keyboard drag. The machine and the geometry are
pure and carry the rules.

The unfinished thing is containment. The chassis hosts an entire tray in one hosting controller, so
SwiftUI holds the header, the content and whatever floats — and the consequences are the bug you found
(a downward drag at the top of the list rubber-bands instead of moving the card) and a chassis that can
only be tested through the app.

## The plan

1. **`PinTrayBodyView`** — done, `16f423e`. A `UIView` that owns its scroll view, is its own delegate,
   and reports pulls upward in its own words.
2. **`PinTray` stops being a `View`.** It becomes the description a consumer writes — title, content,
   floating accessory, commit, detent — and the chassis assembles it. This is the step with no green
   checkpoint in the middle: it breaks the chassis, the demo and several tests in one edit.
3. **The chassis assembles.** Header, body and floating accessory as real subviews it holds and lays out.
   Deletes: the one-controller hosting, `PinTrayFillsKey`, `PinTrayPhase.standingRoom`, the content
   bottom-inset environment value, and the demo's own `ScrollView`.
4. **The behaviour that started this.** A downward drag at the top of the list moves the card; the list
   never rubber-bands over nothing; a drag that starts mid-list belongs to the list for the whole
   gesture.
5. **Close the chassis testing gap.** With containment in UIKit, the header, the body and the card are
   ordinary objects a test can build. The facts that needed the app should stop needing it.
6. **QA once**, end to end, off one recorded session: present, push, type, interactive keyboard drag,
   pull-to-dismiss from the top, pop, second push, backdrop dismiss.
7. **Docs.** `AGENTS.md` and `LEARNINGS.md` current; delete this file.
8. **PR.** Draft, on your say-so.

## Open, not forgotten

- `edits` stays true after popping to a tray that does not edit — `holdsFirstResponder` searches the
  whole overlay, including the outgoing tray. No measurable effect today.
- The chassis reaches sideways to `PinwheelRecorder` as a global.
- Figma capture of a filling tray now goes through `PinUIKitCapture` rather than the DisplayList path.
  Worth one capture run before merge.
