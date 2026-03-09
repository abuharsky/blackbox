import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'account_auth_profile_async/ui/services_page.dart';
import 'counter_sync_async/counter_root.dart';

enum _SampleKind {
  counter,
  account,
}

class SampleList extends StatefulComponent {
  const SampleList({super.key});

  @override
  State<SampleList> createState() => _SampleListState();
}

class _SampleListState extends State<SampleList> {
  _SampleKind _selected = _SampleKind.counter;

  @override
  Component build(BuildContext context) {
    final sample = switch (_selected) {
      _SampleKind.counter => const CounterRoot(),
      _SampleKind.account => const ServicesPage(),
    };

    return div([
      div([
        header([
          p(
            [Component.text('Blackbox + Jaspr')],
            styles: const Styles(
              raw: {
                'letter-spacing': '0.18em',
                'text-transform': 'uppercase',
                'font-size': '0.78rem',
                'color': '#9a3412',
                'margin': '0 0 0.75rem 0',
              },
            ),
          ),
          h1(
            [Component.text('Reactive boxes in a client-side Jaspr app')],
            styles: const Styles(
              raw: {
                'font-size': 'clamp(2.2rem, 5vw, 4.4rem)',
                'line-height': '1.02',
                'margin': '0',
                'max-width': '14ch',
              },
            ),
          ),
          p(
            [
              Component.text(
                'This example mirrors the Flutter sample with the same generated boxes, '
                'but uses blackbox_jaspr for observation and localStorage persistence.',
              ),
            ],
            styles: const Styles(
              raw: {
                'max-width': '56rem',
                'font-size': '1rem',
                'line-height': '1.7',
                'color': '#334155',
                'margin': '1rem 0 0 0',
              },
            ),
          ),
        ]),
        div([
          _SampleButton(
            label: 'Simple counter (Sync + Async)',
            active: _selected == _SampleKind.counter,
            onClick: () => setState(() => _selected = _SampleKind.counter),
          ),
          _SampleButton(
            label: 'Account + Auth + Profile (Async)',
            active: _selected == _SampleKind.account,
            onClick: () => setState(() => _selected = _SampleKind.account),
          ),
        ], styles: const Styles(raw: {
          'display': 'flex',
          'flex-wrap': 'wrap',
          'gap': '0.75rem',
          'margin-top': '1.5rem',
        })),
        div(
          [sample],
          styles: const Styles(
            raw: {
              'margin-top': '1.5rem',
            },
          ),
        ),
      ], styles: const Styles(raw: {
        'max-width': '1100px',
        'margin': '0 auto',
        'padding': '2rem 1.25rem 3rem',
      })),
    ], styles: const Styles(raw: {
      'min-height': '100vh',
      'background':
          'linear-gradient(180deg, #fff7ed 0%, #fffbeb 32%, #f8fafc 100%)',
      'color': '#0f172a',
      'font-family':
          '"IBM Plex Sans", "Segoe UI", system-ui, -apple-system, sans-serif',
    }));
  }
}

class _SampleButton extends StatelessComponent {
  const _SampleButton({
    required this.label,
    required this.active,
    required this.onClick,
  });

  final String label;
  final bool active;
  final VoidCallback onClick;

  @override
  Component build(BuildContext context) {
    return button(
      [Component.text(label)],
      onClick: onClick,
      styles: Styles(
        raw: {
          'border': active ? '1px solid #0f172a' : '1px solid #cbd5e1',
          'background': active ? '#0f172a' : 'rgba(255,255,255,0.72)',
          'color': active ? '#fff' : '#0f172a',
          'padding': '0.9rem 1.15rem',
          'border-radius': '999px',
          'font-size': '0.95rem',
          'font-weight': '600',
          'cursor': 'pointer',
          'box-shadow': active
              ? '0 16px 32px rgba(15,23,42,0.16)'
              : '0 8px 20px rgba(15,23,42,0.06)',
        },
      ),
    );
  }
}
