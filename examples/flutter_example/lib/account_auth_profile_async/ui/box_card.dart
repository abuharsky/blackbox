import 'package:blackbox/blackbox.dart';
import 'package:flutter/material.dart';

typedef OutputRenderer<O> = Widget Function(
  BuildContext context,
  O value,
);

class BoxCard<O> extends StatelessWidget {
  final String title;
  final Widget? subtitle;
  final Output<O> output;
  final List<Widget> actions;
  final OutputRenderer<O>? outputRenderer;

  const BoxCard({
    super.key,
    required this.title,
    required this.output,
    this.subtitle,
    this.actions = const [],
    this.outputRenderer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              title: title,
              subtitle: subtitle,
              state: output,
            ),
            const SizedBox(height: 12),
            _Body(
              output: output,
              outputRenderer: outputRenderer,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final Widget? subtitle;
  final Output<dynamic> state;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final badge = switch (state) {
      AsyncLoading() =>
        const _Badge(text: 'loading', icon: Icons.hourglass_bottom),
      AsyncError() => const _Badge(text: 'error', icon: Icons.error),
      SyncOutput() ||
      AsyncData() =>
        const _Badge(text: 'data', icon: Icons.check_circle),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                subtitle!,
              ],
            ],
          ),
        ),
        badge,
      ],
    );
  }
}

class _Body<O> extends StatelessWidget {
  final Output<O> output;
  final OutputRenderer<O>? outputRenderer;

  const _Body({
    required this.output,
    required this.outputRenderer,
  });

  @override
  Widget build(BuildContext context) {
    return switch (output) {
      AsyncLoading() => const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('loading…'),
          ],
        ),
      AsyncError(:var error) => Text(
          error.toString(),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.red),
        ),
      SyncOutput(:var value) || AsyncData(:var value) => outputRenderer != null
          ? outputRenderer!(context, value)
          : Text(value.toString()),
    };
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Badge({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}
