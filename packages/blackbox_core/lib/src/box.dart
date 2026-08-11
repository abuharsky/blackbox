part of blackbox;

/// Anything deliverable through a BoxProvider: any [OutputSource] (a box,
/// a multibox output cell) or a [MultiBox] composite. A marker interface —
/// Dart's way to say `OutputSource | MultiBox`.
abstract interface class ProvidableBox {}

/// Source of output values — used by Graph, Reaction, Provider.
abstract class OutputSource<O> implements ProvidableBox {
  Output<O> get output;
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false});
}

extension OutputSourceValueAccess<T> on OutputSource<T> {
  /// Returns the current value for ready sync/async outputs, otherwise null.
  T? get valueOrNull {
    try {
      return requireValue;
    } on StateError {
      return null;
    }
  }

  /// Returns the current value for ready sync/async outputs.
  ///
  /// Throws [StateError] if the output is not ready yet.
  T get requireValue => output.value;
}

/// Shared sync machinery — not user-facing.
abstract class _SyncBoxBase<I, O> implements OutputSource<O>, _CellOwner {
  late I _input;
  SyncData<O>? _stateBacking;
  bool _disposed = false;
  bool _initialized = false;
  bool _inAction = false;
  bool _lateMode = false;
  O? _lateInitialValue;

  SyncData<O> get _state {
    final s = _stateBacking;
    if (s == null) {
      throw StateError(
        '$runtimeType has no output yet: it was created with .late() and '
        'the graph has not delivered its first input. Pass initialValue: '
        'to have an output before the first input arrives.',
      );
    }
    return s;
  }

  set _state(SyncData<O> next) => _stateBacking = next;
  final List<void Function(SyncData<O>)> _listeners = [];
  final List<StateCell<dynamic>> _cells = [];
  List<(StateCell<dynamic>, String Function(I))>? _slottedCells;

  /// Current graph-driven input. Always reflects the latest value pushed
  /// by the graph — read it from actions instead of caching it into
  /// fields inside `compute`.
  @protected
  I get input => _input;

  /// EXPERIMENTAL — declares a cell: what this box remembers.
  /// See [StateCell] and docs/MODEL.md. Declare cells as `late final`
  /// fields:
  ///
  /// ```dart
  /// late final _count = state(0);
  /// late final _theme = state(ThemeMode.system, persist: 'theme');
  /// late final _items = state(<Item>[], persistFor: (user) => 'cart:$user');
  /// ```
  @protected
  StateCell<T> state<T>(
    T initial, {
    String? persist,
    String Function(I input)? persistFor,
    PersistentCodec<T>? codec,
  }) {
    assert(
      persist == null || persistFor == null,
      'Provide either persist or persistFor, not both.',
    );
    final key = persistFor != null ? persistFor(_input) : persist;
    final cell = StateCell<T>._(this, initial, persistKey: key, codec: codec);
    _cells.add(cell);
    if (persistFor != null) {
      (_slottedCells ??= []).add((cell, persistFor));
    }
    return cell;
  }

  /// A cell was written: republish the output. Batched inside [action].
  @override
  void _onCellWrite() {
    if (_disposed || !_initialized || _inAction) return;
    _set(_guardedCompute(_input));
  }

  bool _computing = false;

  @override
  bool get _isComputing => _computing;

  /// Runs compute with the cell-write guard up: compute must not write
  /// state (it is the only writer of output).
  O _guardedCompute(I input) {
    _computing = true;
    try {
      return _compute(input);
    } finally {
      _computing = false;
    }
  }

  void _init(I input, {O? initialValue}) {
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    // Read through _input (not the local param): hooks like
    // ValueStateBox.onFirstCompute may promote a restored value to be
    // the effective initial input.
    onFirstCompute(_input, effectiveInitial);
    _state = SyncData(_guardedCompute(_input));
    _initialized = true;
    onReady();
  }

  /// Deferred initialization: the box is created without an input; the
  /// graph delivers the first one. Until then the box has no output —
  /// unless [initialValue] is a valid `O` (including `null` for boxes
  /// with a nullable output), in which case it is published immediately.
  void _initLate({O? initialValue}) {
    _lateMode = true;
    _lateInitialValue = initialValue;
    if (initialValue is O) {
      _stateBacking = SyncData(initialValue);
    }
  }

  /// Current output value (unwrapped from SyncData).
  O get value {
    BoxHooks.reportRead(this);
    return _state.value;
  }

  @override
  SyncData<O> get output {
    BoxHooks.reportRead(this);
    return _state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    void typed(SyncData<O> state) => listener(state);
    _listeners.add(typed);
    // A .late() box without initialValue has nothing to deliver yet;
    // the first emission arrives with the first compute.
    if (!skipFirst && _stateBacking != null) typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  void _updateInput(I input) {
    if (_disposed) return;
    if (_lateMode && !_initialized) {
      // First input for a .late() box: run the deferred _init, but
      // publish through _set so listeners subscribed before the first
      // input receive the first computed output.
      _input = input;
      final effectiveInitial = resolveInitialValue(input, _lateInitialValue);
      _lateInitialValue = null;
      onFirstCompute(_input, effectiveInitial);
      final computed = _guardedCompute(_input);
      _initialized = true;
      onReady();
      _set(computed);
      return;
    }
    _input = input;
    // Re-slot persistFor cells first: cells reload from the new slot,
    // then compute runs once and publishes once.
    final slotted = _slottedCells;
    if (slotted != null) {
      for (final (cell, keyFor) in slotted) {
        cell._reslotIfChanged(keyFor(input));
      }
    }
    final previous = resolvePreviousForInput(input, _state.value);
    final early = beforeCompute(input, previous);
    _set(early ?? _guardedCompute(input));
  }

  /// Maps the effective `previous` value when a new input arrives.
  /// [Persisted] overrides this to re-initialize the box in a new
  /// persistence slot when the persist key changes.
  @protected
  O? resolvePreviousForInput(I input, O? previous) => previous;

  @protected
  O? beforeCompute(I input, O? previous) => null;

  void _set(O value) {
    // Late events (native callbacks, stream ticks) must not notify
    // listeners of a disposed box.
    if (_disposed) return;
    _state = SyncData(value);
    for (final listener in List.of(_listeners)) {
      listener(_state);
    }
  }

  /// Runs [body] and republishes the output once at the end.
  ///
  /// With cells this is an optional batching tool: writes inside [body]
  /// do not emit individually — one compute, one emission when [body]
  /// returns. For field-based boxes it remains the way to signal "my
  /// hidden state changed".
  @protected
  void action(void Function() body) {
    if (_lateMode && !_initialized) {
      throw StateError(
        '$runtimeType.action() called before the graph delivered the '
        'first input to this .late() box.',
      );
    }
    _inAction = true;
    try {
      body();
    } finally {
      _inAction = false;
    }
    _set(_guardedCompute(_input));
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) => initialValue;

  @protected
  void onReady() {}

  @protected
  void onFirstCompute(I input, O? previous) {}

  O _compute(I input);

  @protected
  void dispose() {}

  /// Idempotent dispose entry point used by Graph and MultiBox.
  /// Guarantees [dispose] runs once and no emissions happen afterwards.
  void _disposeOnce() {
    if (_disposed) return;
    _disposed = true;
    dispose();
  }
}

/// Sync box with input.
abstract class Box<I, O> extends _SyncBoxBase<I, O> {
  Box(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  /// Creates the box without an input — the graph delivers the first one.
  ///
  /// Kills the dummy-input problem: a box whose input comes from the
  /// graph should not demand a fake one at construction time.
  ///
  /// ```dart
  /// class PhaseBox extends Box<PhaseInput, AppPhase> {
  ///   PhaseBox.late() : super.late(initialValue: AppPhase.splash);
  ///   ...
  /// }
  /// ```
  ///
  /// Until the first input arrives:
  /// - with [initialValue] (or a nullable output type, where `null` is a
  ///   valid value) the box is ready and shows that value;
  /// - otherwise the box has no output — dependents wait, [value] throws
  ///   a [StateError], listeners get their first emission with the first
  ///   compute.
  ///
  /// Buttons ([action], cell writes) work after the first input.
  Box.late({O? initialValue}) {
    _initLate(initialValue: initialValue);
  }

  @override
  O _compute(I input) => compute(input);

  @protected
  O compute(I input);
}

/// Sync box without input.
abstract class NoInputBox<O> extends _SyncBoxBase<void, O> {
  NoInputBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  O _compute(void _) => compute();

  @protected
  O compute();
}

/// Shared async machinery — not user-facing.
abstract class _AsyncBoxBase<I, O> implements OutputSource<O>, _CellOwner {
  late I _input;
  AsyncOutput<O> _state = AsyncLoading();
  int _version = 0;
  bool _disposed = false;
  bool _initialized = false;
  bool _inAction = false;
  bool _lateMode = false;
  O? _lateInitialValue;
  final List<void Function(AsyncOutput<O>)> _listeners = [];
  final List<StateCell<dynamic>> _cells = [];
  List<(StateCell<dynamic>, String Function(I))>? _slottedCells;

  /// Current graph-driven input. Always reflects the latest value pushed
  /// by the graph. For [LateAsyncBox] valid only after the graph
  /// delivered the first input.
  @protected
  I get input => _input;

  /// EXPERIMENTAL — declares a cell: what this box remembers.
  /// See [StateCell] and docs/MODEL.md. Declare cells as `late final`
  /// fields:
  ///
  /// ```dart
  /// late final _query = state('');
  /// ```
  ///
  /// A write re-runs the async compute (emitting `AsyncLoading` with the
  /// previous data first, per [shouldEmitLoading]).
  @protected
  StateCell<T> state<T>(
    T initial, {
    String? persist,
    String Function(I input)? persistFor,
    PersistentCodec<T>? codec,
  }) {
    assert(
      persist == null || persistFor == null,
      'Provide either persist or persistFor, not both.',
    );
    final key = persistFor != null ? persistFor(_input) : persist;
    final cell = StateCell<T>._(this, initial, persistKey: key, codec: codec);
    _cells.add(cell);
    if (persistFor != null) {
      (_slottedCells ??= []).add((cell, persistFor));
    }
    return cell;
  }

  /// A cell was written: re-run compute. Batched inside [action].
  @override
  void _onCellWrite() {
    if (_disposed || !_initialized || _inAction) return;
    _recompute(shouldEmitLoading: shouldEmitLoading(_input, _previous));
  }

  bool _computing = false;

  @override
  bool get _isComputing => _computing;

  /// Runs compute with the cell-write guard up for its synchronous part:
  /// compute must not write state (it is the only writer of output).
  Future<O> _guardedCompute(I input) {
    _computing = true;
    try {
      return _compute(input);
    } finally {
      _computing = false;
    }
  }

  /// Cache configuration supplied by [CachedBox]/[NoInputCachedBox].
  /// Library-private on purpose: plain async boxes cannot silently turn
  /// their compute into a cached fetch — caching requires the class
  /// whose name (and `fetch` method) carries that contract.
  Cache<I, O>? get _cacheConfig => null;

  _CacheRuntime<I, O>? _cacheRt;
  bool _cacheRtResolved = false;

  _CacheRuntime<I, O>? get _cacheRuntime {
    if (!_cacheRtResolved) {
      _cacheRtResolved = true;
      final config = _cacheConfig;
      if (config != null) {
        _cacheRt = _CacheRuntime<I, O>(this, config);
      }
    }
    return _cacheRt;
  }

  void _init(I input, {O? initialValue}) {
    _input = input;
    final effectiveInitial = resolveInitialValue(input, initialValue);
    if (effectiveInitial != null) {
      _state = AsyncData(effectiveInitial);
    }
    onFirstCompute(input, _previous);
    _initialized = true;
    onReady();
    _recompute(shouldEmitLoading: shouldEmitLoading(input, _previous));
  }

  /// Deferred initialization: the box is created without an input; the
  /// graph delivers the first one. Until then the output is
  /// `AsyncLoading` (or `AsyncData(initialValue)` when provided).
  void _initLate({O? initialValue}) {
    _lateMode = true;
    _lateInitialValue = initialValue;
    if (initialValue != null) {
      _state = AsyncData(initialValue);
    }
  }

  O? get _previous => switch (_state) {
        AsyncData<O>(:final value) => value,
        AsyncLoading<O>(:final previousData) => previousData,
        AsyncError<O>(:final previousData) => previousData,
      };

  @override
  AsyncOutput<O> get output {
    BoxHooks.reportRead(this);
    _cacheRuntime?.onAccess();
    return _state;
  }

  @override
  Cancel listen(void Function(Output<O>) listener, {bool skipFirst = false}) {
    _cacheRuntime?.onAccess();
    void typed(AsyncOutput<O> s) => listener(s);
    _listeners.add(typed);
    if (!skipFirst) typed(_state);
    return _cancelGuarded(() => _listeners.remove(typed));
  }

  /// Forces a recompute. On a [CachedBox] this bypasses the TTL and
  /// re-fetches (deduplicated with any in-flight refresh); on a plain
  /// async box it simply re-runs compute.
  Future<void> refresh() {
    final rt = _cacheRuntime;
    if (rt != null) return rt.refresh();
    return action(() {});
  }

  /// Clears the cached value (and its disk slot, if any), then refreshes.
  /// Only meaningful on a [CachedBox]; otherwise same as [refresh].
  Future<void> invalidateCache() {
    final rt = _cacheRuntime;
    if (rt != null) return rt.invalidate();
    return refresh();
  }

  void _updateInput(I input) {
    if (_disposed) return;
    if (_lateMode && !_initialized) {
      // First input for a .late() box: run the deferred _init.
      final initial = _lateInitialValue;
      _lateInitialValue = null;
      _init(input, initialValue: initial);
      return;
    }
    _input = input;
    // Re-slot persistFor cells first: cells reload from the new slot,
    // then compute runs once and publishes once.
    final slotted = _slottedCells;
    if (slotted != null) {
      for (final (cell, keyFor) in slotted) {
        cell._reslotIfChanged(keyFor(input));
      }
    }
    final previous = resolvePreviousForInput(input, _previous);
    _recompute(shouldEmitLoading: shouldEmitLoading(input, previous));
  }

  /// Maps the effective `previous` value when a new input arrives.
  /// [AsyncPersisted] overrides this to re-initialize the box in a new
  /// persistence slot (severing the old slot's state) when the persist
  /// key changes. On a [CachedBox] the cache runtime does the same.
  @protected
  O? resolvePreviousForInput(I input, O? previous) {
    final rt = _cacheRuntime;
    if (rt == null) return previous;
    return rt.resolvePrevious(input, previous);
  }

  Future<void> _recompute({required bool shouldEmitLoading}) {
    final input = _input;
    final previous = _previous;
    final my = ++_version;

    final early = beforeCompute(input, previous);
    if (early != null) {
      return early.then<void>((value) {
        if (my != _version) return;
        _set(AsyncData(value));
      }).catchError((Object e, StackTrace st) {
        if (my != _version) return;
        _set(AsyncError(e, st, previousData: previous));
      });
    }

    if (shouldEmitLoading) {
      _set(AsyncLoading(previousData: previous));
    }

    return _guardedCompute(input).then<void>((value) {
      if (my != _version) return;
      _set(AsyncData(value));
    }).catchError((Object e, StackTrace st) {
      if (my != _version) return;
      _set(AsyncError(e, st, previousData: previous));
    });
  }

  void _set(AsyncOutput<O> state) {
    // Late completions must not notify listeners of a disposed box.
    if (_disposed) return;
    _state = state;
    for (final listener in List.of(_listeners)) {
      listener(_state);
    }
  }

  /// Runs [body] and re-runs compute once at the end.
  ///
  /// Cell writes in the synchronous part of [body] are batched — one
  /// recompute when it finishes. Writes after an `await` inside an async
  /// [body] trigger individually.
  @protected
  Future<void> action(FutureOr<void> Function() body) {
    if (_lateMode && !_initialized) {
      throw StateError(
        '$runtimeType.action() called before the graph delivered the '
        'first input to this .late() box.',
      );
    }
    _inAction = true;
    final FutureOr<void> result;
    try {
      result = body();
    } catch (e, st) {
      _inAction = false;
      return Future.error(e, st);
    }
    _inAction = false;
    if (result is Future) {
      return result.then<void>((_) => _recompute(
          shouldEmitLoading: shouldEmitLoading(_input, _previous)));
    }
    return _recompute(
        shouldEmitLoading: shouldEmitLoading(_input, _previous));
  }

  @protected
  O? resolveInitialValue(I input, O? initialValue) {
    final rt = _cacheRuntime;
    if (rt == null) return initialValue;
    return rt.resolveInitial(input, initialValue);
  }

  @protected
  void onReady() {
    _cacheRuntime?.onReady();
  }

  /// Return non-null Future to short-circuit compute.
  @protected
  Future<O>? beforeCompute(I input, O? previous) {
    return _cacheRuntime?.beforeCompute(input, previous);
  }

  @protected
  bool shouldEmitLoading(I input, O? previous) {
    final rt = _cacheRuntime;
    if (rt == null) return true;
    return rt.shouldEmitLoading(previous);
  }

  @protected
  void onFirstCompute(I input, O? previous) {}

  Future<O> _compute(I input);

  @protected
  void dispose() {}

  /// Idempotent dispose entry point used by Graph and MultiBox.
  /// Guarantees [dispose] runs once, invalidates in-flight computes,
  /// and no emissions happen afterwards.
  void _disposeOnce() {
    if (_disposed) return;
    _disposed = true;
    _version++;
    dispose();
  }
}

/// Async box with input.
abstract class AsyncBox<I, O> extends _AsyncBoxBase<I, O> {
  AsyncBox(I input, {O? initialValue}) {
    _init(input, initialValue: initialValue);
  }

  /// Creates the box without an input — the graph delivers the first one.
  ///
  /// Kills the dummy-input problem: a box whose input comes from the
  /// graph should not demand a fake one at construction time.
  ///
  /// Until the first input arrives the output is `AsyncLoading` (or
  /// `AsyncData(initialValue)` when provided); dependents simply wait.
  /// The first compute runs when the graph delivers the first input.
  /// Buttons ([action], cell writes) work after the first input.
  AsyncBox.late({O? initialValue}) {
    _initLate(initialValue: initialValue);
  }

  @override
  Future<O> _compute(I input) => compute(input);

  @protected
  Future<O> compute(I input);
}

/// Async box without input.
abstract class NoInputAsyncBox<O> extends _AsyncBoxBase<void, O> {
  NoInputAsyncBox({O? initialValue}) {
    _init(null, initialValue: initialValue);
  }

  @override
  Future<O> _compute(void _) => compute();

  @protected
  Future<O> compute();
}
