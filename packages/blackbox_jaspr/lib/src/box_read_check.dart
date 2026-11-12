part of blackbox_jaspr;

/// Debug aid: a box read while a component builds **on the client**, with
/// no [BoxObserver] tracking it.
///
/// Such a read returns the current value and subscribes nobody — the
/// component shows a snapshot and stays stale until something unrelated
/// rebuilds it. The usual shape: a nested component reads a box in its own
/// `build`, under an observer whose builder only returned it — children
/// build after the observer's builder, outside its tracking.
///
/// Wrap the client root once:
///
/// ```dart
/// BoxReadCheck(child: BoxObserver(builder: (_) => app()))
/// ```
///
/// It watches the builds of its subtree and prints one warning per
/// component and box type. Debug builds only (in release it is a plain
/// pass-through), and only on the client: the server renders once, nothing
/// there can go stale. Reads made from `initState` and
/// `didChangeDependencies` take an initial value once and stay quiet; any
/// other deliberate snapshot during build goes in
/// `BoxHooks.untracked(() => ...)`.
class BoxReadCheck extends ObserverComponent {
  const BoxReadCheck({super.key, required super.child});

  /// `false` — the check stays installed but says nothing.
  static bool enabled = true;

  static final Set<String> _reported = <String>{};

  /// Client elements in the middle of a rebuild, innermost last.
  static final List<Element> _building = <Element>[];

  /// Forgets the sites already reported — for tests.
  @visibleForTesting
  static void debugReset() => _reported.clear();

  static final RegExp _lifecycleSnapshot =
      RegExp(r'\b(initState|didChangeDependencies)\b');

  @override
  ObserverElement createElement() {
    assert(() {
      BoxHooks.onUntrackedRead ??= _onUntrackedRead;
      return true;
    }());
    return _BoxReadCheckElement(this);
  }

  static void _onUntrackedRead(OutputSource<dynamic> source) {
    if (!enabled || _building.isEmpty) return;
    if (_lifecycleSnapshot.hasMatch(StackTrace.current.toString())) return;
    final where = _building.last.component.runtimeType;
    if (!_reported.add('$where/${source.runtimeType}')) return;
    print(
      'BoxReadCheck: ${source.runtimeType} read while $where builds, '
      'outside any BoxObserver — it shows a snapshot and will not rebuild '
      'when the box changes. Read it inside a BoxObserver builder (a nested '
      'component needs its own), or mark a deliberate snapshot with '
      'BoxHooks.untracked(() => ...).',
    );
  }
}

class _BoxReadCheckElement extends ObserverElement {
  _BoxReadCheckElement(BoxReadCheck super.component);

  @override
  void willRebuildElement(Element element) {
    assert(() {
      if (element.binding.isClient) BoxReadCheck._building.add(element);
      return true;
    }());
  }

  @override
  void didRebuildElement(Element element) {
    assert(() {
      final building = BoxReadCheck._building;
      if (building.isNotEmpty && identical(building.last, element)) {
        building.removeLast();
      } else {
        building.remove(element);
      }
      return true;
    }());
  }

  @override
  void didUnmountElement(Element element) {
    assert(() {
      BoxReadCheck._building.remove(element);
      return true;
    }());
  }
}
