# Semantics

What the runtime does, exactly. Each rule links to the test that holds it;
a rule without a test does not belong here. Words are defined in
[CONCEPTS.md](CONCEPTS.md).

Test links name the file and the test: `file › test name`.

## 1. When a box computes and publishes

| rule | test |
| --- | --- |
| A box computes when the graph gives it an input not `==` to the last one, or when one of its cells is written. | [graph_test › distinct input after activation: same upstream value does not repush](../test/graph_test.dart), [state_cell_test › write recomputes and notifies](../test/state_cell_test.dart) |
| Writing a cell a value `==` to its current one does nothing: no compute, no save. | [state_cell_test › writing an equal value is a no-op](../test/state_cell_test.dart), [state_cell_test › equal write does not hit the store](../test/state_cell_test.dart) |
| An output equal to the current one is not published: listeners, wires and effects do not hear it. "Equal" is `sameOutput`, `==` by default. | [output_dedup_test › an equal output is not published: downstream does not re-run](../test/output_dedup_test.dart) |
| Override `sameOutput(previous, next)` for an output type without content `==`. | [output_dedup_test › sameOutput: one override for a type without content ==](../test/output_dedup_test.dart) |
| `action(() { ... })` runs the body, then computes and publishes once. | [state_cell_test › action batches multiple writes into one emission](../test/state_cell_test.dart), [async_state_cell_test › action batches writes: one recompute at the end](../test/async_state_cell_test.dart) |
| Writing a cell inside `compute` is an assert. | [state_cell_test › writing a cell inside compute asserts](../test/state_cell_test.dart) |
| A changed input does not reset cells. | [state_cell_test › input change alone does not lose memory](../test/state_cell_test.dart) |
| After dispose, writes neither compute nor notify. | [state_cell_test › writes after graph dispose do not notify](../test/state_cell_test.dart), [async_state_cell_test › writes after graph dispose neither compute nor notify](../test/async_state_cell_test.dart) |
| A multibox cell ignores an equal value (`dispatch`, `connect`); `child(x, distinct: false)` publishes every value. | [semantics_test › a multibox cell ignores an equal value unless distinct: false](../test/semantics_test.dart) |

## 2. Where `==` decides

| place | compared | effect of "equal" |
| --- | --- | --- |
| state cell write | new value vs current | nothing happens |
| box output | `sameOutput(previous, next)` | not published |
| multibox cell | new value vs current (unless `distinct: false`) | not published |
| wire of a box, multibox or effect | input vs the last one delivered | the node is skipped this pump |
| `outputOf(x)` | the `Output` snapshot (content `==`) | as any input |
| `persistFor` / `Cache` key | the key string | same slot, no re-slot |

A fresh list on a wire is never `==` to the last one: the box recomputes
every pump, then its equal output stops the cascade
([output_dedup_test › a fresh list on the wire costs a recompute, not the graph](../test/output_dedup_test.dart)).
Use records and value types with `==` in inputs and outputs.

## 3. Readiness

A source is **ready** when its output is `SyncData` or `AsyncData`.

| box | before its first input | test |
| --- | --- | --- |
| `Box(input)` / `NoInputBox` | ready | [runtime_sync_test › sync box output is immediately available without listen](../test/runtime_sync_test.dart) |
| `Box.late(initialValue: x)` | ready with `x` | [late_box_test › with initialValue: ready before the first input](../test/late_box_test.dart) |
| `Box.late()`, non-nullable output | not ready, no output | [late_box_test › without initialValue: no output until the first input](../test/late_box_test.dart) |
| `Box.late()`, nullable output | ready with `null` | [late_box_test › nullable output: ready with null before the first input](../test/late_box_test.dart) |
| `AsyncBox` | `AsyncLoading` until the first data | [runtime_async_test › async input box starts in loading and then emits data](../test/runtime_async_test.dart) |
| `AsyncBox.late(initialValue: x)` | ready: `AsyncData(x)` | [late_box_test › initialValue shows as AsyncData before the first input](../test/late_box_test.dart) |
| `CachedValueBox` | ready with `initialValue` or the disk slot | [cached_value_box_test › always has a sync value; background fetch updates and saves](../test/cached_value_box_test.dart) |
| multibox cell | ready from birth with `child(initial)` | [semantics_test › a multibox cell is ready from birth: onlyWhenReady never waits on it](../test/semantics_test.dart) |

To make readers wait, use a non-nullable output without `initialValue`.
`null` is a value: a nullable box is always ready.

## 4. Wires

A wire is the `input:` function of `add`, `addMultiBox` or `addEffect`.
It reads sources through three words:

| word | source not ready | test |
| --- | --- | --- |
| `d.onlyWhenReady(x)` | the whole node skips this pump | [graph_test › async dependency: dependent updates only after AsyncData](../test/graph_test.dart) |
| `d.whenReadyOrNull(x)` | `null`, the node runs | [graph_test › whenReadyOrNull: dependent computes with null while async source is loading, then with real value](../test/graph_test.dart) |
| `d.outputOf(x)` | the `Output` itself (loading / error / data), the node runs | [fold_test › delivers the phase: the fold runs during loading and on data](../test/fold_test.dart) |

| rule | test |
| --- | --- |
| A wire may read any source. A source the graph did not declare (another graph's box, a multibox cell, a clock moment) is subscribed on first read; reading is not declaring. | [graph_ownership_test › reading a foreign box via onlyWhenReady is not a declaration](../test/graph_ownership_test.dart), [multi_box_test › graph node can depend on a child via onlyWhenReady](../test/multi_box_test.dart) |
| After each pump the graph unsubscribes from undeclared sources no wire read in it. Declared boxes are always heard. | [let_go_test › a branch no longer read is let go; coming back reads it fresh](../test/let_go_test.dart), [let_go_test › declared boxes are always heard, even when no wire reads them](../test/let_go_test.dart) |
| A wire that stopped half-way (a source not ready, an error) keeps what it read before. | [let_go_test › a wire waiting on a source keeps its earlier subscriptions](../test/let_go_test.dart) |
| A wire that throws: see [§ 8 Errors](#8-errors). `onError: (e) => true` on `add` / `addMultiBox` swallows it and skips the node. | [multi_box_test › handled input error skips the pump cycle without crashing](../test/multi_box_test.dart) |

## 5. The pump: order and timing

| rule | test |
| --- | --- |
| A write notifies the box's listeners synchronously, inside the write. The graph runs later, in a microtask (a **pump**). | [semantics_test › a write is heard at once by listeners; the graph catches up in a microtask](../test/semantics_test.dart) |
| One pump runs boxes in declaration order, then multiboxes in declaration order, then effects in registration order. | [semantics_test › one pump: boxes in declaration order, then multiboxes, then effects](../test/semantics_test.dart) |
| A change during a pump schedules another pump; pumps repeat until nothing changes. Order changes the number of pumps, never the result. | [semantics_test › declaration order changes the number of pumps, never the result](../test/semantics_test.dart) |
| `listen` delivers the current value at once (unless `skipFirst: true`), then every published change. | [semantics_test › listen delivers the current value at once; skipFirst does not](../test/semantics_test.dart) |
| A `.late()` box's listener subscribed before the first input gets the first output. | [late_box_test › listener subscribed before the first input gets the first emission](../test/late_box_test.dart) |
| `await graph.settled()` returns when no pump is scheduled. It does not wait for async computes in flight. | [graph_tools_test › replaces flushMicrotasks: propagation is done when it resolves](../test/graph_tools_test.dart) |
| Tests only: `await Graph.allSettled()` returns when no live graph has a pump scheduled and no async box is computing, waiting round after round (an async result wakes a pump, a pump starts a compute). A compute that never completes fails it after `timeout`, naming the box; disposing the box drops it. | [all_settled_test › waits through graphs with async boxes between them, round after round](../test/all_settled_test.dart), [all_settled_test › a compute that never completes fails with the box named, not a hang](../test/all_settled_test.dart) |
| More than `64 + 4 × (boxes + multiboxes + effects)` pumps in a row: the graph stops pumping for good and throws a `StateError` naming the nodes still changing. | [graph_tools_test › a dependency cycle fails loudly instead of hanging](../test/graph_tools_test.dart), [node_failure_test › the storm detector names the nodes that never settle](../test/node_failure_test.dart) |

## 6. Effects

| rule | test |
| --- | --- |
| An effect runs when its input is not `==` to the last one. `run(current, previous)`; `previous` is `null` on the first run. | [graph_test › effect receives current and previous distinct inputs](../test/graph_test.dart), [trace_test › ran / unchanged / first run, by name, with input and previous](../test/trace_test.dart) |
| An effect whose wire is not ready waits; it does not run. | [trace_test › waiting while a required source has no output](../test/trace_test.dart) |
| An async `run` is started, never awaited. | [graph_test › async effect is fire-and-forget](../test/graph_test.dart) |
| Unnamed effects are numbered in registration order (`effect_1`, …). | [trace_test › unnamed effects are numbered in registration order](../test/trace_test.dart) |

## 7. Async boxes and the cache

| rule | test |
| --- | --- |
| A plain async box publishes `AsyncLoading(previousData)` on every new input or cell write, then `AsyncData` or `AsyncError(previousData)`. | [async_state_cell_test › cell write re-runs compute: loading with previous, then data](../test/async_state_cell_test.dart), [runtime_async_test › async emits error state on failure](../test/runtime_async_test.dart) |
| Only the latest compute lands; an older one finishing later is dropped. | [runtime_async_test › async versioning ignores stale results](../test/runtime_async_test.dart) |
| `refresh()` re-runs compute. | [declarative_cache_test › refresh() on a plain async box just recomputes](../test/declarative_cache_test.dart) |
| Cache, first boot: fetch, publish, save. | [declarative_cache_test › first boot: computes, emits, saves to the slot](../test/declarative_cache_test.dart) |
| Cache, fresh disk value: published at once, no fetch. | [declarative_cache_test › fresh restart: instant value from disk, no fetch](../test/declarative_cache_test.dart) |
| Cache, expired disk value: published at once, fetched in the background. | [declarative_cache_test › expired restart: stale shown instantly, refreshed in background](../test/declarative_cache_test.dart) |
| Cache, a recompute within TTL returns the cached value without fetching. | [declarative_cache_test › regular recompute returns cached value without fetching](../test/declarative_cache_test.dart) |
| Cache, a value read or listened to after its TTL refreshes in the background. | [declarative_cache_test › expiry triggers refresh on access](../test/declarative_cache_test.dart) |
| Cache, `refresh()` ignores TTL; `invalidateCache()` clears the slot and refreshes. | [declarative_cache_test › refresh() bypasses TTL; invalidateCache() clears the slot](../test/declarative_cache_test.dart) |
| Cache, a refresh shows the stale value while fetching; with `staleWhileRefresh: false` it shows `AsyncLoading` first. | [declarative_cache_test › forced refresh emits loading first](../test/declarative_cache_test.dart) |
| Cache, `persistFor`: an input change switches the slot and publishes its value (or loading); no value crosses slots. | [declarative_cache_test › input change re-slots: no leak, restore without refetch](../test/declarative_cache_test.dart), [output_dedup_test › cache slot switch A → B → A: the reader ends on A](../test/output_dedup_test.dart) |
| Cache, TTL is stamped when a fetch lands, even if the value is the same; a value served from the cache is not re-saved. | [output_dedup_test › cache: a refresh that fetched the same value is not republished, but still renews the TTL](../test/output_dedup_test.dart) |
| `CachedValueBox`: fetch errors are swallowed, the previous value stays. | [cached_value_box_test › fetch errors are swallowed; previous value stays; TTL stamped](../test/cached_value_box_test.dart) |

## 8. Errors

| where it throws | what happens | test |
| --- | --- | --- |
| a wire | `GraphNodeError` (stage `input`) to the zone; the node keeps its output; the rest of the pump runs | [node_failure_test › a wire throws: stage is input](../test/node_failure_test.dart) |
| a sync `compute` in a graph | `GraphNodeError` (stage `compute`), reported once; the box keeps its previous output until its next input; the rest runs | [node_failure_test › compute throws: the rest of the pump still runs, the error names the node](../test/node_failure_test.dart) |
| an async `compute` | the box publishes `AsyncError(previousData)`; not a graph error | [runtime_async_test › async emits error state on failure](../test/runtime_async_test.dart) |
| an effect's `run` (sync or its future) | `GraphNodeError` (stage `run`); later effects run; the same input does not re-run it | [node_failure_test › an effect throws: later effects still run; the same input is not repeated](../test/node_failure_test.dart) |
| a listener | reported to the zone; other listeners and the writer continue | [node_failure_test › a listener throws: other listeners still hear, the writer does not throw](../test/node_failure_test.dart) |
| `action` on a `.late()` box before its first input | `StateError` | [late_box_test › action before the first input throws a clear StateError](../test/late_box_test.dart) |

`build(trace: true)` marks a failed node `✗`
([node_failure_test › trace marks the failed node](../test/node_failure_test.dart)).

## 9. Persistence (state cells)

| rule | test |
| --- | --- |
| `state(x, persist: 'key')`: the disk value wins on creation; `x` is the first-boot value. | [state_cell_test › disk value wins over initial on restore](../test/state_cell_test.dart) |
| Every effective write saves to the slot. | [state_cell_test › first boot uses initial; writes save an envelope](../test/state_cell_test.dart) |
| `persistFor: (input) => key`: an input that changes the key reloads the cell from the new slot before compute — one compute, one publish, no value crosses slots. | [state_cell_test › input change re-slots: no leak, old slot intact, restore works](../test/state_cell_test.dart), [state_cell_test › re-slot emits exactly once per input change](../test/state_cell_test.dart) |
| The same key keeps the cell as it is. | [state_cell_test › same input does not re-slot or reset memory](../test/state_cell_test.dart) |
| `codec:` on the cell overrides the registry. | [state_cell_test › local codec override works without registry registration](../test/state_cell_test.dart) |
| Raw values written without the `{v, ts}` envelope are readable. | [state_cell_test › legacy raw values (no envelope) are readable](../test/state_cell_test.dart) |

## 10. Lifecycle and ownership

| rule | test |
| --- | --- |
| A box is declared (`add` / `addMultiBox`) by at most one live graph; a second declaration throws. | [graph_ownership_test › declaring a box on two live graphs throws loudly](../test/graph_ownership_test.dart), [graph_ownership_test › declaring the same box twice on one graph throws](../test/graph_ownership_test.dart) |
| After its graph is disposed, a box may be declared again. | [graph_ownership_test › re-declaring after the previous owner is disposed is legal](../test/graph_ownership_test.dart) |
| `graph.dispose()` disposes the boxes it declared, not the ones it only read. | [graph_ownership_test › declared boxes are still disposed by their own graph](../test/graph_ownership_test.dart), [graph_ownership_test › disposing a graph does not kill a foreign box it read lazily](../test/graph_ownership_test.dart) |
| `graph.own(release)`: released after every box stopped, last owned first, once; a throwing release does not stop the others; owning on a disposed graph releases at once. | [graph_own_test](../test/graph_own_test.dart) (all six tests) |
| `connect` subscriptions are cancelled before the next `compute` and on dispose. | [multi_box_test › connections are released on the next input cycle](../test/multi_box_test.dart) |
| A disposed multibox's cells stop notifying. | [multi_box_test › cells stop notifying once the multibox is disposed](../test/multi_box_test.dart) |
| `graph.boxes` lists declared boxes in declaration order; `graph.box<T>()` finds one by type and throws on none or on twins. | [late_box_test › declared boxes in declaration order, ready for a provider](../test/late_box_test.dart), [late_box_test › throws loudly on twins — type lookup cannot tell them apart](../test/late_box_test.dart) |

## 11. Time

| rule | test |
| --- | --- |
| `clock.at(moment)` is `false` before the moment and `true` after, with one notification; a past moment is `true` from birth. | [clock_box_test › false before the moment, true after — one notification](../test/clock_box_test.dart), [clock_box_test › a past moment is true from birth](../test/clock_box_test.dart) |
| `clock.every(period)` starts with the current time and publishes once per tick; `period` must be positive. | [clock_box_test › born with the current time, then one notification per tick](../test/clock_box_test.dart), [clock_box_test › rejects a non-positive period](../test/clock_box_test.dart) |
| Asking twice for the same moment or period gives the same cell. | [clock_box_test › memoized by moment — ask twice, get the same cell](../test/clock_box_test.dart) |
| A cell nobody listens to (after the current microtask) is dropped and its timer stopped; asking again gives a new cell with the same answer. | [let_go_test › a metronome nobody listens to stops ticking](../test/let_go_test.dart), [let_go_test › a reader re-subscribing in the same turn keeps the cell](../test/let_go_test.dart), [let_go_test › a forgotten moment asked again gives the same answer](../test/let_go_test.dart) |
| `DebounceBox(window)`: the first value passes at once; values faster than the window collapse into the last; a value equal to the shown one cancels the pending one; a value that never rests never gets out. | [debounce_box_test](../test/debounce_box_test.dart) |
| `HysteresisBox(on:, off:)`: starts `false`; goes `true` after the input is `true` for `on`, `false` after it is `false` for `off`; zero means at once. | [hysteresis_box_test](../test/hysteresis_box_test.dart) |
| Every library timer is a plain `Timer`: a graph built inside `fakeAsync` runs on virtual time, pumps included. | [clock_box_test › the whole graph runs on virtual time — pumps included](../test/clock_box_test.dart) |
| `dispose` cancels pending timers of the clock, debounce and hysteresis. | [clock_box_test › dispose cancels pending alarms](../test/clock_box_test.dart), [debounce_box_test › dispose cancels the pending value](../test/debounce_box_test.dart), [hysteresis_box_test › dispose cancels the pending switch](../test/hysteresis_box_test.dart) |

## 12. Pipeline

| rule | test |
| --- | --- |
| `start()` completes with the result step's first ready value; the pipeline disposes itself in every outcome. | [pipeline_test › completes with the result step; graph is disposed after](../test/pipeline_test.dart) |
| A result step that is ready before the run (`initialValue`, a nullable `.late()` output) is a build error. | [plain_code_reads_test › initialValue on the result → build throws](../test/plain_code_reads_test.dart), [plain_code_reads_test › nullable .late() result → build throws](../test/plain_code_reads_test.dart) |
| The result must be a declared step. | [pipeline_test › result must be a declared step — loud at build](../test/pipeline_test.dart) |
| A required step's error (after its retries) fails the run at once. | [pipeline_test › fails fast on a required step error — no hang](../test/pipeline_test.dart) |
| `retry: n` re-runs the step's `refresh()` up to n times. | [pipeline_test › retry re-drives a flaky step until it succeeds](../test/pipeline_test.dart) |
| `onFailure: FailurePolicy.skip`: the run survives; `whenReadyOrNull` readers get `null`. | [pipeline_test › onFailure: skip — run survives, the wire delivers null](../test/pipeline_test.dart) |
| `timeout:` fails a run that hangs. A second `start()` returns the same future. | [pipeline_test › timeout set at build cuts a hang](../test/pipeline_test.dart), [pipeline_test › second start returns the same future](../test/pipeline_test.dart) |

## 13. Reading in plain code

| read | not ready | test |
| --- | --- | --- |
| `box.valueOrNull` | `null` | [output_test › returns null while async source is loading](../test/output_test.dart) |
| `box.requireValue` | throws, naming the output state | [output_test › throws with output state when async source is not ready](../test/output_test.dart) |
| `await box.firstReady` | waits for the first ready value (skips loading) | [plain_code_reads_test › async: loading is skipped, data completes it](../test/plain_code_reads_test.dart) |

## 14. Debug-only checks

None of these run in release builds.

| rule | test |
| --- | --- |
| Inside a box's `compute` (or a cache `fetch`), reading or pressing another box is a **touch**: one console warning per pair of types, recorded for the map. Not a touch: the box's own cells, and reads inside `BoxHooks.untracked`. | [hidden_links_test](../test/hidden_links_test.dart) |
| Pressing a box's buttons from an effect's `run` is recorded as a **press** for the map, even when the value does not change. | [hidden_links_test › pressing counts even when the value does not change](../test/hidden_links_test.dart) |
| A box read outside any tracking sink goes to `BoxHooks.onUntrackedRead`; inside `BoxHooks.untracked` it goes nowhere. | [hooks_test](../test/hooks_test.dart) |
| Flutter / Jaspr: a box read while building, outside a `BoxObserver`, prints one warning per read site (`BoxReadCheck`). | [box_read_check_test](../../blackbox_flutter/test/box_read_check_test.dart) (Flutter), [box_read_check_test](../../blackbox_jaspr/test/box_read_check_test.dart) (Jaspr) |
