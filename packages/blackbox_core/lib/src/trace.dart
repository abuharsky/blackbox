part of blackbox;

/// Result of a single box during a pump cycle.
enum BoxTraceResult { computed, skipped, waiting }

/// Trace event for a single box in a pump cycle.
final class BoxTrace {
  final String name;
  final BoxTraceResult result;

  /// Display string for the new output value (only for [BoxTraceResult.computed]).
  final String? value;

  const BoxTrace({
    required this.name,
    required this.result,
    this.value,
  });
}

/// Trace of a complete pump cycle.
final class PumpTrace {
  final int pumpCycle;

  /// Name of the box whose emission triggered this pump, or null for initial pump.
  final String? triggeredBy;

  final List<BoxTrace> events;

  const PumpTrace({
    required this.pumpCycle,
    required this.triggeredBy,
    required this.events,
  });

  int get computed => events.where((e) => e.result == BoxTraceResult.computed).length;
  int get waiting => events.where((e) => e.result == BoxTraceResult.waiting).length;
  int get skipped => events.where((e) => e.result == BoxTraceResult.skipped).length;
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
        // ignore: avoid_print
        print('  ✓ ${event.name} → ${event.value}');
      case BoxTraceResult.waiting:
        // ignore: avoid_print
        print('  ○ ${event.name} — waiting');
      case BoxTraceResult.skipped:
        // ignore: avoid_print
        print('  · ${event.name} — unchanged');
    }
  }

  final parts = <String>[];
  if (trace.computed > 0) parts.add('${trace.computed} computed');
  if (trace.waiting > 0) parts.add('${trace.waiting} waiting');
  if (trace.skipped > 0) parts.add('${trace.skipped} unchanged');
  // ignore: avoid_print
  print('[graph] pump #${trace.pumpCycle} done: ${parts.join(', ')}');
}
