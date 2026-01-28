# Blackbox — Comparison with Other State Management Libraries

This document provides a **conceptual and architectural comparison** between **Blackbox** and popular state management libraries in the Dart / Flutter ecosystem.

The goal is **not** to declare a “winner”, but to clarify **different design trade-offs** and help you decide where Blackbox fits best.

---

## High-level positioning

| Library     | Primary focus                              |
|------------|---------------------------------------------|
| MobX       | Transparent reactive state via observables |
| Redux      | Predictable global state & reducers         |
| Riverpod   | Scoped dependency-driven state              |
| Bloc       | Event → State pipelines                     |
| **Blackbox** | Deterministic computation graphs            |

Blackbox is **not a UI state manager by default**.  
It is a **reactive computation core** that can *power* state management, business logic, and complex dependency graphs.

---

## Blackbox vs MobX

### MobX in short
- Observable state
- Automatic dependency tracking
- Reactions triggered implicitly
- Very ergonomic for UI

### Blackbox approach
- No observables
- No automatic dependency tracking
- Dependencies are **declared explicitly**
- Re-computation is **deterministic and scheduled**

### Key differences

| Aspect | MobX | Blackbox |
|------|------|----------|
| Dependency tracking | Implicit (magic) | Explicit (Graph) |
| Re-computation | Automatic | Scheduled |
| Error handling | Often implicit | Fail-fast by default |
| Testability | Good, but implicit | Very high, explicit |
| UI coupling | Strong | None |

### When Blackbox is better
- You want **zero implicit reactivity**
- You want to reason about *why* something recomputed
- You need deterministic, testable business logic
- You want to reuse the same logic outside Flutter

---

## Blackbox vs Redux

### Redux in short
- Single global immutable state
- Reducers + actions
- Very predictable, but verbose
- Strong architectural discipline

### Blackbox approach
- No global store
- Many small computation units (Boxes)
- Dependencies instead of reducers
- Graph instead of action flow

### Key differences

| Aspect | Redux | Blackbox |
|------|-------|----------|
| State shape | Single tree | Distributed boxes |
| Updates | Actions → Reducers | signal() / dependencies |
| Boilerplate | High | Low |
| Async | Middleware-heavy | Native via AsyncBox |
| Granularity | Coarse | Fine-grained |

### When Blackbox is better
- You don’t want a single global store
- You want **local reasoning** instead of reducers
- You want async as a first-class concept
- You want less ceremony

---

## Blackbox vs Riverpod

### Riverpod in short
- Provider-based dependency graph
- Compile-time safety
- Strong Flutter integration
- Good async handling

### Blackbox approach
- Explicit runtime Graph
- No provider scopes
- No implicit lifecycle
- Can live entirely outside Flutter

### Key differences

| Aspect | Riverpod | Blackbox |
|------|----------|----------|
| Dependency graph | Implicit via providers | Explicit Graph |
| Lifecycle | Scoped / autoDispose | Explicit |
| Flutter coupling | Strong | None |
| Async model | AsyncValue | AsyncOutput |
| Debugging | Sometimes indirect | Explicit graph state |

### When Blackbox is better
- You want **full control over lifecycle**
- You want to debug dependency graphs explicitly
- You need the same logic in backend / CLI
- You dislike provider scoping complexity

---

## Blackbox vs Bloc

### Bloc in short
- Event-driven architecture
- Streams everywhere
- Explicit events and states
- Strong separation of concerns

### Blackbox approach
- Signal-driven instead of event-driven
- No Streams by default
- Computation-first, not event-first
- Graph scheduling instead of event queues

### Key differences

| Aspect | Bloc | Blackbox |
|------|------|----------|
| Model | Events → States | Dependencies → Computation |
| Async | Streams | AsyncBox |
| Boilerplate | Medium–High | Low |
| Mental model | FSM-like | Dataflow graph |

### When Blackbox is better
- You don’t need explicit events
- You want fewer layers (event → bloc → state)
- You want direct dependency modeling
- You prefer dataflow over FSM

---

## Blackbox vs Rx / Streams

### Rx / Streams in short
- Push-based streams
- Powerful operators
- Hard to reason about large graphs
- Error handling can be tricky

### Blackbox approach
- Pull-based computation
- Deterministic recomputation
- Explicit dependencies
- Fail-fast semantics

### Key differences

| Aspect | Rx / Streams | Blackbox |
|------|--------------|----------|
| Direction | Push | Pull |
| Dependency visibility | Low | High |
| Error handling | Often swallowed | Explicit |
| Debuggability | Hard at scale | Predictable |

---

## Summary table

| Feature | Blackbox | MobX | Redux | Riverpod | Bloc |
|------|----------|------|-------|----------|------|
| Implicit magic | ❌ | ✅ | ❌ | ⚠️ | ❌ |
| Explicit dependencies | ✅ | ❌ | ❌ | ⚠️ | ❌ |
| Async-first | ✅ | ⚠️ | ❌ | ✅ | ⚠️ |
| UI-agnostic | ✅ | ❌ | ⚠️ | ❌ | ⚠️ |
| Testability | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| Boilerplate | Low | Low | High | Medium | Medium |

---

## How to think about Blackbox

Blackbox is best understood as:

> **A deterministic reactive computation engine**  
> rather than a UI state management solution.

You can:
- build a state manager *on top of it*,
- integrate it with Flutter, Riverpod, or Bloc,
- use it purely for business logic,
- use it in backend or CLI tools.

---

## Final note

If you enjoy MobX, Redux, Riverpod, or Bloc **conceptually**,  
but want:
- more explicit control,
- fewer hidden rules,
- clearer invariants,

Blackbox may be a good fit.

---

*This document intentionally focuses on concepts, not marketing claims.*