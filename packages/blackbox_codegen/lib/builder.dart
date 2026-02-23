import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator.dart';

Builder blackboxBuilder(BuilderOptions options) =>
    PartBuilder([BlackboxGenerator()], '.box.g.dart');
