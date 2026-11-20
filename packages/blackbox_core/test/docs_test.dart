import 'dart:io';

import 'package:test/test.dart';

/// doc/SEMANTICS.md promises: every rule links to the test that holds it.
/// This keeps the promise — a renamed or deleted test, or a rule added
/// without one, fails here.
void main() {
  final doc = File('doc/SEMANTICS.md').readAsStringSync();
  final link = RegExp(r'\[([a-z_]+_test)(?: › ([^\]]+))?\]\(([^)]+)\)');

  test('every rule row in SEMANTICS.md links to a test', () {
    final orphans = <String>[];
    var inRuleTable = false;
    for (final line in doc.split('\n')) {
      if (!line.startsWith('|')) {
        inRuleTable = false;
        continue;
      }
      if (line.startsWith('| ---')) continue;
      if (!inRuleTable && line.trim().endsWith('| test |')) {
        inRuleTable = true;
        continue;
      }
      if (inRuleTable && !link.hasMatch(line)) orphans.add(line);
    }
    expect(orphans, isEmpty, reason: 'rules without a test');
  });

  test('every test SEMANTICS.md names exists', () {
    final missing = <String>[];
    for (final m in link.allMatches(doc)) {
      final name = m.group(2);
      // Other packages' tests are not checked: the published archive of
      // this package does not contain them.
      if (!m.group(3)!.startsWith('../test/')) continue;
      final file = File('doc/${m.group(3)}');
      if (!file.existsSync()) {
        missing.add('${m.group(3)} (no such file)');
        continue;
      }
      if (name == null) continue;
      // Test names may be split across adjacent string literals.
      final source = file
          .readAsStringSync()
          .replaceAll(RegExp(r"'\s*\n\s*'"), '');
      if (!source.contains(name)) missing.add('${m.group(1)} › $name');
    }
    expect(missing, isEmpty);
  });
}
