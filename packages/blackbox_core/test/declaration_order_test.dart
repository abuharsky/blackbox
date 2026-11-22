import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:test/test.dart';

/// Debug-only: a wire that reads a line below its own warns, once per
/// pair of types, and says which line to move.

/// A box without input changes only by its buttons, before a pump —
/// never mid-pump — so it has no line and is never "below".
final class ListPriceBox extends NoInputBox<int> {
  late final _v = state(100);
  @override
  int compute() => _v.value;
  void set(int v) => _v.value = v;
}

/// Fed by a wire: it changes during the pump, on its own line.
final class PriceBox extends Box<int, int> {
  PriceBox.late() : super.late();
  @override
  int compute(int listPrice) => listPrice;
}

final class TaxBox extends Box<int, int> {
  TaxBox.late() : super.late();
  @override
  int compute(int price) => price ~/ 10;
}

final class GoodTaxBox extends Box<int, int> {
  GoodTaxBox.late() : super.late();
  @override
  int compute(int price) => price ~/ 10;
}

final class FeedMultiBox extends MultiBox<int> {
  late final last = child(0, name: 'last');
  @override
  void compute(int n) => dispatch(last, n);
}

final class ShowMultiBox extends MultiBox<int> {
  late final shown = child(0);
  @override
  void compute(int n) => dispatch(shown, n);
}

final class CellReaderBox extends Box<int, int> {
  CellReaderBox.late() : super.late();
  @override
  int compute(int n) => n;
}

Future<List<String>> capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  await runZoned(body,
      zoneSpecification:
          ZoneSpecification(print: (_, __, ___, line) => lines.add(line)));
  return lines;
}

void main() {
  test('a box reading a box declared below it warns, naming the line to '
      'move; effects see the mixed pair for one pump', () async {
    final charges = <int>[];
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      final list = ListPriceBox();
      final price = PriceBox.late();
      final tax = TaxBox.late();
      graph = Graph.builder()
          .add(list)
          .add(tax, input: (d) => d.onlyWhenReady(price)) // above its source
          .add(price, input: (d) => d.onlyWhenReady(list))
          .addEffect((d) => (d.onlyWhenReady(price), d.onlyWhenReady(tax)),
              run: (c, _) => charges.add(c.$1 + c.$2), name: 'charge')
          .build();
      await graph.settled();
      charges.clear();
      list.set(200);
      await graph.settled();
    });

    // The reason for the warning: one pump with new price and old tax.
    expect(charges, [210, 220]);
    final warnings = lines.where((l) => l.contains('declared below')).toList();
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('TaxBox reads PriceBox'));
    expect(warnings.single, contains('Move the line of TaxBox below PriceBox'));
    graph.dispose();
  });

  test('in order, nothing is printed and effects see one consistent pair',
      () async {
    final charges = <int>[];
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      final list = ListPriceBox();
      final price = PriceBox.late();
      final tax = GoodTaxBox.late();
      graph = Graph.builder()
          .add(list)
          .add(price, input: (d) => d.onlyWhenReady(list))
          .add(tax, input: (d) => d.onlyWhenReady(price))
          .addEffect((d) => (d.onlyWhenReady(price), d.onlyWhenReady(tax)),
              run: (c, _) => charges.add(c.$1 + c.$2), name: 'charge')
          .build();
      await graph.settled();
      charges.clear();
      list.set(200);
      await graph.settled();
    });

    expect(charges, [220]);
    expect(lines.where((l) => l.contains('declared below')), isEmpty);
    graph.dispose();
  });

  test('a multibox reading a cell of a multibox declared below it warns',
      () async {
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      final price = ListPriceBox();
      final feed = FeedMultiBox();
      final show = ShowMultiBox();
      graph = Graph.builder()
          .add(price)
          .addMultiBox(show, input: (d) => d.onlyWhenReady(feed.last))
          .addMultiBox(feed, input: (d) => d.onlyWhenReady(price))
          .build();
      await graph.settled();
    });

    expect(
        lines.where((l) => l.contains('declared below')).single,
        allOf(contains('ShowMultiBox reads FeedMultiBox.last'),
            contains('Move the line of ShowMultiBox below FeedMultiBox')));
    graph.dispose();
  });

  test('reading a box without input does not warn: it changes only '
      'before a pump', () async {
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      final list = ListPriceBox();
      final tax = TaxBox.late();
      graph = Graph.builder()
          .add(tax, input: (d) => d.onlyWhenReady(list))
          .add(list)
          .build();
      await graph.settled();
      list.set(300);
      await graph.settled();
      expect(tax.value, 30);
    });

    expect(lines.where((l) => l.contains('declared below')), isEmpty);
    graph.dispose();
  });

  test('a box reading a multibox cell does not warn: boxes always run '
      'first, so no line move would help', () async {
    late Graph<void> graph;
    final lines = await capturePrints(() async {
      final price = ListPriceBox();
      final feed = FeedMultiBox();
      final reader = CellReaderBox.late();
      graph = Graph.builder()
          .add(price)
          .add(reader, input: (d) => d.onlyWhenReady(feed.last))
          .addMultiBox(feed, input: (d) => d.onlyWhenReady(price))
          .build();
      await graph.settled();
    });

    expect(lines.where((l) => l.contains('declared below')), isEmpty);
    graph.dispose();
  });
}
