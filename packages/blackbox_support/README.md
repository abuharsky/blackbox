# blackbox_support

Shared support runtime for [blackbox](https://pub.dev/packages/blackbox)
bindings: the read-tracking `Reaction` used by `BoxObserver` in
[blackbox_flutter](https://pub.dev/packages/blackbox_flutter) and
[blackbox_jaspr](https://pub.dev/packages/blackbox_jaspr).

You normally don't depend on this package directly — it is an internal
dependency of the bindings. Use it only if you are building a binding
for another UI framework: `Reaction.track(fn)` runs `fn`, records every
box read through `BoxHooks`, and invalidates when any of them changes.
