part of blackbox;

final Object _boxHooksKey = Object();

/// Zone value of [BoxHooks.untracked]: reads in here are deliberate
/// snapshots — no sink records them, no debug check complains.
final Object _untrackedReads = Object();

abstract interface class BoxHooksSink {
  void onRead(OutputSource<dynamic> source);
}

final class BoxHooks {
  static T runWith<T>(BoxHooksSink sink, T Function() body) {
    return runZoned(body, zoneValues: {_boxHooksKey: sink});
  }

  /// Runs [body] with reads untracked: a deliberate snapshot.
  ///
  /// Inside an observer, the reads in [body] do not subscribe it — the
  /// observer will not rebuild when those boxes change. Outside one, they
  /// do not trigger [onUntrackedRead]. Use it where a snapshot is the
  /// point: an initial value in `initState`, a value handed to a route
  /// that must not follow later changes.
  static T untracked<T>(T Function() body) {
    return runZoned(body, zoneValues: {_boxHooksKey: _untrackedReads});
  }

  /// Called for a read that no sink records — the reader gets the current
  /// value and nothing more: no subscription, no later update.
  ///
  /// Outside a UI build that is normal (actions, callbacks, the graph's own
  /// wiring). Inside one it is a classic bug: the widget shows a snapshot
  /// and stays stale until something else rebuilds it. The core cannot tell
  /// the two apart, so it only reports; a UI binding installs this hook in
  /// debug builds and decides (see `blackbox_flutter`). `null` — nobody
  /// listens, which costs one null check per read.
  static void Function(OutputSource<dynamic> source)? onUntrackedRead;

  static void reportRead(OutputSource<dynamic> source) {
    final sink = Zone.current[_boxHooksKey];
    if (!identical(sink, _untrackedReads)) _noteTouch(source);
    if (sink is BoxHooksSink) {
      sink.onRead(source);
      return;
    }
    if (identical(sink, _untrackedReads)) return;
    onUntrackedRead?.call(source);
  }
}
