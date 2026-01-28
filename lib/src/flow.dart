part of blackbox;

/// Один шаг flow: box + mapper
final class _FlowStep<S> {
  final _OutputSource<dynamic> box;
  final S? Function(dynamic value) map;

  _FlowStep(this.box, this.map);
}

final class FlowBuilder<S> {
  final List<_FlowStep<S>> _steps = [];

  FlowBuilder<S> on<O>(
    _OutputSource<dynamic> box,
    S? Function(O value) map,
  ) {
    _steps.add(
      _FlowStep<S>(
        box,
        (v) => map(v as O),
      ),
    );
    return this;
  }

  Flow<S> build({required S initial}) {
    return Flow<S>._(initial, _steps);
  }
}

final class Flow<S> {
  S _state;
  final _listeners = <void Function(S)>[];

  final _queue = <void Function()>[];

  Flow._(this._state, List<_FlowStep<S>> steps) {
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
