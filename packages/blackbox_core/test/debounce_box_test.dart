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

const _window = Duration(seconds: 1);

void main() {
  group('DebounceBox', () {
    test('rejects a non-positive window', () {
      expect(() => DebounceBox<int>(Duration.zero), throwsArgumentError);
      expect(() => DebounceBox<int>(const Duration(seconds: -1)),
          throwsArgumentError);
    });

    test('the first value passes at once', () {
      fakeAsync((async) {
        final raw = _Source<String?>('a');
        final debounced = DebounceBox<String?>(_window);
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .build();
        async.flushMicrotasks();
        expect(debounced.value, 'a');
        graph.dispose();
      });
    });

    test('changes faster than the window collapse into the last one', () {
      fakeAsync((async) {
        final raw = _Source<String?>(null);
        final debounced = DebounceBox<String?>(_window);
        final seen = <String?>[];
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .addEffect<String?>(
              (d) => d.onlyWhenReady(debounced),
              name: 'artwork',
              run: (cur, _) => seen.add(cur),
            )
            .build();
        async.flushMicrotasks();
        expect(seen, [null]);

        raw.set('title');
        async.elapse(const Duration(milliseconds: 300));
        raw.set('title · artist');
        async.elapse(const Duration(milliseconds: 300));
        raw.set('title · artist · cover');
        expect(seen, [null]); // nothing has been quiet for a second yet

        async.elapse(const Duration(milliseconds: 999));
        expect(seen, [null]);
        async.elapse(const Duration(milliseconds: 1));
        expect(seen, [null, 'title · artist · cover']); // one call, the last

        graph.dispose();
      });
    });

    test('a value that returns to what is shown cancels the pending one', () {
      fakeAsync((async) {
        final raw = _Source<String?>('a');
        final debounced = DebounceBox<String?>(_window);
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .build();
        async.flushMicrotasks();

        raw.set('b');
        async.elapse(const Duration(milliseconds: 500));
        raw.set('a'); // the blip is over before it settled
        async.elapse(const Duration(seconds: 2));
        expect(debounced.value, 'a');

        graph.dispose();
      });
    });

    test('a value that never rests never gets out — by contract', () {
      fakeAsync((async) {
        final raw = _Source(0);
        final debounced = DebounceBox<int>(_window);
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .build();
        async.flushMicrotasks();

        for (var i = 1; i <= 10; i++) {
          raw.set(i);
          async.elapse(const Duration(milliseconds: 500));
        }
        expect(debounced.value, 0);
        async.elapse(_window);
        expect(debounced.value, 10);

        graph.dispose();
      });
    });

    test('a shown null is a value, not "nothing yet"', () {
      fakeAsync((async) {
        final raw = _Source<String?>(null);
        final debounced = DebounceBox<String?>(_window);
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .build();
        async.flushMicrotasks();
        expect(debounced.value, isNull);

        raw.set('x');
        async.elapse(const Duration(milliseconds: 100));
        expect(debounced.value, isNull); // held, not passed as "first"

        graph.dispose();
      });
    });

    test('dispose cancels the pending value', () {
      fakeAsync((async) {
        final raw = _Source<String?>('a');
        final debounced = DebounceBox<String?>(_window);
        final graph = Graph.builder<void>()
            .add(raw)
            .add(debounced, input: (d) => d.onlyWhenReady(raw))
            .build();
        async.flushMicrotasks();
        raw.set('b');
        graph.dispose();
        async.elapse(const Duration(seconds: 5)); // no write after dispose
      });
    });

    test('is a node on the map, between source and reader', () async {
      final raw = _Source<String?>('a');
      final debounced = DebounceBox<String?>(_window);
      final graph = Graph.builder<void>()
          .add(raw)
          .add(debounced, input: (d) => d.onlyWhenReady(raw))
          .addEffect<String?>(
            (d) => d.onlyWhenReady(debounced),
            name: 'artwork',
            run: (_, __) {},
          )
          .build();
      await graph.settled();
      final map = graph.toMermaid();
      expect(map, contains('_Source_String__ --> DebounceBox_String__'));
      expect(map, contains('DebounceBox_String__ --> effect_1{{artwork}}'));
      graph.dispose();
    });
  });
}
