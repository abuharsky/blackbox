part of blackbox;

sealed class Output<T> {}

final class SyncData<T> implements Output<T> {
  final T value;
  const SyncData(this.value);
}

sealed class AsyncOutput<T> implements Output<T> {
  const AsyncOutput();
}

final class AsyncLoading<T> extends AsyncOutput<T> {
  final T? previousData;
  const AsyncLoading({this.previousData});
}

final class AsyncData<T> extends AsyncOutput<T> {
  final T value;
  const AsyncData(this.value);
}

final class AsyncError<T> extends AsyncOutput<T> {
  final Object error;
  final StackTrace stackTrace;
  final T? previousData;
  const AsyncError(this.error, this.stackTrace, {this.previousData});
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
