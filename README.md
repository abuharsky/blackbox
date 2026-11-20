# Blackbox

State management for Dart, Flutter and Jaspr with one law:

```
output = compute(input, state)
```

An app is **boxes** connected by **wires** in a **graph**, plus
**effects** that act on the outside world. The graph writes a box's
input, the box's own methods write its state, `compute` writes its
output. The graph is written in one function and can be generated into
a map file that code agents and reviewers read first.

Start with the [blackbox README](packages/blackbox_core/README.md): an
example, installation, and the documentation index.

## Packages

| package | what |
| --- | --- |
| [blackbox](packages/blackbox_core) | the core, pure Dart |
| [blackbox_flutter](packages/blackbox_flutter) | `BoxObserver`, `BoxProvider`, `SharedPreferences` persistence |
| [blackbox_jaspr](packages/blackbox_jaspr) | the same for [Jaspr](https://pub.dev/packages/jaspr) web apps, `localStorage` persistence |
| [blackbox_support](packages/blackbox_support) | read tracking shared by the bindings |

## Documentation

| file | read it for |
| --- | --- |
| [CONCEPTS](packages/blackbox_core/doc/CONCEPTS.md) | the words, one entry each |
| [SEMANTICS](packages/blackbox_core/doc/SEMANTICS.md) | exact runtime behavior, each rule linked to its test |
| [ARCHITECTURE](packages/blackbox_core/doc/ARCHITECTURE.md) | how an app is laid out; the map file |
| [RECIPES](packages/blackbox_core/doc/RECIPES.md) | task → solution |
| [ANTI-PATTERNS](packages/blackbox_core/doc/ANTI-PATTERNS.md) | symptom → cause → fix |
| [DECISIONS](packages/blackbox_core/doc/DECISIONS.md) | why it is this way |
| [MIGRATION](packages/blackbox_core/doc/MIGRATION.md) | upgrading |

[doc/coffee-brewing.md](doc/coffee-brewing.md) is a modeling study: a
whole device application designed on the library before any of it was
built.

## Examples

- [examples/blackbox_example](examples/blackbox_example) — Flutter
- [examples/blackbox_jaspr_example](examples/blackbox_jaspr_example) — Jaspr
