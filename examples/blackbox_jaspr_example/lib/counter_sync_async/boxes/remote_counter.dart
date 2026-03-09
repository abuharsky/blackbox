import 'dart:math';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';

part 'remote_counter.box.g.dart';

@box
@observable
class _RemoteCounter {
  late int _counterValue;

  @boxInit
  void init(int initial, int? previousOutput) {
    _counterValue = initial;
  }

  @boxCompute
  Future<int> _compute(int newCounterValue, int? previous) async {
    await Future.delayed(Duration(milliseconds: (Random().nextInt(3) + 1) * 400));
    _counterValue = newCounterValue;
    return _counterValue;
  }
}
