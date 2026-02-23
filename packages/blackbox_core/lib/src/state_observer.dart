part of blackbox;

final class _StateObserverStep<S> {
  final OutputSource<dynamic> box;
  final S? Function(dynamic value) map;

  _StateObserverStep(this.box, this.map);
}

final class StateObserverBuilder<S> {
  final List<_StateObserverStep<S>> _steps = [];

  StateObserverBuilder<S> on<O>(
    OutputSource<dynamic> box,
    S? Function(O value) map,
  ) {
    _steps.add(
      _StateObserverStep<S>(
        box,
        (v) => map(v as O),
      ),
    );
    return this;
  }

  StateObserver<S> build({required S initial}) {
    return StateObserver<S>._(initial, _steps);
  }
}

final class StateObserver<S> {
  S _state;
  final _listeners = <void Function(S)>[];

  final _queue = <void Function()>[];

  StateObserver._(this._state, List<_StateObserverStep<S>> steps) {
    for (final step in steps) {
      step.box.listen((out) {
        if (out is SyncOutput) {
          _enqueue(() {
            final next = step.map(out.value);
            if (next != null && next != _state) {
              _state = next;
              _emit();
            }
          });
        }

        if (out is AsyncOutput) {
          if (!out.isReady) return;

          _enqueue(() {
            final next = step.map(out.value);
            if (next != null && next != _state) {
              _state = next;
              _emit();
            }
          });
        }
      });
    }
  }

  S get state => _state;

  Cancel listen(void Function(S) listener) {
    _listeners.add(listener);
    listener(_state);

    return _cancelGuarded(() => _listeners.remove(listener));
  }

  void _emit() {
    for (final l in _listeners) {
      l(_state);
    }
  }

  void _enqueue(void Function() job) {
    _queue.add(job);
    _queue.removeAt(0)();
  }
}
