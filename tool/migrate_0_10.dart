// Rewrites blackbox 0.9 `compute` signatures to the 0.10 form in the
// current directory's lib/ and test/ (recursively):
//
//   compute(I input, O? previous)  ->  compute(I input)
//   compute(O? previous)           ->  compute()
//   compute(input, _)              ->  compute(input)
//
// Battle-tested on this repository's own migration (4 packages, 2 example
// apps). Bodies that still *use* `previous` are not touched — they are
// listed at the end for a human decision (usually: move that memory into
// a `state(...)` cell or a private field).
//
// Usage, from the root of the project to migrate:
//
//   dart run <path-to-blackbox>/tool/migrate_0_10.dart
//
// The script only edits files it can fix mechanically; run your tests
// afterwards — everything left over fails at compile time by design.
import 'dart:io';

final _patterns = <(RegExp, String Function(Match))>[
  // compute(int input, int? previous) / compute(I input, covariant ... previous)
  (
    RegExp(r'compute\(([^()]*?),\s*[\w<>?,() ]+\?\s+previous\)'),
    (m) => 'compute(${m[1]})',
  ),
  // compute(int? previous) — no-input boxes, typed
  (
    RegExp(r'compute\((?:[\w<>?,() ]+\?\s+)?previous\)'),
    (m) => 'compute()',
  ),
  // compute(input, previous) — untyped second param
  (
    RegExp(r'compute\(([^()]*?),\s*previous\)'),
    (m) => 'compute(${m[1]})',
  ),
  // compute(input, _) — ignored second param
  (
    RegExp(r'compute\(([^()]*?),\s*_\)'),
    (m) => 'compute(${m[1]})',
  ),
  // multibox: compute(void input, void previous)
  (
    RegExp(r'compute\(void input, void previous\)'),
    (m) => 'compute(void input)',
  ),
];

void main() {
  final changed = <String>[];
  final review = <String>[];

  for (final root in ['lib', 'test']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final before = entity.readAsStringSync();
      var after = before;
      for (final (pattern, replace) in _patterns) {
        after = after.replaceAllMapped(pattern, replace);
      }
      if (after != before) {
        entity.writeAsStringSync(after);
        changed.add(entity.path);
      }
      // Bodies still referring to `previous` need a human: that memory
      // belongs in a state(...) cell or a private field now.
      if (RegExp(r'\bprevious\b').hasMatch(after)) {
        final lines = after.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'\bprevious\b').hasMatch(lines[i]) &&
              // effects legitimately keep (current, previous)
              !lines[i].contains('run:') &&
              !lines[i].contains('previousData')) {
            review.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
  }

  stdout.writeln(changed.isEmpty
      ? 'No signatures needed rewriting.'
      : 'Rewrote ${changed.length} file(s):\n  ${changed.join('\n  ')}');
  if (review.isNotEmpty) {
    stdout.writeln('\nStill mentioning `previous` — needs a human look\n'
        '(move that memory into a state(...) cell or a private field;\n'
        'effects\' run(current, previous) is fine and stays):\n'
        '  ${review.join('\n  ')}');
  }
  stdout.writeln('\nNow compile: everything left over fails loudly by design.');
}
