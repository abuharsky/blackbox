part of blackbox;

/// Result of a single box during a pump cycle.
enum BoxTraceResult {
  computed,
  skipped,
  waiting,

  /// The node threw (in its wire or its compute); it kept its previous
  /// output. See [GraphNodeError].
  failed,
}

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

  /// What was thrown (only for [BoxTraceResult.failed]).
  final String? error;

  const BoxTrace({
    required this.name,
    required this.result,
    this.value,
    this.input,
    this.error,
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

  /// The effect threw (in its wire or in `run`). See [GraphNodeError].
  failed,
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

  /// What was thrown (only for [EffectTraceResult.failed]).
  final String? error;

  const EffectTrace({
    required this.name,
    required this.result,
    this.input,
    this.previous,
    this.error,
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

  int get computed =>
      events.where((e) => e.result == BoxTraceResult.computed).length;
  int get waiting =>
      events.where((e) => e.result == BoxTraceResult.waiting).length;
  int get skipped =>
      events.where((e) => e.result == BoxTraceResult.skipped).length;

  /// Boxes, multiboxes and effects that threw this cycle.
  int get failed =>
      events.where((e) => e.result == BoxTraceResult.failed).length +
      effects.where((e) => e.result == EffectTraceResult.failed).length;

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
        final shown =
            event.value != null ? '→ ${event.value}' : '← ${event.input}';
        // ignore: avoid_print
        print('  ✓ ${event.name} $shown');
      case BoxTraceResult.waiting:
        // ignore: avoid_print
        print('  ○ ${event.name} — waiting');
      case BoxTraceResult.skipped:
        // ignore: avoid_print
        print('  · ${event.name} — unchanged');
      case BoxTraceResult.failed:
        // ignore: avoid_print
        print('  ✗ ${event.name} — failed in ${event.error}');
    }
  }

  for (final effect in trace.effects) {
    switch (effect.result) {
      case EffectTraceResult.ran:
        final was = effect.previous != null
            ? ' (was ${effect.previous})'
            : ' (first run)';
        // ignore: avoid_print
        print('  ⚡ ${effect.name} ← ${effect.input}$was');
      case EffectTraceResult.waiting:
        // ignore: avoid_print
        print('  ○ ${effect.name} — waiting');
      case EffectTraceResult.unchanged:
        // ignore: avoid_print
        print('  · ${effect.name} — unchanged');
      case EffectTraceResult.failed:
        // ignore: avoid_print
        print('  ✗ ${effect.name} — failed in ${effect.error}');
    }
  }

  final parts = <String>[];
  if (trace.computed > 0) parts.add('${trace.computed} computed');
  if (trace.waiting > 0) parts.add('${trace.waiting} waiting');
  if (trace.skipped > 0) parts.add('${trace.skipped} unchanged');
  if (trace.ran > 0) parts.add('${trace.ran} effects ran');
  if (trace.failed > 0) parts.add('${trace.failed} failed');
  // ignore: avoid_print
  print('[graph] pump #${trace.pumpCycle} done: ${parts.join(', ')}');
}
