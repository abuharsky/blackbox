import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// Runtime rules stated in doc/SEMANTICS.md that no other test pins.

final log = <String>[];

final class SourceBox extends NoInputBox<int> {
  late final _v = state(0);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

final class LoggingBox extends Box<int, int> {
  LoggingBox.late(this.name) : super.late();
  final String name;
  @override
  int compute(int n) {
    log.add(name);
    return n;
  }
}

final class LoggingMultiBox extends MultiBox<int> {
  late final seen = child(0);
  @override
  void compute(int n) {
    log.add('multibox');
    dispatch(seen, n);
  }
}

final class EchoMultiBox extends MultiBox<void> {
  late final distinctCell = child(0);
  late final everyCell = child(0, distinct: false);
  @override
  void compute(void _) {}
  void echo(int v) {
    dispatch(distinctCell, v);
    dispatch(everyCell, v);
  }
}

void main() {
  setUp(log.clear);

  test('one pump: boxes in declaration order, then multiboxes, then effects',
      () async {
    final source = SourceBox();
    final a = LoggingBox.late('a');
    final b = LoggingBox.late('b');
    final graph = Graph.builder()
        .add(source)
        .addMultiBox(LoggingMultiBox(), input: (d) => d.onlyWhenReady(source))
        .add(a, input: (d) => d.onlyWhenReady(source))
        .add(b, input: (d) => d.onlyWhenReady(a))
        .addEffect<int>((d) => d.onlyWhenReady(b),
            name: 'effect', run: (_, __) => log.add('effect'))
        .build();
    await graph.settled();
    log.clear();

    source.set(1);
    await graph.settled();
    expect(log, ['a', 'b', 'multibox', 'effect']);
    graph.dispose();
  });

  test('declaration order changes the number of pumps, never the result',
      () async {
    final source = SourceBox();
    final a = LoggingBox.late('a');
    final b = LoggingBox.late('b');
    final graph = Graph.builder()
        .add(source)
        .add(b, input: (d) => d.onlyWhenReady(a)) // reader before its source
        .add(a, input: (d) => d.onlyWhenReady(source))
        .build();
    source.set(7);
    await graph.settled();
    expect(b.value, 7);
    graph.dispose();
  });

  test('a write is heard at once by listeners; the graph catches up in a '
      'microtask', () async {
    final source = SourceBox();
    final a = LoggingBox.late('a');
    final graph = Graph.builder()
        .add(source)
        .add(a, input: (d) => d.onlyWhenReady(source))
        .build();
    await graph.settled();

    final heard = <int>[];
    source.listen((o) => heard.add((o as SyncData<int>).value), skipFirst: true);
    source.set(5);
    expect(heard, [5]); // the listener ran inside the write
    expect(a.value, 0); // the graph has not pumped yet
    await graph.settled();
    expect(a.value, 5);
    graph.dispose();
  });

  test('a multibox cell is ready from birth: onlyWhenReady never waits on it',
      () async {
    final mb = LoggingMultiBox(); // never driven: compute has not run
    final a = LoggingBox.late('a');
    final graph =
        Graph.builder().add(a, input: (d) => d.onlyWhenReady(mb.seen)).build();
    await graph.settled();
    expect(a.value, 0);
    graph.dispose();
  });

  test('a multibox cell ignores an equal value unless distinct: false',
      () async {
    final mb = EchoMultiBox();
    final graph =
        Graph.builder().addMultiBox(mb).build();
    final distinct = <int>[];
    final every = <int>[];
    mb.distinctCell.listen((o) => distinct.add((o as SyncData<int>).value),
        skipFirst: true);
    mb.everyCell.listen((o) => every.add((o as SyncData<int>).value),
        skipFirst: true);
    mb.echo(1);
    mb.echo(1);
    expect(distinct, [1]);
    expect(every, [1, 1]);
    graph.dispose();
  });

  test('listen delivers the current value at once; skipFirst does not',
      () {
    final source = SourceBox()..set(3);
    final first = <int>[];
    final skipped = <int>[];
    source.listen((o) => first.add((o as SyncData<int>).value));
    source.listen((o) => skipped.add((o as SyncData<int>).value), skipFirst: true);
    expect(first, [3]);
    expect(skipped, isEmpty);
  });
}
