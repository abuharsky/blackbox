import 'package:blackbox/blackbox.dart';

class LocalCounter extends Box<int, int> with Persisted<int, int> {
  late int _step;
  int _value = 0;

  LocalCounter({required int input}) : super(input);

  @override
  String persistKeyFor(int input) => '_LocalCounter';

  @override
  void onFirstCompute(int input, int? previous) {
    _step = input;
    _value = previous ?? input;
  }

  @override
  int compute(int input, int? previous) {
    _step = input;
    return _value;
  }

  void inc() => action(() => _value += _step);

  void dec() => action(() => _value -= _step);
}
