import 'package:blackbox/blackbox.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

final class _Source<T> extends NoInputBox<T> {
  _Source(this._initial);
  final T _initial;
  late final _v = state(_initial);

  @override
  T compute() => _v.value;

  void set(T v) => _v.value = v;
}

enum _PlayerState { loading, playing }

/// Builds `source → HysteresisBox → effect`, recording what the effect saw.
({Graph<void> graph, List<bool> calls}) _rig(
  _Source<bool> source,
  HysteresisBox box,
) {
  final calls = <bool>[];
  final graph = Graph.builder<void>()
      .add(source)
      .add(box, input: (d) => d.onlyWhenReady(source))
      .addEffect<bool>(
        (d) => d.onlyWhenReady(box),
        name: 'switch',
        run: (cur, _) => calls.add(cur),
      )
      .build();
  return (graph: graph, calls: calls);
}

void main() {
  group('HysteresisBox', () {
    test('rejects negative durations', () {
      expect(() => HysteresisBox(on: const Duration(seconds: -1)),
          throwsArgumentError);
      expect(() => HysteresisBox(off: const Duration(seconds: -1)),
          throwsArgumentError);
    });

    test('off from birth; both zero is a plain switch', () {
      fakeAsync((async) {
        final wanted = _Source(false);
        final (:graph, :calls) = _rig(wanted, HysteresisBox());
        async.flushMicrotasks();
        expect(calls, [false]);

        wanted.set(true);
        async.flushMicrotasks();
        expect(calls, [false, true]);

        wanted.set(false);
        async.flushMicrotasks();
        expect(calls, [false, true, false]);

        graph.dispose();
      });
    });

    test('off: up at once, down only after continuous false', () {
      fakeAsync((async) {
        final playing = _Source(false);
        final (:graph, :calls) =
            _rig(playing, HysteresisBox(off: const Duration(seconds: 3)));
        async.flushMicrotasks();
        expect(calls, [false]);

        playing.set(true);
        async.flushMicrotasks();
        expect(calls, [false, true]); // immediately

        // The device rebuilds: a one-second dip through `loading`.
        playing.set(false);
        async.elapse(const Duration(seconds: 1));
        playing.set(true);
        async.elapse(const Duration(seconds: 5));
        expect(calls, [false, true]); // the dip never reached the switch

        playing.set(false);
        async.elapse(const Duration(seconds: 2, milliseconds: 999));
        expect(calls, [false, true]);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, [false, true, false]); // a real stop, after the hold

        graph.dispose();
      });
    });

    test('on: shown only if it lasts, hidden at once (a spinner)', () {
      fakeAsync((async) {
        final state = _Source(_PlayerState.playing);
        final spinner = HysteresisBox(on: const Duration(milliseconds: 300));
        final calls = <bool>[];
        final graph = Graph.builder<void>()
            .add(state)
            .add(spinner,
                input: (d) =>
                    d.onlyWhenReady(state) == _PlayerState.loading)
            .addEffect<bool>(
              (d) => d.onlyWhenReady(spinner),
              name: 'spinner',
              run: (cur, _) => calls.add(cur),
            )
            .build();
        async.flushMicrotasks();
        expect(calls, [false]);

        // A 50 ms buffer: never shown.
        state.set(_PlayerState.loading);
        async.elapse(const Duration(milliseconds: 50));
        state.set(_PlayerState.playing);
        async.elapse(const Duration(seconds: 1));
        expect(calls, [false]);

        // A real load: shown after 300 ms, hidden the moment it ends.
        state.set(_PlayerState.loading);
        async.elapse(const Duration(milliseconds: 299));
        expect(calls, [false]);
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, [false, true]);
        state.set(_PlayerState.playing);
        async.flushMicrotasks();
        expect(calls, [false, true, false]);

        graph.dispose();
      });
    });

    test('a first true is off from birth — it waits `on` like any rise', () {
      fakeAsync((async) {
        final wanted = _Source(true);
        final (:graph, :calls) =
            _rig(wanted, HysteresisBox(on: const Duration(seconds: 1)));
        async.flushMicrotasks();
        expect(calls, [false]);
        async.elapse(const Duration(seconds: 1));
        expect(calls, [false, true]);
        graph.dispose();
      });
    });

    test('equal on and off is a bool debounce', () {
      fakeAsync((async) {
        final wanted = _Source(false);
        const d = Duration(seconds: 1);
        final (:graph, :calls) = _rig(wanted, HysteresisBox(on: d, off: d));
        async.flushMicrotasks();

        for (var i = 0; i < 6; i++) {
          wanted.set(i.isEven);
          async.elapse(const Duration(milliseconds: 400));
        }
        expect(calls, [false]); // never quiet for a second
        async.elapse(d);
        expect(calls, [false]); // ended on false, which is what is shown

        wanted.set(true);
        async.elapse(d);
        expect(calls, [false, true]);

        graph.dispose();
      });
    });

    test('dispose cancels the pending switch', () {
      fakeAsync((async) {
        final wanted = _Source(true);
        final (:graph, :calls) =
            _rig(wanted, HysteresisBox(off: const Duration(seconds: 3)));
        async.flushMicrotasks();
        expect(calls, [true]); // on: zero — a first true is up at once
        wanted.set(false);
        graph.dispose();
        async.elapse(const Duration(seconds: 10)); // no write after dispose
        expect(calls, [true]);
      });
    });
  });
}
