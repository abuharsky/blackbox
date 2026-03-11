import 'package:blackbox/blackbox.dart';
import 'package:flutter/material.dart';
import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'boxes/step_config.dart';
import 'boxes/remote_step_config.dart';
import 'boxes/local_counter.dart';
import 'boxes/remote_counter.dart';
import 'ui/counter_page.dart';

class CounterRoot extends StatelessWidget {
  const CounterRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final stepConfig = StepConfig();
    final remoteStep = RemoteStepConfig(input: 1);
    final localCounter = LocalCounter(input: 1);
    final remoteCounter = RemoteCounter(input: 0);

    Graph.builder()
        .add(stepConfig)
        .addWith(
          remoteStep,
          dependencies: (d) => d.require(stepConfig),
        )
        .addWith(
          localCounter,
          dependencies: (d) => d.require(remoteStep),
        )
        .addWith(
          remoteCounter,
          dependencies: (d) => d.require(localCounter),
        )
        .build(start: true);

    return BoxProvider.multi(
      boxes: [
        stepConfig,
        remoteStep,
        localCounter,
        remoteCounter,
      ],
      child: CounterPage(),
    );
  }
}
