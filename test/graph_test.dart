import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

final class AddOneBox extends BoxWithInput<int, int> {
  int calls = 0;
  AddOneBox(super.initial);
  @override
  int compute(int input) {
    calls++;
    return input + 1;
  }
}

final class DepBox extends BoxWithInput<int, int> {
  int calls = 0;
  DepBox(super.initial);
  @override
  int compute(int input) {
    calls++;
    return input * 10;
  }
}

void main() {
  group('Graph', () {
    test('DependencyResolver.of throws if dependency not registered', () {
      final g = Graph();
      final a = SpySyncInputBox(1);

      // Not added -> not registered
      expect(() => resolveDependencyForTest(g, a), throwsStateError);
    });

    test('DependencyResolver.of throws if dependency not ready', () {
      final g = Graph();

      final source = SpySyncBox(1);

      final a = ControlledAsyncInputBox(1);

      g.add(source);

      // Register async box output updates into graph by adding it.
      g.addWithDependencies(
        a,
        dependencies: (d) => d.of(source),
      );

      expect(() => resolveDependencyForTest(g, a), throwsStateError);
    });

    test('add() registers outputs and pumps dependents on changes', () {
      final g = Graph();

      final source = SpySyncBox(1);
      final dep = AddOneBox(0);

      g.add(source);
      g.addWithDependencies(
        dep,
        dependencies: (d) => d.of(source),
      );

      // initial: source=1 => dep input=1 => dep output =2
      expect(dep.output.value, 2);

      source.setValue(5);
      expect(dep.output.value, 6);
    });

    test('GraphNode prevents repeated _updateInput when dependencies equal',
        () {
      final g = Graph();

      final source = SpySyncBox(1);
      final dep = DepBox(0);

      g.add(source);
      g.addWithDependencies(dep, dependencies: (d) => d.of(source));

      final before = dep.calls;
      // signal source without changing value => Graph still sees out change
      // (because SyncOutput has identity inequality) but dependency value is the same,
      // so GraphNode should skip.
      source.setValue(1);

      expect(dep.calls, before,
          reason: 'dep should not recompute with same input');
    });

    test('onError can swallow dependency resolution errors', () {
      final g = Graph();
      final dep = AddOneBox(0);

      g.addWithDependencies(
        dep,
        dependencies: (d) => d.of(SpySyncBox(1)), // never registered
        onError: (e) => e is StateError,
      );

      // should not throw during pump
      expect(() => schedulePumpForTest(g), returnsNormally);
    });

    test('onError rethrows when not handled', () {
      final g = Graph();
      final dep = AddOneBox(0);

      expect(
        () => g.addWithDependencies(
          dep,
          dependencies: (d) => d.of(SpySyncBox(1)), // never registered
          onError: (e) => false,
        ),
        throwsStateError,
      );
    });

    test('adding dependent on not-ready async dependency throws', () {
      final g = Graph();

      final source = SpySyncBox(1);
      final asyncSource = ControlledAsyncInputBox(1);
      final dep = AddOneBox(0);

      // source — валидный dependency source
      g.add(source);

      // asyncSource зависит от source → ок
      g.addWithDependencies(
        asyncSource,
        dependencies: (d) => d.of(source),
      );

      // dep зависит от asyncSource, который сейчас AsyncLoading
      // onError не передан → ошибка должна быть проброшена НЕМЕДЛЕННО
      expect(
        () => g.addWithDependencies(
          dep,
          dependencies: (d) => d.of(asyncSource),
        ),
        throwsStateError,
      );
    });

    test(
      'dependent recomputes when async dependency becomes ready (with onError)',
      () async {
        final g = Graph();

        final source = SpySyncBox(1);
        final asyncSource = ControlledAsyncInputBox(1);
        final dep = AddOneBox(0);

        g.add(source);

        g.addWithDependencies(
          asyncSource,
          dependencies: (d) => d.of(source),
        );

        g.addWithDependencies(
          dep,
          dependencies: (d) => d.of(asyncSource),
          onError: (e) => e is StateError,
        );

        // первая попытка была и подавлена onError
        expect(dep.calls, greaterThanOrEqualTo(1));

        asyncSource.completerFor(1).complete(10);
        await Future<void>.delayed(Duration.zero);

        // повторная попытка после readiness
        expect(dep.calls, greaterThanOrEqualTo(2));
        expect(dep.output.value, 11);
      },
    );

    test('dependent can be wired to async with onError until ready', () async {
      final g = Graph();

      final source = SpySyncBox(1);
      final asyncSource = ControlledAsyncInputBox(1);
      final dep = AddOneBox(0);

      g.add(source);
      g.addWithDependencies(asyncSource, dependencies: (d) => d.of(source));

      g.addWithDependencies(
        dep,
        dependencies: (d) => d.of(asyncSource),
        onError: (e) => e is StateError, // ignore "not ready"
      );

      // complete source => should pump and compute dependent
      asyncSource.completerFor(1).complete(7);
      await Future<void>.delayed(Duration.zero);

      expect(dep.output.value, 8);
    });
  });
}
