part of blackbox_flutter;

/// Debug aid: a box read while widgets build, with no [BoxObserver]
/// tracking it.
///
/// Such a read returns the current value and subscribes nobody — the
/// widget shows a snapshot and stays stale until something unrelated
/// rebuilds it. The bug is silent and order-dependent: it shows only when
/// that "something" happens not to come. Two shapes in practice:
///
/// - a read in a plain widget's `build` (it is no observer);
/// - a read in a callback that runs later than the observer's builder —
///   `LayoutBuilder`, `itemBuilder`, `Builder` — those run outside its
///   tracking.
///
/// The check prints one warning per read site, with the frames that led
/// to it. It runs only in debug builds and only during the build phase:
/// reads in `onPressed`, actions and the graph are snapshots by design and
/// stay quiet. So are reads made from `initState` and
/// `didChangeDependencies` (directly, or in a `listen` callback that fires
/// on subscribe): an initial value taken once is their whole point. Any
/// other deliberate snapshot during build goes in
/// `BoxHooks.untracked(() => ...)`.
///
/// Installed by [BoxObserver] and [BoxProvider] on first use; [install]
/// does it explicitly. An `onUntrackedRead` set by someone else is left
/// alone.
abstract final class BoxReadCheck {
  /// `false` — the check stays installed but says nothing.
  static bool enabled = true;

  static final Set<String> _reported = <String>{};

  /// Installs the check (debug builds only; a no-op in release).
  static void install() {
    assert(() {
      BoxHooks.onUntrackedRead ??= _onUntrackedRead;
      return true;
    }());
  }

  /// Forgets the sites already reported — for tests.
  @visibleForTesting
  static void debugReset() => _reported.clear();

  static void _onUntrackedRead(OutputSource<dynamic> source) {
    if (!enabled || !_building) return;
    final all = _callerFrames(StackTrace.current);
    if (all.any(_lifecycleSnapshot.hasMatch)) return;
    final frames = all.take(3).toList();
    if (!_reported.add(frames.join('\n'))) return;
    debugPrint(
      'BoxReadCheck: ${source.runtimeType} read during build outside any '
      'BoxObserver — this widget shows a snapshot and will not rebuild when '
      'the box changes.\n'
      'Read it inside a BoxObserver builder (a LayoutBuilder/itemBuilder '
      'callback inside one runs later and needs its own), or mark a '
      'deliberate snapshot with BoxHooks.untracked(() => ...).\n'
      'Read at:\n${frames.map((f) => '  $f').join('\n')}',
    );
  }

  static bool get _building {
    try {
      return WidgetsBinding.instance.buildOwner?.debugBuilding ?? false;
    } catch (_) {
      return false; // no binding — nothing is building
    }
  }

  /// A frame of `State.initState` / `didChangeDependencies` (or a closure
  /// inside one): the read takes an initial value, once.
  static final RegExp _lifecycleSnapshot =
      RegExp(r'\.(initState|didChangeDependencies)(\.|\s|$)');

  /// The frames outside blackbox, Flutter and the SDK, innermost first: the
  /// box's own getter (if it has one) and the widget code that called it.
  static List<String> _callerFrames(StackTrace trace) {
    const skip = [
      'package:blackbox/',
      'package:blackbox_flutter/',
      'package:blackbox_support/',
      'package:flutter/',
      'dart:',
    ];
    final frames = <String>[];
    for (final line in trace.toString().split('\n')) {
      final open = line.indexOf('(');
      final close = line.lastIndexOf(')');
      if (open < 0 || close <= open) continue;
      final location = line.substring(open + 1, close);
      if (skip.any(location.startsWith)) continue;
      final member =
          line.substring(0, open).replaceFirst(RegExp(r'^#\d+\s+'), '').trim();
      frames.add('$member ($location)');
    }
    return frames;
  }
}
