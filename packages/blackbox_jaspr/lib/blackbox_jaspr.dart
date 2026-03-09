/// Jaspr integration for Blackbox reactive boxes.
///
/// Provides observer and provider components plus persistence adapters for
/// wiring Blackbox outputs into the Jaspr component tree.
library blackbox_jaspr;

import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:jaspr/jaspr.dart';

export 'src/persistent_local_storage_store.dart';

part 'src/_tracker.dart';
part 'src/box_observer.dart';
part 'src/box_provider.dart';
part 'src/observable_flow_box.dart';
