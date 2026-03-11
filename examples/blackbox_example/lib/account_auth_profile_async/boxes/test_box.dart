import 'dart:async';

import 'package:blackbox/blackbox.dart';
import 'package:blackbox_annotations/blackbox_annotations.dart';

part 'test_box.box.g.dart';

@box
@lazy
class _TestBox {
  @boxCompute

  /// Test compute method for validating mixed input signatures.
  Future<String?> compute(
      String input1, int input2, Function() input3, String? previous) async {
    return "";
  }
}
