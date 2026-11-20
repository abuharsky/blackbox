import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox/map.dart';
import 'package:test/test.dart';

/// One rule, debug builds only: inside a box's compute (or a cached
/// fetch), touching another box — reading it or pressing its buttons —
/// is a hidden link (`⚠`). Not another box: the box itself and its own
/// cells. Not a touch: a read inside BoxHooks.untracked.

final class ValueBox extends NoInputBox<int> {
  late final _v = state(0);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

/// Presses another box from its fetch — the field's FreshStationBox →
/// myStations.adopt.
final class RecheckBox extends AsyncBox<int, int> {
  RecheckBox.late(this._adopt) : super.late();
  final ValueBox _adopt;
  @override
  Future<int> compute(int n) async {
    await Future<void>.delayed(Duration.zero);
    _adopt.set(n);
    return n;
  }
}

/// A button that reads its own box before writing — like adopt().
final class ListBox extends NoInputBox<List<int>> {
  late final _items = state<List<int>>(const []);
  @override
  List<int> compute() => _items.value;
  void adopt(int n) {
    if (value.contains(n)) return;
    _items.value = [...value, n];
  }
}

final class AdoptingBox extends Box<int, int> {
  AdoptingBox.late(this._list) : super.late();
  final ListBox _list;
  @override
  int compute(int n) {
    _list.adopt(n);
    return n;
  }
}

final class DoubleBox extends Box<int, int> {
  DoubleBox(super.input);
  @override
  int compute(int n) => n * 2;
}

/// Builds a throwaway box inside its compute and reads it — the field's
/// UpcomingCoversBox → TrackLookupBox. A touch like any other; a
/// deliberate snapshot says so with untracked.
final class ToolUserBox extends Box<int, int> {
  ToolUserBox.late({this.snapshot = false}) : super.late();
  final bool snapshot;
  @override
  int compute(int n) {
    final tool = DoubleBox(n);
    return snapshot ? BoxHooks.untracked(() => tool.value) : tool.value;
  }
}

/// Reads a captured box in compute.
final class PeekBox extends Box<int, int> {
  PeekBox.late(this._other) : super.late();
  final ValueBox _other;
  @override
  int compute(int n) => n + _other.value;
}

Future<List<String>> capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(body,
      zoneSpecification:
          ZoneSpecification(print: (_, __, ___, line) => lines.add(line)));
  return lines;
}

Future<(Graph<void>, List<String>)> run(
    Box<int, int> box, ValueBox n) async {
  late Graph<void> graph;
  final lines = await capturePrints(() async {
    graph =
        Graph.builder().add(n).add(box, input: (d) => d.onlyWhenReady(n)).build();
    n.set(3);
    await pumpEventQueue();
  });
  return (graph, lines);
}

void main() {
  test('pressing another box from a fetch is a touch', () async {
    final adopted = ValueBox();
    final recheck = RecheckBox.late(adopted);
    final n = ValueBox();
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      graph = Graph.builder()
          .add(n)
          .add(recheck, input: (d) => d.onlyWhenReady(n))
          .build();
      n.set(3);
      await pumpEventQueue();
    });
    final m = graphMap({'g': graph});
    expect(m, contains('⚠ touches: `ValueBox` (outside)'));
    expect(m, contains('`RecheckBox` touched `ValueBox`'));
    expect(lines.where((l) => l.contains('RecheckBox touched ValueBox')),
        hasLength(1));
    graph.dispose();
  });

  test('read and press of one box are one link, one warning', () async {
    final (graph, lines) = await run(AdoptingBox.late(ListBox()), ValueBox());
    expect(lines.where((l) => l.contains('AdoptingBox touched ListBox')),
        hasLength(1));
    expect(lines, hasLength(1));
    expect(
        '`AdoptingBox` touched `ListBox`'.allMatches(graphMap({'g': graph})),
        hasLength(1));
    graph.dispose();
  });

  test('a tool box built inside compute is a touch; untracked says snapshot',
      () async {
    final (touching, lines) = await run(ToolUserBox.late(), ValueBox());
    expect(lines.where((l) => l.contains('ToolUserBox touched DoubleBox')),
        hasLength(1));
    touching.dispose();

    final (quiet, _) = await run(ToolUserBox.late(snapshot: true), ValueBox());
    expect(graphMap({'g': quiet}), contains('⚠ Hidden links: none seen.'));
    quiet.dispose();
  });

  test('pressing counts even when the value does not change', () async {
    final source = ValueBox();
    final target = ValueBox();
    final graph = Graph.builder()
        .add(source)
        .addEffect<int>((d) => d.onlyWhenReady(source),
            name: 'note', run: (_, __) => target.set(0)) // already 0
        .build();
    await pumpEventQueue();
    expect(graphMap({'g': graph}), contains('⇒ presses `ValueBox` (outside)'));
    graph.dispose();
  });

  test('a warning is printed once per pair of types, not per instance',
      () async {
    final lines = await capturePrints(() async {
      for (var i = 0; i < 5; i++) {
        final n = ValueBox();
        final graph = Graph.builder()
            .add(n)
            .add(PeekBox.late(ValueBox()), input: (d) => d.onlyWhenReady(n))
            .build();
        await pumpEventQueue();
        graph.dispose();
      }
    });
    expect(lines.where((l) => l.contains('PeekBox touched ValueBox')),
        hasLength(1));
  });
}
