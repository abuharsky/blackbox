/// The map of graphs as one Markdown document — a tool that reads the
/// facts the core records ([GraphFacts]). See `package:blackbox/map.dart`.
library;

import '../blackbox_core.dart';

enum _Kind { box, multibox, cell, effect }

final class _MapVertex {
  _MapVertex(this.object, this.base, this.kind, this.graph);

  final Object object;
  final String base;
  final _Kind kind;

  /// The graph that drives it; `null` — read here, driven elsewhere.
  final String? graph;

  String label = '';
  String id = '';
  String? wiredIn;
  bool unnamed = false; // effects only
  _MapVertex? owner; // a cell's multibox
  final List<_MapVertex> cells = [];
  final List<_MapVertex> inputs = [];
  final List<_MapVertex> readers = [];
  final List<_MapVertex> presses = []; // effect → boxes it pressed
  final List<_MapVertex> pressedBy = []; // box ← effects that pressed it
  final List<_MapVertex> touches = []; // box → foreign boxes touched in compute
  final List<_MapVertex> touchedBy = [];

  bool get isBox => kind == _Kind.box || kind == _Kind.multibox;
}

/// The map of several graphs as one Markdown document: an overview (per
/// graph, what it reads from the others and what its effects press; the
/// boxes outside them; every hidden link), a small picture of how the
/// graphs connect, and an index — for each box the graph that drives it,
/// the file it is wired in, its input wires, its readers, the effects
/// that press it, the boxes it touches where the graph cannot see.
/// Keys are the graphs' names on the map.
///
/// Made to be committed: a test builds the app headless, drives the
/// scenarios whose links belong on the map, and compares `graphMap` with
/// `doc/MAP.md` — so the map cannot go stale, and every PR that changes a
/// wire shows it in the diff.
///
/// ```dart
/// final map = graphMap({'player': player.graph, 'catalog': catalog.graph});
/// ```
///
/// What it can see: wires that have run; presses and touches in debug
/// builds. What it cannot: commands from UI, `listen` and closures
/// outside boxes — a link between boxes missing here is not a wire.
String graphMap(Map<String, Graph<dynamic>> graphs) {
  final vertices = <_MapVertex>[];
  final byObject = Map<Object, _MapVertex>.identity();

  _MapVertex add(Object o, String base, _Kind kind, String? graph) =>
      byObject.putIfAbsent(o, () {
        final v = _MapVertex(o, base, kind, graph);
        vertices.add(v);
        return v;
      });

  String cellBase(String owner, ChildCell<dynamic> cell) =>
      '$owner.${GraphFacts.cellName(cell) ?? '${cell.runtimeType}'.replaceFirst('ChildCell', 'cell')}';

  // A cell always sits under its multibox — also one the multibox has
  // let go of (a forgotten clock moment) — and cells of one multibox
  // named alike are one line: the same question, asked again.
  _MapVertex cellVertex(ChildCell<dynamic> cell, _MapVertex owner) {
    final known = byObject[cell];
    if (known != null) return known;
    final base = cellBase(owner.base, cell);
    if (GraphFacts.cellName(cell) != null) {
      for (final sibling in owner.cells) {
        if (sibling.base == base) return byObject[cell] = sibling;
      }
    }
    final v = add(cell, base, _Kind.cell, owner.graph)..owner = owner;
    owner.cells.add(v);
    return v;
  }

  _MapVertex multibox(MultiBox<dynamic> mb, String? graph) {
    final v = add(mb, '${mb.runtimeType}', _Kind.multibox, graph);
    for (final child in mb.children) {
      cellVertex(child as ChildCell<dynamic>, v);
    }
    return v;
  }

  // Any object a link points at; one no listed graph drives is still a
  // vertex — read (or pressed) here, driven elsewhere.
  _MapVertex vertexOf(Object o) {
    final known = byObject[o];
    if (known != null) return known;
    if (o is ChildCell) {
      final mb = GraphFacts.cellOwner(o);
      final owner = byObject[mb] ?? multibox(mb, null);
      return cellVertex(o, owner);
    }
    if (o is MultiBox) return multibox(o, null);
    return add(o, '${o.runtimeType}', _Kind.box, null);
  }

  // 1. What each graph drives, in declaration order.
  for (final MapEntry(key: name, value: g) in graphs.entries) {
    for (final declared in GraphFacts.declared(g)) {
      final v = declared is MultiBox
          ? multibox(declared, name)
          : add(declared, '${declared.runtimeType}', _Kind.box, name);
      v.wiredIn = GraphFacts.wiredIn(declared);
    }
    for (final effect in GraphFacts.effects(g)) {
      add(effect.id, effect.name, _Kind.effect, name)
        ..wiredIn = effect.wiredIn
        ..unnamed = !effect.named;
    }
  }

  // 2. Links: wires, presses, touches.
  void link(List<_MapVertex> out, _MapVertex to, List<_MapVertex> back,
      _MapVertex from) {
    if (out.contains(to)) return;
    out.add(to);
    back.add(from);
  }

  for (final g in graphs.values) {
    void wires(Object node, Iterable<OutputSource<dynamic>> deps) {
      final to = byObject[node]!;
      for (final dep in deps) {
        link(to.inputs, vertexOf(dep), vertexOf(dep).readers, to);
      }
    }

    for (final wire in GraphFacts.wires(g)) {
      wires(wire.target, wire.reads);
    }
    for (final effect in GraphFacts.effects(g)) {
      wires(effect.id, effect.reads);
      final e = byObject[effect.id]!;
      for (final pressed in effect.presses) {
        final target = vertexOf(pressed);
        link(e.presses, target, target.pressedBy, e);
      }
    }
  }
  for (final v in List.of(vertices)) {
    if (!v.isBox) continue;
    for (final touched in GraphFacts.touches(v.object)) {
      final t = vertexOf(touched);
      link(v.touches, t, t.touchedBy, v);
    }
  }

  // 3. Labels unique within a graph (references across graphs carry the
  //    graph's name); ids unique in the whole document.
  final groupCount = <String, int>{};
  String groupKey(_MapVertex v) => '${v.graph}\u0000${v.base}';
  for (final v in vertices) {
    groupCount[groupKey(v)] = (groupCount[groupKey(v)] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final ids = <String>{};
  for (final v in vertices) {
    final n = seen[groupKey(v)] = (seen[groupKey(v)] ?? 0) + 1;
    v.label = groupCount[groupKey(v)]! > 1 ? '${v.base} #$n' : v.base;
    v.id = _uniqueId('${v.graph ?? 'outside'}_${v.label}', ids);
  }
  int byLabel(_MapVertex a, _MapVertex b) => a.label.compareTo(b.label);
  for (final v in vertices) {
    for (final list in [
      v.inputs,
      v.readers,
      v.presses,
      v.pressedBy,
      v.touches,
      v.touchedBy,
    ]) {
      list.sort(byLabel);
    }
  }

  String ref(_MapVertex v, String? from) {
    final notes = [
      if (v.graph != from) v.graph == null ? 'outside' : '`${v.graph}`',
      if (v.unnamed) 'unnamed',
    ];
    final name =
        v.kind == _Kind.effect ? 'effect `${v.label}`' : '`${v.label}`';
    return notes.isEmpty ? name : '$name (${notes.join(', ')})';
  }

  String refs(List<_MapVertex> vs, String? from) =>
      vs.map((v) => ref(v, from)).join(', ');

  // A graph, or an outside box (its cells folded into it): the nodes of
  // the overview picture.
  String group(_MapVertex v) =>
      v.graph != null ? 'g:${v.graph}' : 'o:${(v.owner ?? v).id}';

  final out = StringBuffer()
    ..writeln('# Graph map')
    ..writeln()
    ..writeln('How to read it:')
    ..writeln()
    ..writeln('- A box is listed under the graph that drives it (declares '
        'it). Any graph may read it. Boxes read here but driven by none of '
        'these graphs are listed under *Outside*.')
    ..writeln('- `←` input wires: the box re-runs when one of these changes. '
        '`→` readers: what re-runs when this box changes.')
    ..writeln('- `⇒` an effect pressed this box\'s buttons (from its `run`, '
        'a timer it started, or after an await) — a legal ring, not a wire.')
    ..writeln('- `⚠` a hidden link: inside its compute (or cached fetch) a '
        'box touched another box — read it or pressed its buttons — where '
        'the graph cannot see. Need its value: wire it. Commanding it: move '
        'the command into an effect.')
    ..writeln('- Links appear once they have happened while the map was '
        'recorded (debug build). Commands from UI, `listen` and closures '
        'outside boxes are not here: a link between boxes that is missing '
        'from this map is not a wire.');

  // ---- Overview ----------------------------------------------------------
  final outsideBoxes =
      vertices.where((v) => v.graph == null && v.isBox).toList()..sort(byLabel);
  final effects = vertices.where((v) => v.kind == _Kind.effect).toList();
  final unnamed = effects.where((v) => v.unnamed).length;
  final hidden = [
    for (final v in vertices) ...[
      for (final t in v.touches) '`${v.label}` touched `${t.label}`',
    ],
  ];

  String counts(Map<String, int> m) => m.isEmpty
      ? '—'
      : (m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          .map((e) => '${e.key} ${e.value}')
          .join(', ');

  String groupName(String key) {
    if (key.startsWith('g:')) return '`${key.substring(2)}`';
    final v = vertices.firstWhere((v) => v.id == key.substring(2));
    return '`${v.label}`';
  }

  out
    ..writeln()
    ..writeln('## Overview')
    ..writeln()
    ..writeln('| graph | boxes | effects | reads from other graphs | '
        'its effects press |')
    ..writeln('|---|---|---|---|---|');
  for (final name in graphs.keys) {
    final own = vertices.where((v) => v.graph == name);
    final reads = <String, int>{};
    final presses = <String, int>{};
    for (final v in own) {
      for (final input in v.inputs) {
        final from = group(input);
        if (from == 'g:$name') continue;
        reads[groupName(from)] = (reads[groupName(from)] ?? 0) + 1;
      }
      for (final target in v.presses) {
        final to =
            group(target) == 'g:$name' ? 'itself' : groupName(group(target));
        presses[to] = (presses[to] ?? 0) + 1;
      }
    }
    out.writeln('| `$name` | ${own.where((v) => v.isBox).length} '
        '| ${own.where((v) => v.kind == _Kind.effect).length} '
        '| ${counts(reads)} | ${counts(presses)} |');
  }
  out
    ..writeln()
    ..writeln(outsideBoxes.isEmpty
        ? 'Outside these graphs: nothing.'
        : 'Outside these graphs (read here, driven elsewhere): '
            '${outsideBoxes.map((v) => '`${v.label}`').join(', ')}.')
    ..writeln()
    ..writeln(hidden.isEmpty
        ? '⚠ Hidden links: none seen.'
        : '⚠ Hidden links (${hidden.length}): ${hidden.join('; ')}.')
    ..writeln()
    ..writeln('Effects: ${effects.length}, unnamed: $unnamed'
        '${unnamed > 0 ? ' — name them: `addEffect(..., name: \'...\')`' : ''}.');

  // The small picture: graphs and outside boxes, links counted.
  final edges = <String, int>{};
  void count(String from, String to, String kind) {
    if (from == to) return;
    final key = '$from\u0000$to\u0000$kind';
    edges[key] = (edges[key] ?? 0) + 1;
  }

  for (final v in vertices) {
    for (final input in v.inputs) {
      count(group(input), group(v), 'wire');
    }
    for (final target in v.presses) {
      count(group(v), group(target), 'press');
    }
    for (final touched in v.touches) {
      count(group(v), group(touched), 'hidden');
    }
  }
  String nodeId(String key) => key.startsWith('g:')
      ? 'graph_${_safe(key.substring(2))}'
      : key.substring(2);

  out
    ..writeln()
    ..writeln('```mermaid')
    ..writeln('flowchart LR');
  for (final name in graphs.keys) {
    out.writeln('  ${nodeId('g:$name')}(["$name"])');
  }
  for (final v in outsideBoxes) {
    out.writeln('  ${v.id}["${_mermaidText(v.label)}"]');
  }
  for (final MapEntry(:key, :value) in edges.entries) {
    final [from, to, kind] = key.split('\u0000');
    final line = switch (kind) {
      'press' => '==>|⇒ $value|',
      'hidden' => '-.->|⚠ $value|',
      _ => '-->|$value|',
    };
    out.writeln('  ${nodeId(from)} $line ${nodeId(to)}');
  }
  out
    ..writeln('```')
    ..writeln()
    ..writeln('Arrow `-->|n|`: n wires read across. `==>|⇒ n|`: effects '
        'press n boxes there. `-.->|⚠ n|`: n hidden links.');

  // ---- Per graph ---------------------------------------------------------
  void entry(_MapVertex v, String? commonFile) {
    final kind = switch (v.kind) {
      _Kind.multibox => ' · multibox',
      _Kind.effect => v.unnamed ? ' · unnamed' : '',
      _ => '',
    };
    final wired = v.wiredIn != null && v.wiredIn != commonFile
        ? ' · wired in `${v.wiredIn}`'
        : '';
    final title =
        v.kind == _Kind.effect ? 'effect `${v.label}`' : '`${v.label}`';
    out.writeln('- **$title**$kind$wired');
    if (v.graph != null) {
      out.writeln(v.inputs.isEmpty
          ? '  - ← no input wires'
          : '  - ← ${refs(v.inputs, v.graph)}');
    }
    if (v.pressedBy.isNotEmpty) {
      out.writeln('  - ⇐ pressed by ${refs(v.pressedBy, v.graph)}');
    }
    if (v.touches.isNotEmpty) {
      out.writeln('  - ⚠ touches: ${refs(v.touches, v.graph)}');
    }
    if (v.presses.isNotEmpty) {
      out.writeln('  - ⇒ presses ${refs(v.presses, v.graph)}');
    }
    for (final c in v.cells) {
      final readers = c.readers.isEmpty
          ? 'no graph reads it (UI or `listen` may)'
          : refs(c.readers, v.graph);
      out.writeln('  - cell `${c.label}` → $readers');
      if (c.touchedBy.isNotEmpty) {
        out.writeln('    - ⚠ touched by ${refs(c.touchedBy, v.graph)}');
      }
    }
    if (v.kind == _Kind.box) {
      out.writeln(v.readers.isEmpty
          ? '  - → no graph reads it (UI or `listen` may)'
          : '  - → ${refs(v.readers, v.graph)}');
    }
    if (v.touchedBy.isNotEmpty) {
      out.writeln('  - ⚠ touched by ${refs(v.touchedBy, v.graph)}');
    }
  }

  String? mostCommonFile(Iterable<_MapVertex> vs) {
    final files = <String, int>{};
    for (final v in vs) {
      final f = v.wiredIn;
      if (f != null) files[f] = (files[f] ?? 0) + 1;
    }
    if (files.isEmpty) return null;
    return (files.entries.toList()
          ..sort((a, b) => b.value != a.value
              ? b.value.compareTo(a.value)
              : a.key.compareTo(b.key)))
        .first
        .key;
  }

  for (final name in graphs.keys) {
    final own = vertices.where((v) => v.graph == name).toList();
    final file = mostCommonFile(own);
    out
      ..writeln()
      ..writeln('## `$name`')
      ..writeln();
    if (file != null) {
      out
        ..writeln('Wired in `$file`.')
        ..writeln();
    }
    out
      ..writeln('### Boxes')
      ..writeln();
    final boxes = own.where((v) => v.isBox).toList();
    if (boxes.isEmpty) out.writeln('None.');
    for (final v in boxes) {
      entry(v, file);
    }
    final ownEffects = own.where((v) => v.kind == _Kind.effect).toList();
    if (ownEffects.isNotEmpty) {
      out
        ..writeln()
        ..writeln('### Effects')
        ..writeln();
      for (final v in ownEffects) {
        entry(v, file);
      }
    }
  }

  if (outsideBoxes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Outside these graphs')
      ..writeln()
      ..writeln('Read (or pressed) here, driven by none of the graphs above.')
      ..writeln();
    for (final v in outsideBoxes) {
      entry(v, null);
    }
  }
  return out.toString();
}

String _safe(String s) {
  final safe = s
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return safe.isEmpty ? 'node' : safe;
}

String _uniqueId(String raw, Set<String> taken) {
  final base = _safe(raw);
  var id = base;
  for (var k = 2; !taken.add(id); k++) {
    id = '${base}_$k';
  }
  return id;
}

String _mermaidText(String s) =>
    s.replaceAll('"', '#quot;').replaceAll('<', '#lt;').replaceAll('>', '#gt;');
