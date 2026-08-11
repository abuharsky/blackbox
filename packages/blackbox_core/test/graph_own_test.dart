import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// Box that records its own dispose into a shared log — used to prove
/// owned resources are released only after every box has stopped.
final class LoggingBox extends NoInputBox<int> {
  LoggingBox(this.log);
  final List<String> log;

  @override
  int compute() => 0;

  @override
  void dispose() {
    log.add('box disposed');
    super.dispose();
  }
}

void main() {
  group('graph.own', () {
    test('releases owned resources on dispose', () {
      final released = <String>[];
      final g = Graph.builder().add(LoggingBox([])).build()
        ..own(() => released.add('client'));

      g.dispose();
      expect(released, ['client']);
    });

    test('reverse registration order: last owned, first released', () {
      final released = <String>[];
      final g = Graph.builder().add(LoggingBox([])).build()
        ..own(() => released.add('first'))
        ..own(() => released.add('second'))
        ..own(() => released.add('third'));

      g.dispose();
      expect(released, ['third', 'second', 'first']);
    });

    test('owned resources are released after every box has stopped', () {
      final log = <String>[];
      final g = Graph.builder().add(LoggingBox(log)).build()
        ..own(() => log.add('client closed'));

      g.dispose();
      expect(log, ['box disposed', 'client closed']);
    });

    test('dispose is idempotent — owned callbacks run once', () {
      var releases = 0;
      final g = Graph.builder().add(LoggingBox([])).build()
        ..own(() => releases++);

      g.dispose();
      g.dispose();
      expect(releases, 1);
    });

    test('owning on an already-disposed graph releases immediately', () {
      final g = Graph.builder().add(LoggingBox([])).build();
      g.dispose();

      var released = false;
      g.own(() => released = true);
      expect(released, isTrue);
    });

    test('a throwing release does not block the others', () {
      final released = <String>[];
      final g = Graph.builder().add(LoggingBox([])).build()
        ..own(() => released.add('first'))
        ..own(() => throw StateError('boom'))
        ..own(() => released.add('third'));

      g.dispose();
      expect(released, ['third', 'first']);
    });
  });
}
