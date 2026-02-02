part of blackbox;

// cancel.dart
@visibleForTesting
Cancel cancelGuardedForTest(void Function() fn) => _cancelGuarded(fn);

// graph.dart
@visibleForTesting
T resolveDependencyForTest<T>(Connector g, _OutputSource<T> box) {
  return DependencyResolver._(g).of(box);
}

@visibleForTesting
void schedulePumpForTest(Connector g) {
  g._schedulePump();
}

@visibleForTesting
bool isReadyForTest<T>(Output<T> o) {
  return o.isReady;
}

// box.dart
@visibleForTesting
void updateInputForTest<I, O>(_InputBox<I, O> box, I input) {
  box._updateInput(input);
}
