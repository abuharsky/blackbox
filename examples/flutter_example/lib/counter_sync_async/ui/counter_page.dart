import 'package:blackbox_flutter/blackbox_flutter.dart';
import 'package:flutter/material.dart';

import '../../account_auth_profile_async/ui/box_card.dart';
import '../boxes/step_config.dart';
import '../boxes/remote_step_config.dart';
import '../boxes/local_counter.dart';
import '../boxes/remote_counter.dart';

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.box<StepConfig>();
    final remoteStep = context.box<RemoteStepConfig>();
    final local = context.box<LocalCounter>();
    final remote = context.box<RemoteCounter>();

    Widget info(String text) => Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Blackbox Example')),
      body: BoxObserver(
        builder: (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                /// ---------- Step (sync)
                BoxCard<int>(
                  title: 'Step (sync)',
                  subtitle: info('''
A simple synchronous box.
Stores a numeric step value in memory.
Press + / − to update the value immediately.
No async operations involved.
'''),
                  output: step.output,
                  actions: [
                    IconButton(
                      onPressed: step.dec,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: step.inc,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 12,
                  child: Icon(Icons.arrow_downward_outlined),
                ),

                /// ---------- Remote Step (async)
                BoxCard<int>(
                  title: 'Remote Step',
                  subtitle: info(
                    '''An asynchronous box.
Loads the step value from an external source.
You will see loading first, then either data or error.
''',
                  ),
                  output: remoteStep.output,
                ),

                const SizedBox(
                  height: 12,
                  child: Icon(Icons.arrow_downward_outlined),
                ),

                /// ---------- Local Counter (sync)
                BoxCard<int>(
                  title: 'Local Counter',
                  subtitle: info(
                    '''A local in-memory counter.
State exists only while the app is running.
Each button press updates the value synchronously.
''',
                  ),
                  output: local.output,
                  actions: [
                    IconButton(
                      onPressed: local.dec,
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      onPressed: local.inc,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 12,
                  child: Icon(Icons.arrow_downward_outlined),
                ),

                /// ---------- Remote Counter (async)
                BoxCard<int>(
                  title: 'Remote Counter',
                  subtitle: info(
                    '''An asynchronous counter.
Each update triggers a remote request.
Demonstrates loading and error handling.''',
                  ),
                  output: remote.output,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
