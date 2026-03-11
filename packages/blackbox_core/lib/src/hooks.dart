part of blackbox;

final Object _boxHooksKey = Object();

abstract interface class BoxHooksSink {
  void onRead(OutputSource<dynamic> source);
}

final class BoxHooks {
  static T runWith<T>(BoxHooksSink sink, T Function() body) {
    return runZoned(body, zoneValues: {_boxHooksKey: sink});
  }

  static void reportRead(OutputSource<dynamic> source) {
    final sink = Zone.current[_boxHooksKey];
    if (sink is! BoxHooksSink) return;
    sink.onRead(source);
  }
}
