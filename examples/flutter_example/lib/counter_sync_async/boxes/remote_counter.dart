import 'dart:math';
import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

part 'remote_counter.box.g.dart';

@box
@observable
class _RemoteCounter {
  late int _counterValue;

  @boxInit
  /// Initializes remote counter state.
  init(int initial, int? previousOutput) {
    _counterValue = initial;
  }

  @boxCompute
  /// Simulates remote synchronization and returns updated counter value.
  Future<int> _compute(int newCounterValue, previous) async {
    await Future.delayed(Duration(seconds: Random().nextInt(3) + 1));
    _counterValue = newCounterValue;
    return _counterValue;
  }
}
