import 'package:blackbox/blackbox.dart';
import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/jaspr.dart';

import 'boxes/local_counter.dart';
import 'boxes/remote_counter.dart';
import 'boxes/remote_step_config.dart';
import 'boxes/step_config.dart';
import 'ui/counter_page.dart';

class CounterRoot extends StatefulComponent {
  const CounterRoot({super.key});

  @override
  State<CounterRoot> createState() => _CounterRootState();
}

class _CounterRootState extends State<CounterRoot> {
  late final StepConfig _stepConfig;
  late final RemoteStepConfig _remoteStep;
  late final LocalCounter _localCounter;
  late final RemoteCounter _remoteCounter;
  late final Graph _graph;

  @override
  void initState() {
    super.initState();

    _stepConfig = StepConfig();
    _remoteStep = RemoteStepConfig(input: 1);
    _localCounter = LocalCounter(input: 1);
    _remoteCounter = RemoteCounter(input: 0);

    _graph = Graph.builder()
        .add(_stepConfig)
        .add(
          _remoteStep,
          input: (d) => d.whenReady(_stepConfig),
        )
        .add(
          _localCounter,
          input: (d) => d.whenReady(_remoteStep),
        )
        .add(
          _remoteCounter,
          input: (d) => d.whenReady(_localCounter),
        )
        .build(start: true);
  }

  @override
  void dispose() {
    _graph.dispose();
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    return BoxProvider.multi(
      boxes: [
        _stepConfig,
        _remoteStep,
        _localCounter,
        _remoteCounter,
      ],
      child: const CounterPage(),
    );
  }
}
