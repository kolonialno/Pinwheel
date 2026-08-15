# Tray MVP

Temporary. Delete before merge.

## What a tray is

A tray is one screen of a short stack presented over the app. It has a title bar, a body, and optionally
something floating over the body and a button that ends the flow. Trays come in sequences: you open one,
push into another, come back, and eventually either commit or leave. The sequence is the unit the caller
thinks about; the tray is the unit we draw.

Three nouns, and everything below is one of them:

- **Flow** — an ordered stack of trays, driven by the caller's `path`. Owns nothing but the order.
- **Tray** — one screen. A title, a body, an optional floating accessory, an optional commit.
- **Row** — what a body is made of.

## The four trays we are building

Boost Post is the reference, mocked. It is worth listing what each one actually needs, because the row
vocabulary falls straight out of it:

| Tray | Body is | Needs |
|---|---|---|
| **Boost Post** | a link, a tier section, two value rows, a commit | rows that push, rows that show a value |
| **How it works** (the `?`) | a paragraph | a text row, and a tray that fits its content |
| **Region** | a filtered list of choices | caller's data, a query, a floating search field |
| **Pay with** | a list of choices, one ticked | selection |

So a body is a list of rows, and there are five kinds:

- **Text** — a paragraph or a caption. Centred when it is a caption.
- **Link** — text that opens a URL. "Get up to 3x more likes. Learn more" is this, not a label: tapping it
  leaves the app, so it is a button and should read as one.
- **Value** — a label, the current value, a chevron. Tapping pushes another tray. Region and Pay with.
- **Choice** — a label and a tick when chosen. Tapping selects and pops. Tiers, regions, payment methods.
- **Custom** — any SwiftUI leaf, for the thing we did not anticipate.

The tiers are a **section of choice rows**, not a picker. X draws a scrollable wheel; a section of rows
says the same thing, scrolls with everything else, and needs no new component.

## The caller-facing API

The caller already owns the state. They have a selected tier, a region, a payment method — so the trays
bind to that state rather than accumulating a parallel copy of it.

```swift
.pinwheelTray(path: $path) { step in
    switch step {
    case .boost:
        PinTray("Boost Post") {
            PinTrayText("Get up to 3x more likes.", link: "Learn more", to: .learnMore)
            PinTraySection("Tiers") {
                ForEach(Tier.all) { tier in
                    PinTrayChoice(tier.name, detail: tier.price, isChosen: tier == chosen) { chosen = tier }
                }
            }
            PinTrayValue("Region", value: region.name) { path.append(.region) }
            PinTrayValue("Pay with", value: method.name) { path.append(.pay) }
        }
        .commit("Boost Post") { boost() }

    case .region:
        PinTray("Region") {
            ForEach(regions.matching(query)) { region in
                PinTrayChoice(region.name, isChosen: region == self.region) {
                    self.region = region
                    path.removeLast()
                }
            }
        }
        .detent(.filling)
        .floating { PinTraySearchField(text: $query) }
    }
}
```

Nothing here is a data source protocol. The caller writes a `ForEach` over their own data, because they
already have it and any protocol we invent would be a worse version of `Collection`. Search is the same:
the caller owns the query and does the filtering, and we supply the field that floats.

## The outcome

There isn't one, and that is the point. The caller's state *is* the outcome — `chosen`, `region`,
`method` are their properties, bound by the rows. `.commit("Boost Post") { boost() }` runs their closure,
and `boost()` reads what it already has.

A dictionary or an `Outcome` protocol would mean the caller writes their selections into our bag and
reads them back out with a cast, to learn what they told us in the first place. If a caller wants a
struct to hand onward, they write one; we do not need to know.

## Containers and leaves

Containment is UIKit's. SwiftUI draws leaves. Concretely:

| Thing | Kind | Its one job |
|---|---|---|
| `PinTrayOverlay` | UIKit | Coordinates: owns the machine and the stack, decides what the card does |
| `PinTrayCardView` | UIKit | Be the card: background, corners, geometry |
| `PinTrayTitleBar` | UIKit | Hold the title row; report that the leading control was tapped |
| `PinTrayBodyView` | UIKit | Own the scroll, host the rows, report pulls — **built** |
| `PinTrayAccessoryView` | UIKit | Hold what floats at the bottom; tell the body how much room to keep |
| The rows, the title, the field | SwiftUI | Draw |

Each container owns a hosting controller for its leaf and nothing else. Layout, gestures and reporting
are the container's; drawing is the leaf's.

**"Title bar", not "header".** Header already means the sheet's header and a list's section header in this
codebase, and a tray is neither. It is a bar with a title and controls, so it is a title bar, everywhere.

## How a tray becomes the next tray

A tray is its three containers, built together and swapped as a unit; the card persists and carries the
geometry. Building fresh per tray keeps each tray's scroll position its own, which sharing one body would
lose.

On a push: build the arriving tray's containers, cross-fade them over the outgoing ones, and let the card
resize on whatever timeline the machine says owns the change. The outgoing tray is detached from layout
first so it cannot re-lay itself out mid-fade. Going deeper the outgoing tray grows as it fades; coming
back the arriving one shrinks into place — the shallower of the two always carries the zoom, so a
sequence reads as depth.

## How it must behave

These are settled and measured; they are the acceptance criteria, not aspirations.

- **A filling tray is anchored by its top.** Its top is `safeAreaTop + trayBackdropReach` and no keyboard
  moves it. Only the bottom travels.
- **Region stands on the keyboard**, filling the room above it, and keeps that top when the keyboard
  shrinks — the bottom rides the keyboard down and clamps at the floor while the keyboard carries on.
- **Tapping the field again returns it to where it was**, because the top never moved.
- **A downward drag at the top of the body drags the card to dismiss.** There is nothing above the first
  row to reveal.
- **A drag that starts mid-list belongs to the list for the whole gesture** — reaching the top part way
  through must not hand the rest of the flick to the card.
- **No tray covers the strip that dismisses it**; tapping above the card dismisses the whole flow.
- **One motion per change.** When the keyboard moves it owns the timeline and we start nothing beside it;
  a tray leaving beside it borrows its duration and curve.
- **A choice applies immediately and pops.** A commit button exists only where a flow genuinely ends —
  Boost Post has one; the pickers do not.
- **Nothing waits on a timer.**

## Not building

- A data source protocol, an outcome bag, or a picker wheel.
- Reduce Motion support — wanted, later.
- Anything for a tray that is sized by its content *and* raises a keyboard. It does not exist yet, and the
  hold that case needs is the one piece of the machine with no real user.

## Order of work

1. ~~`PinTrayBodyView`~~ — done.
2. `PinTrayTitleBar` and `PinTrayAccessoryView`, same shape: container owns a leaf, reports upward.
3. `PinTray` becomes the description the overlay assembles, and stops being a `View`. One edit, no green
   checkpoint in the middle — it breaks the chassis, the demo and several tests together.
4. The overlay assembles the three containers and swaps them as a unit.
5. The row vocabulary, and the demo rebuilt on it — including the two trays that do not exist yet.
6. The drag behaviour, red first.
7. The chassis tests that containment now makes reachable.
8. One QA pass off a single recorded session, then the draft PR.

## Open, not forgotten

- `edits` stays true after popping to a tray that does not edit. No measurable effect today.
- The chassis reaches sideways to `PinwheelRecorder` as a global.
- A filling tray's Figma capture goes through `PinUIKitCapture` now. Worth one capture run before merge.
