import 'package:blackbox/blackbox.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

typedef OutputRenderer<O> = Component Function(
  BuildContext context,
  O value,
);

class BoxCard<O> extends StatelessComponent {
  const BoxCard({
    required this.title,
    required this.output,
    this.subtitle,
    this.actions = const [],
    this.outputRenderer,
    super.key,
  });

  final String title;
  final Component? subtitle;
  final Output<O> output;
  final List<Component> actions;
  final OutputRenderer<O>? outputRenderer;

  @override
  Component build(BuildContext context) {
    return article([
      _Header(
        title: title,
        subtitle: subtitle,
        state: output,
      ),
      div(
        [
          _Body(
            output: output,
            outputRenderer: outputRenderer,
          ),
        ],
        styles: const Styles(raw: {
          'margin-top': '1rem',
          'padding-top': '1rem',
          'border-top': '1px solid #e2e8f0',
        }),
      ),
      if (actions.isNotEmpty)
        div(actions, styles: const Styles(raw: {
          'display': 'flex',
          'flex-wrap': 'wrap',
          'gap': '0.65rem',
          'margin-top': '1rem',
        })),
    ], styles: const Styles(raw: {
      'margin': '0.85rem 0',
      'padding': '1.2rem',
      'border-radius': '1.25rem',
      'border': '1px solid rgba(148,163,184,0.22)',
      'background': 'rgba(255,255,255,0.82)',
      'box-shadow': '0 14px 40px rgba(15,23,42,0.08)',
      'backdrop-filter': 'blur(8px)',
    }));
  }
}

class _Header extends StatelessComponent {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final Component? subtitle;
  final Output<dynamic> state;

  @override
  Component build(BuildContext context) {
    final badge = switch (state) {
      AsyncLoading() => const _Badge(
          text: 'loading',
          tone: '#f59e0b',
          background: 'rgba(245,158,11,0.14)',
        ),
      AsyncError() => const _Badge(
          text: 'error',
          tone: '#ef4444',
          background: 'rgba(239,68,68,0.14)',
        ),
      SyncOutput() || AsyncData() => const _Badge(
          text: 'data',
          tone: '#10b981',
          background: 'rgba(16,185,129,0.14)',
        ),
    };

    return div([
      div([
        h3(
          [Component.text(title)],
          styles: const Styles(raw: {
            'margin': '0',
            'font-size': '1.12rem',
          }),
        ),
        if (subtitle != null) subtitle!,
      ], styles: const Styles(raw: {
        'display': 'grid',
        'gap': '0.2rem',
        'min-width': '0',
      })),
      badge,
    ], styles: const Styles(raw: {
      'display': 'flex',
      'justify-content': 'space-between',
      'gap': '1rem',
      'align-items': 'flex-start',
      'flex-wrap': 'wrap',
    }));
  }
}

class _Body<O> extends StatelessComponent {
  const _Body({
    required this.output,
    required this.outputRenderer,
  });

  final Output<O> output;
  final OutputRenderer<O>? outputRenderer;

  @override
  Component build(BuildContext context) {
    return switch (output) {
      AsyncLoading() => p(
          [Component.text('loading...')],
          styles: const Styles(raw: {'margin': '0', 'color': '#92400e'}),
        ),
      AsyncError(:final error) => p(
          [Component.text(error.toString())],
          styles: const Styles(raw: {
            'margin': '0',
            'color': '#b91c1c',
            'white-space': 'pre-wrap',
          }),
        ),
      SyncOutput(:final value) || AsyncData(:final value) => outputRenderer != null
          ? outputRenderer!(context, value)
          : p(
              [Component.text('$value')],
              styles: const Styles(raw: {'margin': '0'}),
            ),
    };
  }
}

class _Badge extends StatelessComponent {
  const _Badge({
    required this.text,
    required this.tone,
    required this.background,
  });

  final String text;
  final String tone;
  final String background;

  @override
  Component build(BuildContext context) {
    return span(
      [Component.text(text)],
      styles: Styles(raw: {
        'display': 'inline-flex',
        'align-items': 'center',
        'border-radius': '999px',
        'padding': '0.4rem 0.7rem',
        'font-size': '0.74rem',
        'font-weight': '700',
        'text-transform': 'uppercase',
        'letter-spacing': '0.08em',
        'background': background,
        'color': tone,
      }),
    );
  }
}
