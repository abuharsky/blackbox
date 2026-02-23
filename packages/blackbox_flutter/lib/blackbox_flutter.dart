/// Flutter integration for Blackbox reactive boxes.
///
/// Provides observer and provider widgets plus persistence adapters for wiring
/// Blackbox outputs into the Flutter widget tree.
library blackbox_flutter;

import 'package:blackbox/blackbox.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

export 'src/persistent_shared_prefs_store.dart';

part 'src/_tracker.dart';
part 'src/box_provider.dart';
part 'src/box_observer.dart';
