/// Core Blackbox library for deterministic reactive computation.
///
/// Exposes boxes, outputs, runtime, graph connector, persistence, and pipeline
/// APIs for building testable state and business-logic flows.
library blackbox;

import 'dart:async';

import 'package:meta/meta.dart';

part 'src/box.dart';
part 'src/cancel.dart';
part 'src/connector.dart';
part 'src/lazy.dart';
part 'src/output.dart';
part 'src/persistent.dart';
part 'src/pipeline.dart';
part 'src/runtime.dart';
part 'src/state_observer.dart';

part 'src/test.dart';
