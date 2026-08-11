import 'package:blackbox/blackbox.dart';

class StepConfig extends NoInputBox<int> {
  int _step = 1;

  StepConfig();

  @override
  int compute() => _step;

  void inc() => action(() => _step++);

  void dec() => action(() => _step--);
}
