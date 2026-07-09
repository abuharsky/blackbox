part of blackbox;

/// Async box with deferred initialization via graph.
@Deprecated(
  'Extend AsyncBox and use the AsyncBox.late(initialValue:) constructor '
  'instead — same behavior, no separate class.',
)
abstract class LateAsyncBox<I, O> extends AsyncBox<I, O> {
  LateAsyncBox({O? initialValue}) : super.late(initialValue: initialValue);
}
