import 'package:blackbox/blackbox.dart';

typedef CounterInput = ({int step});

class StepConfigBox extends NoInputBox<int> {
  int _step = 1;

  StepConfigBox();

  @override
  int compute(previous) => _step;

  void setStep(int step) {
    action(() {
      _step = step;
    });
  }
}

class CounterBox extends Box<CounterInput, int> {
  int _value = 0;
  int _currentStep = 1;

  CounterBox(int value) : super((step: value));

  @override
  int compute(CounterInput input, previous) {
    _currentStep = input.step;
    return _value;
  }

  void increment() {
    action(() {
      _value += _currentStep;
    });
  }

  void decrement() {
    action(() {
      _value -= _currentStep;
    });
  }
}
