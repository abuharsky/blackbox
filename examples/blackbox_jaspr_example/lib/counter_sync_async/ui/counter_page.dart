import 'package:blackbox_jaspr/blackbox_jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../account_auth_profile_async/ui/box_card.dart';
import '../boxes/local_counter.dart';
import '../boxes/remote_counter.dart';
import '../boxes/remote_step_config.dart';
import '../boxes/step_config.dart';

class CounterPage extends StatelessComponent {
  const CounterPage({super.key});

  @override
  Component build(BuildContext context) {
    final step = context.box<StepConfig>();
    final remoteStep = context.box<RemoteStepConfig>();
    final local = context.box<LocalCounter>();
    final remote = context.box<RemoteCounter>();

    Component info(String text) {
      return p(
        [Component.text(text)],
        styles: const Styles(
          raw: {
            'margin': '0.45rem 0 0',
            'font-size': '0.94rem',
            'line-height': '1.65',
            'color': '#475569',
          },
        ),
      );
    }

    Component arrow() {
      return div(
        [Component.text('↓')],
        styles: const Styles(
          raw: {
            'text-align': 'center',
            'font-size': '1.35rem',
            'color': '#f97316',
            'padding': '0.25rem 0',
          },
        ),
      );
    }

    return BoxObserver(
      builder: (_) => section([
        h2(
          [Component.text('Simple counter chain')],
          styles: const Styles(raw: {
            'margin': '0 0 0.5rem',
            'font-size': '1.4rem',
          }),
        ),
        p(
          [
            Component.text(
              'A sync step box feeds a remote step, then a persistent local counter, and finally an async remote counter.',
            ),
          ],
          styles: const Styles(raw: {
            'margin': '0 0 1rem',
            'line-height': '1.7',
            'color': '#334155',
          }),
        ),
        BoxCard<int>(
          title: 'Step (sync)',
          subtitle: info('Keeps the current step in memory and updates immediately.'),
          output: step.output,
          actions: [
            _ActionButton(label: 'step -', onClick: step.dec),
            _ActionButton(label: 'step +', onClick: step.inc),
          ],
          outputRenderer: (_, value) => strong([Component.text('value: $value')]),
        ),
        arrow(),
        BoxCard<int>(
          title: 'Remote Step (async)',
          subtitle: info('Simulates a delayed remote sync for the current step.'),
          output: remoteStep.output,
          outputRenderer: (_, value) => strong([Component.text('value: $value')]),
        ),
        arrow(),
        BoxCard<int>(
          title: 'Local Counter (persistent)',
          subtitle: info('Persists its value in localStorage through LocalStorageStore.'),
          output: local.output,
          actions: [
            _ActionButton(label: 'local -', onClick: local.dec),
            _ActionButton(label: 'local +', onClick: local.inc),
          ],
          outputRenderer: (_, value) => strong([Component.text('value: $value')]),
        ),
        arrow(),
        BoxCard<int>(
          title: 'Remote Counter (async)',
          subtitle: info('Recomputes after the local counter changes and shows async output states.'),
          output: remote.output,
          outputRenderer: (_, value) => strong([Component.text('value: $value')]),
        ),
      ]),
    );
  }
}

class _ActionButton extends StatelessComponent {
  const _ActionButton({
    required this.label,
    required this.onClick,
  });

  final String label;
  final VoidCallback onClick;

  @override
  Component build(BuildContext context) {
    return button(
      [Component.text(label)],
      onClick: onClick,
      styles: const Styles(
        raw: {
          'border': '1px solid #fdba74',
          'background': '#fff7ed',
          'color': '#9a3412',
          'padding': '0.65rem 0.9rem',
          'border-radius': '0.8rem',
          'font-weight': '600',
          'cursor': 'pointer',
        },
      ),
    );
  }
}
