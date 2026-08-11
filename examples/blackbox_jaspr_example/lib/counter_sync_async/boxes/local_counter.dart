import 'package:blackbox/blackbox.dart';

class LocalCounter extends Box<int, int> {
  late final _value = state(0, persist: '_LocalCounter');

  LocalCounter({required int input}) : super(input);

  @override
  int compute(int step) => _value.value;

  void inc() => _value.value += input;

  void dec() => _value.value -= input;
}
