/// Blackbox: boxes, wires and effects — one law,
/// `output = compute(input, state)`.
///
/// Exposes boxes, outputs, graph, persistence, and pipeline APIs for
/// building testable state and business-logic flows. Tools that read a
/// running graph (the map) live in `package:blackbox/map.dart`.
library;

export 'src/blackbox_core.dart' hide GraphFacts;
