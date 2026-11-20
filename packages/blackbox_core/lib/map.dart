/// The map of an application's graphs as a Markdown file — a tool, not
/// part of the model. It reads the facts the core records; it never
/// changes how a graph runs.
///
/// ```dart
/// import 'package:blackbox/map.dart';
///
/// File('doc/MAP.md').writeAsStringSync(
///   graphMap({'player': player.graph, 'catalog': catalog.graph}),
/// );
/// ```
library;

export 'src/map/graph_map.dart' show graphMap;
