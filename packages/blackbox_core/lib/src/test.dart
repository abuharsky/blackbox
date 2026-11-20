part of blackbox;

// cancel.dart
@visibleForTesting
Cancel cancelGuardedForTest(void Function() fn) => _cancelGuarded(fn);

// graph.dart
@visibleForTesting
T resolveDependencyForTest<T>(Graph g, OutputSource<T> box) {
  return DependencyResolver._(g).onlyWhenReady(box);
}

@visibleForTesting
void schedulePumpForTest(Graph g) {
  g._schedulePump();
}

@visibleForTesting
bool isReadyForTest<T>(Output<T> o) {
  return o.isReady;
}

/// Skips the current replayed state and waits for the next matching ready value
/// emitted after [action] starts.
///
/// Completes with the matching value from [SyncData] or [AsyncData].
/// Completes with error immediately if [action] throws or the box emits
/// [AsyncError].
@visibleForTesting
Future<O> awaitNextValueAfterAction<O>({
  required OutputSource<O> box,
  required FutureOr<void> Function() action,
  required O expected,
  Duration timeout = const Duration(seconds: 1),
}) {
  final completer = Completer<O>();
  late final Cancel cancel;
  var skippedCurrent = false;

  void completeValue(O value) {
    if (completer.isCompleted) return;
    completer.complete(value);
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (completer.isCompleted) return;
    completer.completeError(error, stackTrace);
  }

  cancel = box.listen((output) {
    if (!skippedCurrent) {
      skippedCurrent = true;
      return;
    }

    switch (output) {
      case SyncData<O>(:final value):
        if (value == expected) {
          completeValue(value);
        }
      case AsyncData<O>(:final value):
        if (value == expected) {
          completeValue(value);
        }
      case AsyncError<O>(:final error, :final stackTrace):
        completeError(error, stackTrace);
      case AsyncLoading<O>():
        break;
    }
  });

  Future.sync(action).catchError((Object error, StackTrace stackTrace) {
    completeError(error, stackTrace);
  });

  return completer.future
      .timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Expected next value after action: $expected',
          timeout,
        ),
      )
      .whenComplete(cancel);
}

// box.dart
@visibleForTesting
void updateInputForTest<I, O>(Box<I, O> box, I input) {
  box._updateInput(input);
}

@visibleForTesting
void updateAsyncInputForTest<I, O>(AsyncBox<I, O> box, I input) {
  box._updateInput(input);
}

// ── Graph.allSettled bookkeeping ────────────────────────────────────────
// Kept only when asserts are on (`dart test` and `flutter test` turn them
// on); release builds record nothing.

/// Graphs created so far — weakly held, so a forgotten graph is not kept
/// alive by this list.
final List<WeakReference<Graph<dynamic>>> _graphsForTest = [];

/// Async computes and background fetches running now, per box.
final Map<Object, int> _computingForTest = Map.identity();

void _noteGraphBorn(Graph<dynamic> graph) {
  assert(() {
    _graphsForTest
      ..removeWhere((r) => r.target == null || r.target!._disposed)
      ..add(WeakReference(graph));
    return true;
  }());
}

/// Counts [work] as running for [box] until it completes.
Future<T> _trackComputing<T>(Object box, Future<T> work) {
  if (!_tracking) return work;
  _computingForTest[box] = (_computingForTest[box] ?? 0) + 1;
  return work.whenComplete(() {
    final left = (_computingForTest[box] ?? 0) - 1;
    if (left > 0) {
      _computingForTest[box] = left;
    } else {
      _computingForTest.remove(box);
    }
  });
}

/// A disposed box's pending work no longer counts.
void _forgetComputing(Object box) {
  assert(() {
    _computingForTest.remove(box);
    return true;
  }());
}

Future<void> _allSettled(Duration timeout) async {
  if (!_tracking) {
    throw StateError(
      'Graph.allSettled() is for tests: it needs asserts on, as '
      '`dart test` and `flutter test` run. Production code waits for a '
      'value, not for quiet: `await box.firstReady`.',
    );
  }
  final clock = Stopwatch()..start();
  while (true) {
    await Future<void>.delayed(Duration.zero);
    _graphsForTest
        .removeWhere((r) => r.target == null || r.target!._disposed);
    final pumping = _graphsForTest.where((r) {
      final g = r.target!;
      return g._pumpScheduled || g._pumpingNow;
    }).length;
    if (pumping == 0 && _computingForTest.isEmpty) return;
    if (clock.elapsed > timeout) {
      final running = [
        for (final e in _computingForTest.entries)
          '${e.key.runtimeType}${e.value > 1 ? ' ×${e.value}' : ''}',
      ];
      throw TimeoutException(
        'Graph.allSettled: still busy after $timeout. '
        '${running.isEmpty ? '' : 'Still computing: ${running.join(', ')} — '
            'a compute that never completes (a fake left open) keeps it '
            'waiting: complete it, or dispose its graph in tearDown. '}'
        '${pumping == 0 ? '' : '$pumping graph(s) still pumping.'}',
        timeout,
      );
    }
  }
}
