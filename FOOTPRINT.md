# DotBar footprint work — measurements, changes, recommendations

Branch `feat/footprint`. All numbers measured on macOS 26A428 (Darwin 27.0.0), Apple
silicon, Release build, app launched with an isolated `HOME` so it never touched the
user's `items.json` or defaults.

**Headline: idle RAM and idle CPU are already at the platform floor. Binary size was
not.** The one change that moved a real number is the build-flag work (−13.1% binary).
The planned SwiftUI-into-a-loadable-bundle split was measured first and **deliberately
not done** — it buys ~0.4 MB of a 13 MB footprint and nothing on disk. Evidence below.

---

## 1. Before / after

| Metric (steady state, 21 s after launch, default `CPU Load` item) | Before | After | Δ |
|---|---|---|---|
| Main binary | 624,224 B | 542,544 B | **−81,680 B (−13.1%)** |
| `__text` section | 346,924 B | 283,268 B | −63,656 B (−18.4%) |
| `__swift5_reflstr` / `__swift5_fieldmd` | 1,535 / 3,736 B | 0 / 0 B | gone |
| `__swift5_typeref` | 22,608 B | 21,458 B | −1,150 B |
| phys_footprint (3 paired runs) | 13.2 / 13.6 / 13.8 MB | 13.2 / 13.6 / 13.7 MB | **no change** |
| Dirty memory | ~13–14 MB | ~13–14 MB | no change |
| Mapped images | 730 | 730 | no change |
| CPU, first 21 s | 0:00.07 | 0:00.07 | no change |
| CPU, steady-state 60 s window @10 s refresh | — | **+20 ms / 60 s (~0.03%)** | at floor |

Run-to-run footprint variance is ±0.6 MB, which is larger than every optimisation
available here. Paired runs (baseline and optimised alternating, same `items.json`)
were used so variance cancels.

## 2. Where the 13 MB actually goes

Control experiments, each a separate app:

| App | Binary | phys_footprint | Images |
|---|---|---|---|
| Minimal `LSUIElement` + one `NSStatusItem` with `button.title` | 55 KB | **11.9 MB** | 714 |
| Same + custom `NSView` subview drawing text, a dot, autolayout | 55 KB | **11.7 MB** | 714 |
| DotBar, prefs UI deleted, SwiftUI **not linked** | 383 KB | 14.0 MB | 726 |
| DotBar, unmodified | 624 KB | 14.4 MB | 730 |

Read this carefully:

- **~11.8 MB is the AppKit floor.** A do-nothing agent app with one status item costs
  that much before any DotBar code runs. ~90% of DotBar's idle footprint is not ours.
- **The custom `DotBarView` is free** (11.7 vs 11.9 MB). The `CoreAnimation` / `CG Image`
  / `Accelerate` regions it adds are ~0.3 MB and offset by other savings. I had assumed
  this was a cost centre and measured it specifically — it is not. Do not "optimise" the
  status-item view into `button.attributedTitle`; it would lose features for nothing.
- **Linking SwiftUI costs ~0.4 MB**, inside run-to-run noise. `dyld` maps SwiftUI,
  AttributeGraph and RenderBox at launch (confirmed present in `vmmap` even when
  Preferences is never opened), but they live in the dyld shared cache, so the pages are
  clean, shared and already resident for every other app on the system.
- Dirty-page breakdown: `Malloc Small` 7.9 MB (of which only 4.3 MB is live per `heap`;
  the rest is allocator free-list), `__DATA_DIRTY` 1.35 MB across 575 framework regions,
  `Malloc Metadata` 976 KB, `__DATA` 837 KB, page table 609 KB. Per `heap`, the live
  objects are 1010 ObjC classes, CFString, ObjC method caches — AppKit's, not DotBar's.
- Item count is irrelevant: 1 static item 13.4 MB, 1 script item 13.2 MB, 5 script
  items 13.3 MB. Thread count stays at 3.

## 3. What changed

Only files owned by this branch were touched.

**`project.yml`**
- `SWIFT_LTO: YES` + `OTHER_LDFLAGS: -Wl,-dead_strip_dylibs` → −64,864 B.
- `OTHER_SWIFT_FLAGS: -Xfrontend -disable-reflection-metadata` → a further −16,816 B.
- `ENABLE_TESTABILITY: NO`, `SWIFT_ENABLE_LIBRARY_EVOLUTION: NO` — already the Release
  defaults, pinned so they cannot drift.
- `NSSupportsSuddenTermination: true` in Info.plist. Safe: `items.json` is written
  atomically on every model change, so there is nothing to flush at shutdown. Caveat:
  `NSStatusItem` autosave positions live in `UserDefaults`, which `cfprefsd` flushes
  lazily — a shutdown within a second or two of reordering status items could lose the
  new order. Cosmetic, and the same risk every menu-bar agent accepts.
- **`NSSupportsAutomaticTermination` was deliberately NOT added.** For an `LSUIElement`
  agent with no windows it invites the system to terminate DotBar while idle, which
  would silently remove every status item from the menu bar. It is not safe here.
- Already correct, verified, left alone: `-Osize`, whole-module, `DEAD_CODE_STRIPPING`,
  `STRIP_INSTALLED_PRODUCT` / `STRIP_STYLE: all` / `STRIP_SWIFT_SYMBOLS`,
  `COPY_PHASE_STRIP`, `DEPLOYMENT_POSTPROCESSING`. `SWIFT_STDLIB_TOOL_STRIP_BITCODE` is
  a no-op on arm64 (bitcode is dead) and was not added.

**`DotBar/App/DotBarApp.swift`** — dropped the unused `import SwiftUI`. Cosmetic; keeps
the entry point honest about being AppKit-only.

### Reflection metadata — why this is safe here

`-disable-reflection-metadata` strips `__swift5_reflstr` / `__swift5_fieldmd`, which
SwiftUI is often claimed to need for `@State` / `@Binding` / `@ObservedObject`
discovery. I did not take that on faith. I built a harness that compiles the **real**
`PreferencesView` + `ItemEditorView` (with a populated `AppState`, a script item, a
rule-coloured dot, an SF Symbol and a hotkey), hosts it in an `NSHostingView`, drives
40 layout/display passes and renders it to a bitmap — once with reflection metadata and
once without:

```
CONTROL  SUBVIEWS=207 TEXTLIKE=18 RENDERED_NONBLANK_SAMPLES=48028
NOREFL   SUBVIEWS=207 TEXTLIKE=18 RENDERED_NONBLANK_SAMPLES=48031
```

Identical view trees, and the rendered PNG shows the live preview, working `TextField`
bindings, segmented pickers and steppers all correct. Codable was checked in the same
harness under the flag: `CODABLE_ROUNDTRIP_EQUAL=true` and a legacy minimal
`items.json` (`decodeIfPresent` path) decodes correctly. Codable is compile-time
synthesized and never consults reflection metadata.

If SwiftUI's Preferences UI ever misbehaves in a way that smells like property-wrapper
state not updating, this flag is the first thing to drop; the middle ground is
`SWIFT_REFLECTION_METADATA_LEVEL = without-names`, which keeps field metadata and loses
only the names.

## 4. Why the `DotBarPrefs.bundle` split was not done

The brief called this the biggest lever, on the theory that dyld maps SwiftUI at launch
for a window that is rarely opened. Measured, the theory does not hold on this OS:
**deleting the entire Preferences UI so SwiftUI is not linked at all moves
phys_footprint from 14.4 MB to 14.0 MB** — 0.4 MB, less than run-to-run variance, and
only 4 fewer mapped images out of 730. SwiftUI is shared-cache resident.

Nor is there a disk win: the ~240 KB of prefs code does not disappear, it moves from
`Contents/MacOS/DotBar` into `Contents/PlugIns/DotBarPrefs.bundle`. The `.app` total is
unchanged, and a separate Mach-O adds its own load commands and a second code signature.

The cost side is what settles it. `-bundle_loader` lets the bundle *link* against the
app's symbols but not `import` its module, so the bundle cannot see `AppState`, `Item`
or `ScriptOutput` as types. The two ways out are both bad:

- A `DotBarCore` framework holding the shared types requires making essentially every
  type and member `public` — a large diff across `Models.swift`, `AppState.swift`,
  `Store.swift`, `ScriptRunner.swift`, i.e. exactly the files the other two agents are
  editing. Guaranteed merge conflict.
- Compiling the shared sources into both targets gives each module its own distinct
  `Item` / `AppState` types, so `AppState.shared` in the bundle would be a *different*
  singleton from the app's. Bridging then needs a serialisation boundary. This is
  actually buildable without touching a single non-owned file — the design is: pass
  `Item` as Codable JSON; reconstruct `ScriptOutput` in the bundle by shipping only
  `out.raw`/`failed`/`errorMessage` and calling `ScriptOutput.parse(raw:failed:error:)`
  locally (it is a pure function of `raw`, so the round-trip is lossless); expose the
  app side as an `NSDictionary` of `@convention(block)` closures rather than a shared
  `@objc` protocol or class, since a protocol/class compiled into both modules
  registers twice in the ObjC runtime and casts across the boundary break; drive UI
  refresh over a plain `NotificationCenter` name. It works — but it is a permanent,
  fragile, duplicate-compilation seam in exchange for 0.4 MB of a 13 MB process.

Not worth it. If it is ever revisited, do it for launch time (not measured here) rather
than for memory, and do it after the other two branches have merged.

## 5. Recommendations for files this branch does not own

Ordered by value. None of these move idle RAM — I measured, there is no idle RAM to
move. They are allocation-churn and tidiness fixes.

| # | File / line | Change | Expected gain |
|---|---|---|---|
| 1 | `MenuBar/StatusItemController.swift:127` | `let df = DateFormatter()` is built on **every menu open**. Hoist to `private static let updatedFormatter: DateFormatter = { let d = DateFormatter(); d.dateStyle = .short; d.timeStyle = .medium; return d }()`. | ~1–3 ms and a few KB per menu open. No idle gain. `DateFormatter` is thread-safe for reads; this is main-actor only anyway. |
| 2 | `Core/Store.swift:32-33` | `static var encoder` / `static var decoder` are **computed**, so a fresh `JSONEncoder`/`JSONDecoder` is allocated on every `save`, `load`, `export` and `import`. Make both `static let`. | Removes one allocation per save. Saves happen on every model change. |
| 3 | `App/AppState.swift:105-107` | `respectLowPowerMode`'s getter hits `UserDefaults` on every `effectiveInterval()` call, i.e. once per timer (re)schedule per item. Cache it in a stored property, refreshed in the existing `.NSProcessInfoPowerStateDidChange` observer and in the setter. | Negligible CPU; removes a `UserDefaults` round-trip from the timer path. |
| 4 | `Core/ScriptRunner.swift:40-48` | Each `runSync` blocks **three** global-queue threads: two pipe readers plus `group.wait`. At 1–5 items this measured as zero (thread count stayed at 3), but N concurrent slow scripts will grow the libdispatch pool by up to 3N threads, each with a stack. Prefer `readabilityHandler`/`DispatchIO`, or read both pipes on one thread. | Only matters with many items running slow scripts concurrently. No gain at current scale. |
| 5 | `App/AppState.swift:178,193` | `Task.detached { await ScriptRunner.run(...) }` hops to the concurrency pool, and `ScriptRunner.run` immediately hops again to `DispatchQueue.global`. Call `ScriptRunner.runSync` directly inside the detached task and drop the `withCheckedContinuation`. | One fewer thread hop per refresh. Negligible, but it is free. |
| 6 | `App/AppState.swift:4` | `ObservableObject` is what keeps `Combine` linked into the main binary. Runtime cost is ~0 (shared cache). **Leave it** — only relevant if the bundle split is ever revisited. | None. Informational. |
| 7 | `App/AppState.swift:252` | `checkNotify` calls `Notifier.requestAuthorizationIfNeeded()` on every output for any item with `notify != .off`, which touches `UNUserNotificationCenter.current()`. It is `didRequest`-guarded so it only fires once, but note it hard-requires a real app bundle — it throws `bundleProxyForCurrentProcess is nil` when the binary runs unbundled. Worth an early-return when `item.notify == .off` *before* the call, which is already the case — no change needed, just don't move that guard. | None. Trap documented so nobody moves the guard. |

### Already optimal — verified, do not "fix"

- `Timer.tolerance` is set to 10% of the interval (`AppState.swift:392`) so the OS
  coalesces wakeups. Correct.
- `Emoji.table` (`LineParams.swift:289`, ~110 entries) and `Hotkey.named`
  (`HotkeyManager.swift:94`, ~80 entries) are `static let`, so Swift builds them lazily
  behind `swift_once` — **not** at launch. `emojize` is additionally guarded by
  `guard s.contains(":")`. Nothing to make lazier.
- `ScriptRunner.environment` resolves `PATH` once through a login shell and every
  refresh then uses a cheap `zsh -c`. This is the single most important idle-CPU
  decision in the app and it is already right.
- `PreferencesWindowController.windowWillClose` drops `contentViewController` and the
  window, so the whole SwiftUI hierarchy is released on close. Already right.
- Launch stagger, per-item in-flight guard, and timer pause across sleep/wake are all
  present and correct.
- No storyboard, no nib, no `NSMainNibFile`, no asset catalog. `LSUIElement` is set.
  Info.plist carries nothing unnecessary.

## 6. Verification status

- Release build: **succeeds, zero errors** (`** BUILD SUCCEEDED **`).
- The shipped binary was launched from this worktree under an isolated `HOME`, ran 22 s
  clean with no stderr output, created its status item, and was killed by this branch.
  Another DotBar instance (the user's, PID 17043 from the main worktree) was running
  throughout and was **not** touched.
- The SwiftUI Preferences UI was verified by rendering the real `PreferencesView` +
  `ItemEditorView` headlessly and comparing against a control build (§3). It was **not**
  verified by clicking through a visible window — this environment has neither screen
  recording nor assistive-access permission, so `screencapture` and `System Events`
  both return nothing. A human should still open Preferences once after merging.
