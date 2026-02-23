/// Annotation definitions for Blackbox code generation.
///
/// Declares markers for box classes, compute/action methods, lazy loading, and
/// optional persistence/observability features.
library blackbox_annotations;

const lazy = LazyAnnotation();
const observable = ObservableAnnotation();

const box = BlackboxAnnotation();
const boxCompute = BoxComputeAnnotation();
const boxAction = BoxActionAnnotation();
const boxInit = BoxInitAnnotation();

class persistent<T> {
  /// Must be a top-level or static function.
  /// Signature:
  ///   String Function(InputType input)
  final Function(T) keyBuilder;
  final Type store;
  final Type codec;

  const persistent({
    required this.keyBuilder,
    required this.store,
    required this.codec,
  });
}

class LazyAnnotation {
  const LazyAnnotation();
}

class ObservableAnnotation {
  const ObservableAnnotation();
}

class BlackboxAnnotation {
  const BlackboxAnnotation();
}

/// Marks a method as the compute function. Must appear exactly once on the base class.
class BoxComputeAnnotation {
  const BoxComputeAnnotation();
}

/// Marks a method as a action. Methods are executed through runtime `action(() { ... })`.
class BoxActionAnnotation {
  const BoxActionAnnotation();
}

class BoxInitAnnotation {
  const BoxInitAnnotation();
}
