part of blackbox;

sealed class Output<T> {}

// Outputs are values, and values compare by content: `outputOf` puts
// them into input snapshots, and the pump's deduplication relies on ==.

final class SyncData<T> implements Output<T> {
  final T value;
  const SyncData(this.value);

  @override
  bool operator ==(Object other) =>
      other is SyncData<T> && other.value == value;

  @override
  int get hashCode => Object.hash(SyncData, value);
}

sealed class AsyncOutput<T> implements Output<T> {
  const AsyncOutput();
}

final class AsyncLoading<T> extends AsyncOutput<T> {
  final T? previousData;
  const AsyncLoading({this.previousData});

  @override
  bool operator ==(Object other) =>
      other is AsyncLoading<T> && other.previousData == previousData;

  @override
  int get hashCode => Object.hash(AsyncLoading, previousData);
}

final class AsyncData<T> extends AsyncOutput<T> {
  final T value;
  const AsyncData(this.value);

  @override
  bool operator ==(Object other) =>
      other is AsyncData<T> && other.value == value;

  @override
  int get hashCode => Object.hash(AsyncData, value);
}

final class AsyncError<T> extends AsyncOutput<T> {
  final Object error;
  final StackTrace stackTrace;
  final T? previousData;
  const AsyncError(this.error, this.stackTrace, {this.previousData});

  // stackTrace deliberately excluded: two occurrences of the same error
  // with the same shown data are the same phase for a fold. Occurrence
  // identity, when needed, is the seq pattern — a value with a number.
  @override
  bool operator ==(Object other) =>
      other is AsyncError<T> &&
      other.error == error &&
      other.previousData == previousData;

  @override
  int get hashCode => Object.hash(AsyncError, error, previousData);
}

extension AsyncOutputWhen<T> on AsyncOutput<T> {
  R when<R>({
    required R Function(T data) data,
    required R Function(T? previousData) loading,
    required R Function(Object error, StackTrace? stackTrace, T? previousData)
        error,
  }) {
    final self = this;

    if (self is AsyncData<T>) {
      return data(self.value);
    }

    if (self is AsyncLoading<T>) {
      return loading(self.previousData);
    }

    if (self is AsyncError<T>) {
      return error(self.error, self.stackTrace, self.previousData);
    }

    throw StateError('Unhandled AsyncOutput state: $self');
  }
}
