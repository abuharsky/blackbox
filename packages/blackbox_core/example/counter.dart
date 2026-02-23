import 'package:blackbox/blackbox.dart';

typedef StepInput = ();
typedef CounterInput = ({int step});

class StepConfigBox extends Box<int> {
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

class CounterBox extends BoxWithInput<CounterInput, int> {
  int _value = 0;
  int _currentStep = 1;

  CounterBox(int value) : super((step: value));

  @override
  int compute(CounterInput input, previout) {
    // Cache latest dependencies snapshot for action handlers.
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
