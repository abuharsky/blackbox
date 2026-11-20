# Anti-patterns

What not to write, as **symptom → cause → fix**. Each links to the
decision behind it in [DECISIONS.md](DECISIONS.md).

| # | anti-pattern | you see |
| --- | --- | --- |
| 1 | [`now()` in compute](#1-now-in-compute) | a value goes stale until something unrelated recomputes |
| 2 | [Reading another box in compute](#2-reading-another-box-in-compute) | `touched … inside its compute`; `⚠` on the map |
| 3 | [Pressing another box in compute](#3-pressing-another-box-in-compute) | the same warning; changes with no wire on the map |
| 4 | [A copy of another box, kept in sync](#4-a-copy-of-another-box-kept-in-sync) | two values that disagree for a moment |
| 5 | [A pulling closure](#5-a-pulling-closure) | a change upstream reaches nothing until the next unrelated event |
| 6 | [A fresh object on a wire](#6-a-fresh-object-on-a-wire) | a box recomputes every pump; or the storm error |
| 7 | [Mutating an output in place](#7-mutating-an-output-in-place) | a change nobody hears |
| 8 | [An oscillating effect](#8-an-oscillating-effect) | the trace shows one effect with alternating inputs |
| 9 | [A box held to be read later](#9-a-box-held-to-be-read-later) | a box field of another box type |
| 10 | [A graph inside a box](#10-a-graph-inside-a-box) | links missing from the map |
| 11 | [An optional shared box](#11-an-optional-shared-box) | two instances of what should be one value |
| 12 | [A counter to fake an event](#12-a-counter-to-fake-an-event) | `seq: ++_seq` in a state |
| 13 | [A safe-looking default for "unknown"](#13-a-safe-looking-default-for-unknown) | a reaction on cold start as if the value changed |
| 14 | [`whenReadyOrNull` on a nullable source](#14-whenreadyornull-on-a-nullable-source) | `null` meaning two things |
| 15 | [A delay hidden in a wire or an effect](#15-a-delay-hidden-in-a-wire-or-an-effect) | `settled()` returns before the app is done |
| 16 | [Optimistic state](#16-optimistic-state) | the UI shows "playing" when the device failed |
| 17 | [A box that exists only to feed an effect](#17-a-box-that-exists-only-to-feed-an-effect) | a box of loose values copied from other modules |
| 18 | [Reading a box in build without an observer](#18-reading-a-box-in-build-without-an-observer) | a widget that does not update; a `BoxReadCheck` warning |
| 19 | [Unnamed effects](#19-unnamed-effects) | `effect_3` on the map and in the trace |
| 20 | [An empty list for a failed load](#20-an-empty-list-for-a-failed-load) | "nothing here" when the request failed |
| 21 | [Logic in the graph function](#21-logic-in-the-graph-function) | a graph function you have to scroll; `if` inside `input:` |
| 22 | [A one-shot flag for the next change](#22-a-one-shot-flag-for-the-next-change) | `armXOnNextChange()`; a command lost now and then |

---

## 1. `now()` in compute

- **Symptom:** a value depending on time is stale until something
  unrelated makes the box recompute.
- **Cause:** `compute` read the wall clock. Time is neither input nor
  state, so nothing recomputes when it passes.
- **Fix:** take the moment from `ClockBox` on a wire:
  `d.onlyWhenReady(clock.at(deadline))`. Compute the deadline from
  delivered data (an event's timestamp plus a duration).
  [Why](DECISIONS.md#time-is-delivered).

## 2. Reading another box in compute

- **Symptom:** `blackbox: A touched B inside its compute` in the console;
  `⚠ touches` on the map. A misses B's changes.
- **Cause:** a link the graph cannot see: A does not recompute when B
  changes.
- **Fix:** wire B into A's input: `(d) => (..., b: d.onlyWhenReady(b))`.
  A deliberate snapshot goes in `BoxHooks.untracked(() => ...)`.
  [Why](DECISIONS.md#one-rule-for-hidden-links).

## 3. Pressing another box in compute

- **Symptom:** the same warning; B changes, and no wire or effect on the
  map explains it.
- **Cause:** a command hidden in `compute`, which should only compute.
- **Fix:** move the command into a named effect that reads what triggers
  it. [Why](DECISIONS.md#one-rule-for-hidden-links).

## 4. A copy of another box, kept in sync

- **Symptom:** two boxes hold the same truth; an effect or `listen`
  copies one into the other; for a moment they disagree.
- **Cause:** the truth exists twice.
- **Fix:** one box, created where both modules can reach it, read by
  both through wires. See [RECIPES: Share a box between modules](RECIPES.md#share-a-box-between-modules).
  [Why](DECISIONS.md#a-shared-truth-lives-above-the-modules).

## 5. A pulling closure

- **Symptom:** `isPremium: () => purchases.premium.value` passed into a
  module; buying premium unlocks nothing until the next track.
- **Cause:** the closure reads fresh data but triggers nothing.
- **Fix:** pass the box and wire it: `d.onlyWhenReady(premium)`.
  [Why](DECISIONS.md#a-shared-truth-lives-above-the-modules).

## 6. A fresh object on a wire

- **Symptom:** a box recomputes on every pump; with a box that also
  returns a fresh object, the graph stops with "did not settle".
- **Cause:** the wire builds a new list or an object without `==`;
  it is never equal to the last input.
- **Fix:** put values with `==` on wires (records, ids, value classes);
  for an output type without `==`, override `sameOutput`.
  [Why](DECISIONS.md#equal-outputs-are-not-published).

## 7. Mutating an output in place

- **Symptom:** a list changed with `.add` is not seen by anyone.
- **Cause:** the same object is `==` to itself; nothing is published.
- **Fix:** replace it: `_items.value = [..._items.value, item]`.

## 8. An oscillating effect

- **Symptom:** `build(trace: true)` shows one effect running pump after
  pump with alternating inputs.
- **Cause:** the effect's input contains a value its own command
  changes (enabling the analyzer rebuilds the player, which drops
  `playing`, which disables the analyzer).
- **Fix:** build the input from intent (the screen is open and the user
  did not pause), not from device state. If device state is required,
  put `HysteresisBox(off:)` between them. A `DebounceBox` only slows the
  loop. [Why](DECISIONS.md#the-ring-through-the-device).

## 9. A box held to be read later

- **Symptom:** a box has a field of another box type and reads it in
  `compute` or reacts to it.
- **Cause:** a hidden dependency (see 2).
- **Fix:** wire it. A box that must *command* another (an intent such as
  `activate(stationId, player)`) gets it per call, not as a field.

## 10. A graph inside a box

- **Symptom:** boxes that never appear on the map; a box that owns a
  `Graph`.
- **Cause:** a second, invisible wiring layer.
- **Fix:** keep the graph flat. A group that needs its own lifetime is a
  separate top-level graph built at the composition root.
  [Why](DECISIONS.md#a-module-is-a-file-with-one-graph).

## 11. An optional shared box

- **Symptom:** `PremiumBox? premium` with `premium ?? PremiumBox.late()`
  in a module; in production, two premiums.
- **Cause:** a forgotten argument silently creates a second instance;
  each graph drives its own, so the one-declarer check cannot fire.
- **Fix:** a required parameter. Whoever decides the sharing (the root,
  a test) creates the box. [Why](DECISIONS.md#a-shared-truth-lives-above-the-modules).

## 12. A counter to fake an event

- **Symptom:** `seq: ++_seq` added so that a repeated value gets
  published.
- **Cause:** an equal value is not published; the counter fights that.
- **Fix:** store what the box remembers about the occurrence: a reason, a
  count with a reset point, a device timestamp. See
  [RECIPES: Remember an occurrence](RECIPES.md#remember-an-occurrence).
  [Why](DECISIONS.md#occurrences-are-state).

## 13. A safe-looking default for "unknown"

- **Symptom:** "premium gained" fires on every cold start of a premium
  user.
- **Cause:** `false` was used for "not loaded yet".
- **Fix:** say "unknown": a `.late()` box without `initialValue` (readers
  wait), or a `hydrated` flag in the value. See
  [RECIPES: Say "don't know"](RECIPES.md#say-dont-know).

## 14. `whenReadyOrNull` on a nullable source

- **Symptom:** `null` arrives and the box cannot tell "not ready" from
  "ready, nothing selected".
- **Cause:** both map to `null`.
- **Fix:** `onlyWhenReady` (a nullable source is ready with `null`), or
  `outputOf` when the phase matters.

## 15. A delay hidden in a wire or an effect

- **Symptom:** `Future.delayed` in an effect; `settled()` returns while
  the app is still going to change; the map does not show the delay.
- **Cause:** the delay is not a node.
- **Fix:** `DebounceBox` or `HysteresisBox` as a node, visible on the map
  and testable with `fakeAsync`. [Why](DECISIONS.md#a-delay-is-a-node).

## 16. Optimistic state

- **Symptom:** the UI shows "playing" after the button press, though the
  stream failed.
- **Cause:** the button wrote the cell instead of the device reporting
  it.
- **Fix:** the button commands the device; the cell moves when the device
  reports (`connect`). Keep the user's intent separately if needed.

## 17. A box that exists only to feed an effect

- **Symptom:** a box holding "a few values the effects need" from other
  modules.
- **Cause:** each field is a copy of someone else's truth (see 4).
- **Fix:** let the effect wire to the real boxes. Keep such a box only
  while a value cannot be wired yet, with a date to remove it.
  [Why](DECISIONS.md#the-effect-input-box-was-demoted).

## 18. Reading a box in build without an observer

- **Symptom:** a widget does not update; debug builds print a
  `BoxReadCheck` warning with the read site.
- **Cause:** the read happened outside `BoxObserver` (a plain widget's
  `build`, a `LayoutBuilder` or `itemBuilder` callback).
- **Fix:** wrap the reading code in `BoxObserver`; a deliberate one-time
  read goes in `BoxHooks.untracked`.

## 19. Unnamed effects

- **Symptom:** `effect_3` in the trace; the map lists unnamed effects.
- **Cause:** `addEffect` without `name:`.
- **Fix:** name it after the subsystem it writes: `name: 'equalizer'`.

## 20. An empty list for a failed load

- **Symptom:** "No stations" when the request failed.
- **Cause:** an error was turned into an empty value.
- **Fix:** keep the error in the output (`AsyncError`, or a `hasError`
  field) so the UI can show it.

## 21. Logic in the graph function

- **Symptom:** the graph function is long; wires contain `if` and
  computations; effect bodies are ten lines inline. To see what connects
  to what, you read past the logic.
- **Cause:** three kinds of code in one place: wiring, rules and effect
  bodies.
- **Fix:** one line per node. A rule becomes a box; an effect body
  becomes a class with `input` and `apply`; a wire reading several
  sources becomes a static `wire` on its box. See
  [RECIPES: Writing the graph](RECIPES.md#one-line-per-node).
  [Why](DECISIONS.md#the-graph-function-is-a-table).

## 22. A one-shot flag for the next change

- **Symptom:** `armAutoPlayOnNextSourceChange()` before a selection; now
  and then the command is lost (the change did not come, or came twice).
- **Cause:** a command waiting for data, stored as an event that must
  catch exactly one change.
- **Fix:** store the wish as state (`_shouldPlay`, set by play, cleared
  by pause) and act on it in `compute` whenever data arrives. See
  [RECIPES: A command that must wait for data](RECIPES.md#a-command-that-must-wait-for-data).
