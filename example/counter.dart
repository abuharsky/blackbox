import 'package:blackbox/blackbox.dart';

typedef StepInput = ();
typedef CounterInput = ({int step});

class StepConfigBox extends Box<int> {
  int _step = 1;

  StepConfigBox();

  @override
  int compute() => _step;

  void setStep(int step) {
    signal(() {
      _step = step;
    });
  }
}

class CounterBox extends BoxWithInput<CounterInput, int> {
  int _value = 0;
  int _currentStep = 1;

  CounterBox(int value) : super((step: value));

  @override
  int compute(CounterInput input) {
    // Cache latest dependencies snapshot for signal handlers.
    _currentStep = input.step;
    return _value;
  }

  void increment() {
    signal(() {
      _value += _currentStep;
    });
  }

  void decrement() {
    signal(() {
      _value -= _currentStep;
    });
  }
}
