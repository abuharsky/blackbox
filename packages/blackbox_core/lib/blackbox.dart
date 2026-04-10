/// Core Blackbox library for deterministic reactive computation.
///
/// Exposes boxes, outputs, graph, persistence, and pipeline
/// APIs for building testable state and business-logic flows.
library blackbox;

import 'dart:async';

import 'package:meta/meta.dart';

part 'src/box.dart';
part 'src/cancel.dart';
part 'src/flow_box.dart';
part 'src/graph.dart';
part 'src/hooks.dart';
part 'src/output.dart';
part 'src/persistent.dart';
part 'src/pipeline.dart';
part 'src/trace.dart';

part 'src/test.dart';
