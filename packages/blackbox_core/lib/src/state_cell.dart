part of blackbox;

/// EXPERIMENTAL — the declared memory of a box.
///
/// A cell is what a box *remembers* (see docs/MODEL.md): the third thing
/// next to input and output. Declare cells as `late final` fields via
/// `state(...)`:
///
/// ```dart
/// class CounterBox extends Box<int, int> {
///   late final count = state(0);
///
///   @override
///   int compute(int step, int? previous) => count.value;
///
///   void inc() => count.value += input;
/// }
/// ```
///
/// Contract:
/// - Only the owning box writes to its cells; from outside the box only
///   the output is visible.
/// - A write is an assignment (`cell.value = next` or [update]); writing
///   an equal (`==`) value is a no-op. In-place mutation is invisible —
///   assign a new instance: `items.value = [...items.value, item]`.
/// - Every effective write re-runs compute and emits the new output.
///   Multiple writes in one gesture can be batched with `action(() {..})`
///   — one compute, one emission at the end.
/// - `persist:` binds the cell to a storage slot: it restores itself on
///   creation (the disk value wins, `initial` is the first-boot
///   fallback) and saves itself on every write.
/// - `persistFor:` builds the slot key from the box input. When an input
///   change changes the key, the cell **re-slots**: it reloads
///   `cached ?? initial` from the new slot before compute runs — one
///   compute, one emission, and the previous slot's value cannot leak.
final class StateCell<T> {
  final _SyncBoxBase<dynamic, dynamic> _owner;
  final T _initial;
  final PersistentCodec<T>? _codec;

  String? _slotKey;
  _ResolvedPersistence<T>? _slot;
  T _value;

  StateCell._(
    this._owner,
    T initial, {
    String? persistKey,
    PersistentCodec<T>? codec,
  })  : _initial = initial,
        _codec = codec,
        _value = initial {
    if (persistKey != null) _bindSlot(persistKey);
  }

  /// Current remembered value.
  T get value => _value;

  set value(T next) {
    if (next == _value) return;
    _value = next;
    _slot?.save(next);
    _owner._onCellWrite();
  }

  /// Functional update: `count.update((v) => v + 1)`.
  void update(T Function(T value) f) => value = f(_value);

  void _bindSlot(String key) {
    _slotKey = key;
    final slot = BlackboxPersistence._resolve<T>(key, codec: _codec);
    _slot = slot;
    _value = slot.cached ?? _initial;
  }

  /// Re-slot on input change (persistFor). Emits nothing — the compute
  /// that follows the input change publishes the new output.
  void _reslotIfChanged(String key) {
    if (key == _slotKey) return;
    _bindSlot(key);
  }

  @override
  String toString() => 'StateCell<$T>($_value)';
}
