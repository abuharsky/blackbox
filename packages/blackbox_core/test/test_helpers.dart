import 'dart:async';

import 'package:blackbox/blackbox.dart';

/// Simple sync box with input that lets us observe compute invocations.
final class SpySyncInputBox extends BoxWithInput<int, int> {
  int computeCalls = 0;
  SpySyncInputBox(super.initial);

  @override
  int compute(int input) {
    computeCalls++;
    return input;
  }
}

/// Sync box without input.
final class SpySyncBox extends Box<int> {
  int computeCalls = 0;
  int _value;
  SpySyncBox(this._value);

  void setValue(int v) => signal(() => _value = v);

  @override
  int compute() {
    computeCalls++;
    return _value;
  }
}

/// Async box with input, controlled by a Completer per input.
/// Each compute call creates a new completer that tests can complete.
final class ControlledAsyncInputBox extends AsyncBoxWithInput<int, int> {
  final Map<int, Completer<int>> completers = {};
  int computeCalls = 0;

  ControlledAsyncInputBox(super.initial);

  Completer<int> completerFor(int input) =>
      completers.putIfAbsent(input, () => Completer<int>());

  @override
  Future<int> compute(int input) {
    computeCalls++;
    return completerFor(input).future;
  }
}

/// Async box without input, controlled by a single completer that can be rotated.
final class ControlledAsyncBox extends AsyncBox<int> {
  Completer<int> _c = Completer<int>();
  int computeCalls = 0;

  ControlledAsyncBox();

  Completer<int> get completer => _c;

  void rotate() => signal(() => _c = Completer<int>());

  @override
  Future<int> compute() {
    computeCalls++;
    return _c.future;
  }
}
