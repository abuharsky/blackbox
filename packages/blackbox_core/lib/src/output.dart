part of blackbox;

sealed class Output<T> {}

final class SyncOutput<T> implements Output<T> {
  final T value;
  const SyncOutput(this.value);
}

sealed class AsyncOutput<T> implements Output<T> {
  const AsyncOutput();
}

final class AsyncLoading<T> extends AsyncOutput<T> {
  const AsyncLoading();
}

final class AsyncData<T> extends AsyncOutput<T> {
  final T value;
  const AsyncData(this.value);
}

final class AsyncError<T> extends AsyncOutput<T> {
  final Object error;
  final StackTrace stackTrace;
  const AsyncError(this.error, this.stackTrace);
}
