part of blackbox;

// cancel.dart
@visibleForTesting
Cancel cancelGuardedForTest(void Function() fn) => _cancelGuarded(fn);

// graph.dart
@visibleForTesting
T resolveDependencyForTest<T>(Graph g, OutputSource<T> box) {
  return DependencyResolver._(g).ready(box);
}

@visibleForTesting
void schedulePumpForTest(Graph g) {
  g._schedulePump();
}

@visibleForTesting
bool isReadyForTest<T>(Output<T> o) {
  return o.isReady;
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
