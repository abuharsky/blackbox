import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';

part 'test_box.box.g.dart';

@box
@lazy
@observable
class _TestBox {
  @boxCompute
  /// Test compute method for validating mixed input signatures.
  Future<String?> compute(
      String input1, int input2, Function() input3, String? previous) async {
    return "";
  }
}
