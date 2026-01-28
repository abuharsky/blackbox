part of blackbox;

typedef Cancel = void Function();

Cancel _cancelGuarded(void Function() cancel) {
  var done = false;
  return () {
    if (done) return;
    done = true;
    cancel();
  };
}
