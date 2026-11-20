part of blackbox;

// Debug-only facts about links that are not wires, for tools (the map in
// package:blackbox/map.dart) and console warnings. Release builds skip
// all of it: every entry point is behind an assert.
//
// One rule: inside a box's compute (or a cached fetch), touching another
// box — reading it or pressing its buttons — is a hidden link. Not
// another box: the box itself and its own cells. Not a touch: a read
// inside BoxHooks.untracked, the documented "I mean a snapshot".
//
// Two zone values carry "who is doing this" into timers and past awaits:
// - _pressKey: the effect whose `run` is executing — a button pressed
//   from there is that effect pressing it (the legal ring, `⇒`);
// - _computeKey: the box whose `compute` is executing — a foreign box
//   touched from there is a hidden link (`⚠`).
// The pump itself always runs in a clean zone, so work the graph does is
// never attributed to whoever happened to schedule it.

final Object _pressKey = Object();
final Object _computeKey = Object();

bool get _tracking {
  var on = false;
  assert(() {
    on = true;
    return true;
  }());
  return on;
}

/// Runs [body] with [value] as the zone's [key] — in debug builds only.
R _withLink<R>(Object key, Object value, R Function() body) =>
    _tracking ? runZoned(body, zoneValues: {key: value}) : body();

/// Runs [body] with no effect and no box in the zone — the pump's zone.
R _cleanLinks<R>(R Function() body) => _tracking
    ? runZoned(body, zoneValues: {_pressKey: null, _computeKey: null})
    : body();

/// A button of [box] was pressed (a cell write — equal or not —,
/// `action`, `refresh`, a multibox `dispatch`).
void _notePress(Object box) {
  assert(() {
    final effect = Zone.current[_pressKey];
    if (effect is _Effect) effect._presses.add(box);
    return true;
  }());
  _noteTouch(box);
}

/// Boxes (or cells) each box touched inside its own compute.
final Expando<Set<Object>> _hiddenTouchesOf = Expando('blackbox touches');

/// [touched] was read or pressed. If a box's compute did it and it is not
/// that box's own, record a hidden link and warn — once per pair of types
/// per process.
void _noteTouch(Object touched) {
  assert(() {
    final box = Zone.current[_computeKey];
    if (box == null || _isOwn(touched, box)) return true;
    final touches = _hiddenTouchesOf[box] ??= Set.identity();
    if (touches.add(touched) &&
        _warned.add('${box.runtimeType} ${_nameOf(touched)}')) {
      // ignore: avoid_print — debug-only diagnostic, assert-guarded.
      print(
        'blackbox: ${box.runtimeType} touched ${_nameOf(touched)} inside '
        'its compute — a link the graph cannot see. Need its value? Wire '
        'it into the input: (d) => (..., x: d.onlyWhenReady(box)). '
        'Commanding it? Move the command into an effect. A deliberate '
        'snapshot read goes inside BoxHooks.untracked(() => ...).',
      );
    }
    return true;
  }());
}

final Set<String> _warned = {};

bool _isOwn(Object o, Object box) =>
    identical(o, box) || (o is ChildCell && identical(o._owner, box));

String _nameOf(Object o) => o is ChildCell
    ? '${o._owner.runtimeType}.${o._name ?? '${o.runtimeType}'}'
    : '${o.runtimeType}';

/// File of the `add` / `addMultiBox` call that declared a box (debug
/// builds only) — "wired in" on the map.
final Expando<String> _wiredInOf = Expando('blackbox wired in');

void _recordWiredIn(Object box) {
  final site = _callSite();
  if (site != null) _wiredInOf[box] = site;
}

/// The first stack frame outside this library, as a file — debug builds
/// only. A file, not a line: a line number would change a committed map
/// on every unrelated edit above it.
String? _callSite() {
  String? site;
  assert(() {
    site = _firstForeignFile(StackTrace.current);
    return true;
  }());
  return site;
}

final RegExp _frameFile =
    RegExp(r'((?:package|file|org-dartlang-app):[^\s)]*?\.dart)');

String? _firstForeignFile(StackTrace trace) {
  for (final line in trace.toString().split('\n')) {
    final match = _frameFile.firstMatch(line);
    if (match == null) continue;
    final uri = match.group(1)!;
    if (uri.startsWith('package:blackbox/')) continue;
    return _projectRelative(uri);
  }
  return null;
}

/// `package:` URIs stay as they are; a file path is cut to the project
/// folder it lives in (`test/…`, `lib/…`) — machine paths never reach a
/// committed map.
String _projectRelative(String uri) {
  if (uri.startsWith('package:')) return uri;
  const roots = ['/lib/', '/test/', '/bin/', '/tool/', '/web/'];
  for (final root in roots) {
    final i = uri.lastIndexOf(root);
    if (i >= 0) return uri.substring(i + 1);
  }
  return uri.substring(uri.lastIndexOf('/') + 1);
}
