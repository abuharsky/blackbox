part of blackbox;

/// Facts about graphs and boxes, read by tools — the map in
/// `package:blackbox/map.dart`. Not part of the model:
/// `package:blackbox/blackbox.dart` does not export it.
///
/// The core records; tools only read. Links that are not wires (presses,
/// touches, "wired in") are recorded in debug builds only — in release
/// they are empty.
abstract final class GraphFacts {
  /// What [graph] declared, in declaration order.
  static List<ProvidableBox> declared(Graph<dynamic> graph) => graph._declared;

  /// Each box or multibox [graph] drives, with the sources its wire has
  /// read (every one seen, in debug builds).
  static List<({Object target, Set<OutputSource<dynamic>> reads})> wires(
          Graph<dynamic> graph) =>
      [
        for (final node in graph._nodes)
          (target: node._source, reads: node._deps),
        for (final mbNode in graph._multiboxes)
          (target: mbNode.mb, reads: mbNode._deps),
      ];

  /// The effects of [graph], in registration order: what each reads, and
  /// which boxes it pressed (debug builds).
  static List<
      ({
        Object id,
        String name,
        bool named,
        String? wiredIn,
        Set<OutputSource<dynamic>> reads,
        Set<Object> presses,
      })> effects(Graph<dynamic> graph) => [
        for (final e in graph._effects)
          (
            id: e,
            name: e.name,
            named: e.named,
            wiredIn: e._wiredIn,
            reads: e._deps,
            presses: e._presses,
          ),
      ];

  /// The file [box] was declared in (debug builds), or `null`.
  static String? wiredIn(Object box) => _wiredInOf[box];

  /// Boxes and cells [box] touched — read or pressed — inside its own
  /// compute (debug builds): links the graph cannot see.
  static Set<Object> touches(Object box) =>
      _hiddenTouchesOf[box] ?? const <Object>{};

  /// The multibox that declared [cell].
  static MultiBox<dynamic> cellOwner(ChildCell<dynamic> cell) => cell._owner;

  /// The name given in `child(..., name:)`, or `null`.
  static String? cellName(ChildCell<dynamic> cell) => cell._name;
}
