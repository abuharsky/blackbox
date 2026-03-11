# blackbox_support

Shared tracking runtime for `blackbox`.

This package contains the reusable observation machinery used by UI adapters:
- `Reaction`
- `ReactionScheduler`
- `MicrotaskReactionScheduler`

`blackbox` reports box output reads through core hooks, while packages such as
`blackbox_flutter` and `blackbox_jaspr` provide framework-specific observers
that run builds inside a `Reaction`.
