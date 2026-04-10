import 'dart:math';

import 'package:blackbox/blackbox.dart';

class RemoteCounter extends AsyncBox<int, int> {
  late int _counterValue;

  RemoteCounter({required int input}) : super(input);

  @override
  void onFirstCompute(int input, int? previous) {
    _counterValue = input;
  }

  @override
  Future<int> compute(int input, int? previous) async {
    await Future.delayed(
      Duration(milliseconds: (Random().nextInt(3) + 1) * 400),
    );
    _counterValue = input;
    return _counterValue;
  }
}
