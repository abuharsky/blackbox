part of blackbox;

typedef Cancel = void Function();

Cancel _cancelGuarded(void Function() cancel) {
  var done = false;
  return () {
    if (done) return;
    done = true;
    cancel();
  };
}

/// Delivers [state] to every listener. A listener that throws is that
/// listener's failure: it is reported to the zone (loud — a test fails,
/// Flutter shows it) and the remaining listeners still hear the change.
/// The writer that caused the change does not throw.
void _notify<S>(List<void Function(S)> listeners, S state) {
  for (final listener in List.of(listeners)) {
    try {
      listener(state);
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
