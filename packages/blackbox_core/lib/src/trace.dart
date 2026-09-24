part of blackbox;

/// Result of a single box during a pump cycle.
enum BoxTraceResult { computed, skipped, waiting }

/// Trace event for a single box (or multibox) in a pump cycle.
final class BoxTrace {
  final String name;
  final BoxTraceResult result;

  /// Display string for the new output value (only for
  /// [BoxTraceResult.computed], and only for boxes — a multibox has no
  /// single output, so its trace carries [input] instead).
  final String? value;

  /// Display string for the input delivered this cycle (only for
  /// [BoxTraceResult.computed]; recorded for multiboxes).
  final String? input;

  const BoxTrace({
    required this.name,
    required this.result,
    this.value,
    this.input,
  });
}

/// Result of a single effect during a pump cycle.
enum EffectTraceResult {
  /// The input changed (or it is the first pump) — `run` was called.
  ran,

  /// The input equals the previous one — `run` was skipped.
  unchanged,

  /// A required source is not ready — the effect did not run.
  waiting,
}

/// Trace event for a single effect in a pump cycle: which effect, whether
/// it ran, and with what input against which previous input. This is the
/// line that makes an effect commanding the outside world visible:
/// the graph structure shows the wire, the trace shows the call.
final class EffectTrace {
  final String name;
  final EffectTraceResult result;

  /// Display string for the input `run` received (only for
  /// [EffectTraceResult.ran]).
  final String? input;

  /// Display string for the previous input `run` received, `null` on the
  /// first run (only for [EffectTraceResult.ran]).
  final String? previous;

  const EffectTrace({
    required this.name,
    required this.result,
    this.input,
    this.previous,
  });
}

/// Trace of a complete pump cycle.
final class PumpTrace {
  final int pumpCycle;

  /// Name of the box whose emission triggered this pump, or null for initial pump.
  final String? triggeredBy;

  /// Boxes and multiboxes, in pump order.
  final List<BoxTrace> events;

  /// Effects, in registration order.
  final List<EffectTrace> effects;

  const PumpTrace({
    required this.pumpCycle,
    required this.triggeredBy,
    required this.events,
    this.effects = const [],
  });

  int get computed => events.where((e) => e.result == BoxTraceResult.computed).length;
  int get waiting => events.where((e) => e.result == BoxTraceResult.waiting).length;
  int get skipped => events.where((e) => e.result == BoxTraceResult.skipped).length;

  /// Effects whose `run` was called this cycle.
  int get ran => effects.where((e) => e.result == EffectTraceResult.ran).length;
}

/// Default console printer for [PumpTrace].
void _defaultTracePrinter(PumpTrace trace) {
  final trigger = trace.triggeredBy;
  final header = trigger != null
      ? '[graph] pump #${trace.pumpCycle} (triggered by: $trigger)'
      : '[graph] pump #${trace.pumpCycle}';
  // ignore: avoid_print
  print(header);

  for (final event in trace.events) {
    switch (event.result) {
      case BoxTraceResult.computed:
        final shown = event.value != null
            ? '→ ${event.value}'
            : '← ${event.input}';
        // ignore: avoid_print
        print('  ✓ ${event.name} $shown');
      case BoxTraceResult.waiting:
        // ignore: avoid_print
        print('  ○ ${event.name} — waiting');
      case BoxTraceResult.skipped:
        // ignore: avoid_print
        print('  · ${event.name} — unchanged');
    }
  }

  for (final effect in trace.effects) {
    switch (effect.result) {
      case EffectTraceResult.ran:
        final was =
            effect.previous != null ? ' (was ${effect.previous})' : ' (first run)';
        // ignore: avoid_print
        print('  ⚡ ${effect.name} ← ${effect.input}$was');
      case EffectTraceResult.waiting:
        // ignore: avoid_print
        print('  ○ ${effect.name} — waiting');
      case EffectTraceResult.unchanged:
        // ignore: avoid_print
        print('  · ${effect.name} — unchanged');
    }
  }

  final parts = <String>[];
  if (trace.computed > 0) parts.add('${trace.computed} computed');
  if (trace.waiting > 0) parts.add('${trace.waiting} waiting');
  if (trace.skipped > 0) parts.add('${trace.skipped} unchanged');
  if (trace.ran > 0) parts.add('${trace.ran} effects ran');
  // ignore: avoid_print
  print('[graph] pump #${trace.pumpCycle} done: ${parts.join(', ')}');
}
