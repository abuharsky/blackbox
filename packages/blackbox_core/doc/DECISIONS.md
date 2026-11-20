# Decisions

Why Blackbox is the way it is. Each entry: the decision, the reason, and
what it was paid for by, when a real bug paid for it. What changed in
each version is in [CHANGELOG.md](../CHANGELOG.md); what the runtime does
is in [SEMANTICS.md](SEMANTICS.md).

Most stories come from a production internet-radio app (native player,
billing, alarms, background isolate).

---

## One law, three writers

**Decision.** `output = compute(input, state)`; the graph writes input,
buttons write state, `compute` writes output.

**Why.** A reader can answer "why did this change?" by looking at two
things. Every other rule in the library follows from this one.

## The graph is written in one place

**Decision.** Dependencies are wires in a builder, not calls scattered
through classes (`ref.watch`, subscriptions).

**Why.** When a chain of five units breaks, you read one function, not
five files. The graph can also be drawn and checked (the map).

## Equal outputs are not published

**Decision (0.11).** A box does not publish an output `==` to its current
one, like cells already did. `sameOutput` covers types without `==`.

**Why.** "Writing an equal value is a no-op" is now true everywhere.

**Paid for by.** Duplicate effect runs; and a graph that stopped with the
storm error because a fresh list on a wire met a box that republished
every time. Field code kept a hand-written "last published" field to
work around it.

## A failing node fails alone

**Decision (0.11).** An exception in a wire, a `compute` or an effect is
reported as `GraphNodeError` (node, stage) once; the rest of the pump
runs. A throwing listener does not stop the others.

**Paid for by.** One throwing box silently stopped every box declared
after it from updating, with no message saying which.

## Every output change is published

**Decision (0.11).** The cache publishes a slot switch and a disk restore
like any output; TTL is stamped when a fetch lands.

**Paid for by.** Switching stations A → B → A left the lock screen on B's
cover: the cache had swapped the value silently, and with equal outputs
unpublished nobody heard the return to A.

## A graph hears only what its wires read

**Decision (0.11).** After each pump a graph unsubscribes from undeclared
sources no wire read. `ClockBox` drops moments nobody listens to.

**Paid for by.** A box per opened station, never released; clock timers
ticking for readers long gone.

## Keyed boxes were rejected

**Decision (0.11 cycle).** No `BoxFamily` (a box per key, living while
watched). It was built and removed.

**Why.** "A box lives while someone watches it" is a second lifecycle
rule next to "a graph owns what it declares". The same need is met by
the open item's id as input and a cache slot per id
([recipe](RECIPES.md#one-box-for-whichever-item-is-open)).

## A module is a file with one graph

**Decision.** No "module as a box" and no graph inside a box. A module is
a function in a file that builds one graph; an app may have several.
There is no global `settled()` across graphs: tests use small graphs and
fake boxes.

**Why.** Every wire stays visible on one level; lifetimes stay with
graphs.

## A shared truth lives above the modules

**Decision.** A value two modules need is one box created at the
composition root, driven by one graph, read by the others through wires.
The driving module takes it as a required parameter.

**Paid for by.** A premium purchase in the middle of a track unlocked
nothing until the next song: the catalog read premium through a closure,
which saw fresh data but triggered nothing. And an optional
`premium ?? PremiumBox.late()` that split the app into two premiums
when the argument was forgotten.

## One rule for hidden links

**Decision (0.11).** In debug builds, touching (reading or pressing)
another box inside a box's `compute` is a hidden link: one warning per
pair of types, `⚠` on the map. Exceptions: the box's own cells, and
reads inside `BoxHooks.untracked`. Nothing else.

**Why.** Earlier drafts had separate read and press warnings and an
exception for boxes created inside `compute`. They contradicted each
other on the same line of code. One rule cannot. A box used as a tool
inside `compute` is a touch too; if deliberate, it says so with
`untracked`.

## The map is a generated file, outside the core

**Decision (0.11).** `graphMap` in `package:blackbox/map.dart` writes
Markdown, committed as `doc/MAP.md` and kept by a golden test. It reads
facts through `GraphFacts`, which `package:blackbox/blackbox.dart` does
not export. Links that are not wires are recorded in debug builds only.

**Why.** Code agents and reviewers read one file first, and wire changes
show in diffs. Markdown is cheaper for agents to read than HTML. The
core records facts; it does not know about Markdown.

## Time is delivered

**Decision.** `compute` never reads the clock; `ClockBox` delivers time
as cells: `at(moment)`, `every(period)`. There is no `after(Duration)`.

**Why.** An output that depends on when it was called is not a function
of input and state, and nothing recomputes it when time passes. "After"
hides the moment it counts from; a deadline computed from a delivered
timestamp is an honest key.

## A delay is a node

**Decision.** Delays are `DebounceBox` and `HysteresisBox`: nodes on the
map. No delay option on wires, no default delay anywhere.

**Why.** A hidden delay makes `settled()` lie and the map incomplete. A
node is visible, traced and testable on virtual time. Inside both boxes
an instant switch catches up in a microtask, not a zero timer: a zero
timer would let a fast dip through.

## The ring through the device

**Decision.** An effect's input must not contain a value its own command
changes. Use intent; if a measurement is required, `HysteresisBox(off:)`.

**Paid for by.** The spectrum analyzer: enabling it made the player
rebuild its engine, which passed through `loading`, which turned the
analyzer off, which rebuilt the engine back — a loop at the device's
rhythm, invisible in the structure and plain in the trace.

## The ring through memory is legal

**Decision.** A value the graph computes and needs back is state: an
effect presses a button, the box is read downstream.

**Why.** The loop is visible because the state has a name. A *copy* of
someone else's value is not this; it is a duplicated truth
([anti-pattern 4](ANTI-PATTERNS.md#4-a-copy-of-another-box-kept-in-sync)).

## Occurrences are state

**Decision.** No event cell and no `StateMachineBox`. A repeated
occurrence is stored as what the box remembers: a reason, a count with a
reset point, a device timestamp. A state machine is a sealed type, a
pure `next`, and one `dispatch`.

**Paid for by.** A `seq` counter found hand-written in three places and
proposed as a missing primitive. Each turned out to be a missing state
(`StopReason`, `failures`, `lastTare`) that answered the reader better.

## The effect input box was demoted

**Decision.** A box holding "loose values effects need from other
modules" is scaffolding, not architecture.

**Paid for by.** The pattern's own example: each of its fields turned out
to be a copy of another module's truth; the class was deleted.

## No `latestData`

**Decision.** The library has no "last good value" accessor on wires.
Apps write one-line helpers when they mean it.

**Why.** A value that is always present hides whether it is stale, and
code downstream stops handling errors.

## A pipeline result must not be ready before the run

**Decision (0.11).** A result step with an `initialValue` or a nullable
`.late()` output is a build error.

**Why.** `start()` completes with the first value; a stub would complete
the run at once.

## FlowBox was absorbed by record inputs

**Decision (0.10).** Many sources converge through one box's record
input, fed by several wires. `FlowBox` is deprecated.

**Why.** Fan-in must be visible on the map, so the graph does it, not a
box subscribing on its own.

## Documentation rules

**Decision (0.11).** The reference is split by job: CONCEPTS (words),
SEMANTICS (exact behavior), ARCHITECTURE (layout), RECIPES, ANTI-PATTERNS,
DECISIONS (this file). Every rule in SEMANTICS links to its test, and a
test (`docs_test.dart`) fails if a rule has no test or a linked test is
gone. Stories live here, not in the CHANGELOG or the reference.

**Paid for by.** The previous docs promised behavior the code did not
have (equal outputs, every timer in the clock, `every` ticking for no
one) in places where four field bugs were hiding.
