part of blackbox;

// cancel.dart
@visibleForTesting
Cancel cancelGuardedForTest(void Function() fn) => _cancelGuarded(fn);

// graph.dart
@visibleForTesting
T resolveDependencyForTest<T>(Graph g, OutputSource<T> box) {
  return DependencyResolver._(g).whenReady(box);
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
