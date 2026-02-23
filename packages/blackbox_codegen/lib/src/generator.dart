import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'package:blackbox_annotations/blackbox_annotations.dart';

/// ===========================================================
/// Small “spec-first” generator:
/// - analyze → BoxSpec
/// - render(BoxSpec) → String
/// ===========================================================

enum BoxKind {
  syncNoInput,
  syncWithInput,
  asyncNoInput,
  asyncWithInput,
}

/// -------------------------
/// ParamSpec
/// -------------------------
class ParamSpec {
  final String name;
  final String type; // base without '?'
  final bool isNullable;
  final bool isNamed;
  final bool isRequired;

  const ParamSpec({
    required this.name,
    required this.type,
    required this.isNullable,
    required this.isNamed,
    required this.isRequired,
  });

  String renderType() => isNullable ? '$type?' : type;

  String renderDeclaration() {
    final t = renderType();
    if (!isNamed) return '$t $name';
    if (isRequired) return 'required $t $name';
    return '$t $name';
  }

  String renderArgument() => isNamed ? '$name: $name' : name;

  // ✅ factories for call arguments
  factory ParamSpec.positionalArg(String name) {
    return ParamSpec(
      type: 'dynamic',
      isNullable: false,
      name: name,
      isNamed: false,
      isRequired: false,
    );
  }

  factory ParamSpec.namedArg(String name, String arg) {
    return ParamSpec(
      type: 'dynamic',
      isNullable: false,
      name: name,
      isNamed: true,
      isRequired: false,
    );
  }

  factory ParamSpec.positionalDecl(String type, String name,
      {bool nullable = false}) {
    return ParamSpec(
        type: type,
        isNullable: nullable,
        name: name,
        isNamed: false,
        isRequired: false);
  }

  factory ParamSpec.namedDecl(String type, String name,
      {bool nullable = false, bool required = false}) {
    return ParamSpec(
      type: type,
      isNullable: nullable,
      name: name,
      isNamed: true,
      isRequired: required,
    );
  }
}

/// -------------------------
/// ArgumentsRenderer
/// -------------------------

/// Renders Dart parameter/argument lists.
/// This class is intentionally **dumb**:
/// it only joins already-prepared ParamSpec objects.
///
/// ⚠️ No business logic here.
/// ⚠️ No knowledge about compute / input / previous / super.
/// ⚠️ Only syntax-level rendering.
class ArgumentsRenderer {
  /// Renders a **parameter declaration list**.
  ///
  /// Used in:
  /// - method declarations
  /// - constructors
  /// - factory constructors
  ///
  /// Examples:
  /// ---
  /// renderParameterList([
  ///   ParamSpec.positional('int', 'a'),
  ///   ParamSpec.named('String', 'b', required: true),
  /// ])
  ///
  /// → `int a, {required String b}`
  ///
  /// ---
  /// renderParameterList([
  ///   ParamSpec.named('int?', 'initialValue'),
  /// ])
  ///
  /// → `{int? initialValue}`
  static String renderParameterList(List<ParamSpec> params) {
    if (params.isEmpty) return '';

    final positional = <ParamSpec>[];
    final named = <ParamSpec>[];

    for (final p in params) {
      (p.isNamed ? named : positional).add(p);
    }

    final positionalPart =
        positional.map((p) => p.renderDeclaration()).join(', ');
    final namedPart = named.map((p) => p.renderDeclaration()).join(', ');

    if (named.isEmpty) return positionalPart;
    if (positionalPart.isEmpty) return '{$namedPart}';
    return '$positionalPart, {$namedPart}';
  }

  /// Renders an **argument list for a call expression**.
  ///
  /// Used in:
  /// - method calls
  /// - constructor calls
  /// - super(...)
  ///
  /// Examples:
  /// ---
  /// renderArgumentList([
  ///   ParamSpec.positionalArg('a'),
  ///   ParamSpec.namedArg('b', 'b'),
  /// ])
  ///
  /// → `a, b: b`
  ///
  /// ---
  /// renderArgumentList([
  ///   ParamSpec.positionalArg('input'),
  ///   ParamSpec.positionalArg('previous'),
  /// ])
  ///
  /// → `input, previous`
  static String renderArgumentList(List<ParamSpec> params) {
    if (params.isEmpty) return '';

    final positional = <ParamSpec>[];
    final named = <ParamSpec>[];

    for (final p in params) {
      (p.isNamed ? named : positional).add(p);
    }

    final positionalPart = positional.map((p) => p.renderArgument()).join(', ');
    final namedPart = named.map((p) => p.renderArgument()).join(', ');

    if (named.isEmpty) return positionalPart;
    if (positionalPart.isEmpty) return namedPart;
    return '$positionalPart, $namedPart';
  }
}

/// -------------------------
/// ComputeSpec
/// -------------------------
class ComputeSpec {
  final bool isAsync;

  final String outputType; // base without '?'
  final bool outputNullable;

  /// input:
  /// - null: no input
  /// - singleInput: single input param
  /// - wrappedInputs: many inputs (wrapped into Input class)
  final ParamSpec? singleInput;
  final List<ParamSpec>? wrappedInputs;

  /// previous всегда есть (O?)
  final ParamSpec previous;

  /// name of impl compute method
  final String implMethodName;

  const ComputeSpec({
    required this.isAsync,
    required this.outputType,
    required this.outputNullable,
    required this.singleInput,
    required this.wrappedInputs,
    required this.previous,
    required this.implMethodName,
  });

  bool get hasInput => singleInput != null || wrappedInputs != null;
  bool get inputIsWrapped => wrappedInputs != null;

  String renderOutputType({bool makeNullable = false}) =>
      makeNullable || outputNullable ? '$outputType?' : outputType;

  String renderReturnType() {
    final t = renderOutputType();
    return isAsync ? 'Future<$t>' : t;
  }

  String renderInputType(String publicName) {
    if (!hasInput) return 'void';
    if (inputIsWrapped) return '${publicName}Input';
    return singleInput!.renderType();
  }
}

/// -------------------------
/// ActionSpec
/// -------------------------
class ActionSpec {
  final String name;
  final List<ParamSpec> params;
  final bool isAsync;

  const ActionSpec({
    required this.name,
    required this.params,
    required this.isAsync,
  });
}

/// -------------------------
/// FeatureSpec
/// -------------------------
class FeatureSpec {
  final bool lazy;
  final bool persistent;
  final bool observable;

  const FeatureSpec({
    required this.lazy,
    required this.persistent,
    required this.observable,
  });
}

/// -------------------------
/// PersistentSpec
/// -------------------------
class PersistentSpec {
  final String keyFunctionRef;
  final String storeType;
  final String codecType;

  PersistentSpec({
    required this.keyFunctionRef,
    required this.storeType,
    required this.codecType,
  });
}

/// -------------------------
/// BoxSpec
/// -------------------------
class BoxSpec {
  final String implClassName; // _AuthBox
  final String publicClassName; // AuthBox
  final String generatedClassName; // _$AuthBox or _\$AuthBox, etc.

  final BoxKind kind;

  final List<ParamSpec> implConstructorParams;

  final MethodElement? initMethod;
  final ComputeSpec compute;
  final List<ActionSpec> actions;

  final FeatureSpec features;

  final PersistentSpec? persistent;

  const BoxSpec({
    required this.implClassName,
    required this.publicClassName,
    required this.generatedClassName,
    required this.kind,
    required this.implConstructorParams,
    required this.compute,
    required this.actions,
    required this.features,
    required this.initMethod,
    required this.persistent,
  });
}

/// ===========================================================
/// Generator
/// ===========================================================
class BlackboxGenerator extends GeneratorForAnnotation<BlackboxAnnotation> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@box can only be applied to classes',
        element: element,
      );
    }

    final spec = _analyze(element);

    final buffer = StringBuffer();

    // Public input wrapper (only when >1 input params)
    if (spec.compute.inputIsWrapped) {
      buffer.writeln(_renderInputClass(spec));
    }

    // Public lazy wrapper (only when @lazy)
    if (spec.features.lazy) {
      buffer.writeln(_renderLazyWrapper(spec));
    }

    // Generated box (always generated; name depends on lazy)
    buffer.writeln(_renderGeneratedBox(spec));

    return buffer.toString();
  }

  // ===========================================================
  // Analyze
  // ===========================================================

  BoxSpec _analyze(ClassElement base) {
    final implName = base.name!;
    if (!implName.startsWith('_')) {
      throw InvalidGenerationSourceError(
        '@box class must be private (start with _)',
        element: base,
      );
    }

    final publicName = implName.substring(1);

    final persistentSpec = _buildPersistentSpec(base);

    final features = FeatureSpec(
      lazy: _hasAnnotation(base, 'LazyAnnotation'),
      persistent: persistentSpec != null,
      observable: _hasAnnotation(base, 'ObservableAnnotation'),
    );

    final generatedName = features.lazy
        ? '_\$${publicName}' // private generated if lazy
        : '${publicName}'; // public generated if not lazy (you can adjust)

    final ctor = _getSingleConstructor(base);
    final ctorParams = ctor.formalParameters.map(_toParamSpec).toList();

    final computeMethod = _findCompute(base);
    final computeSpec = _analyzeCompute(computeMethod);

    final initMethod = _findInit(base);

    final kind = _computeKind(computeSpec);

    // Lazy restriction: cannot be no-input
    if (features.lazy && !computeSpec.hasInput) {
      throw InvalidGenerationSourceError(
        '@lazy can be applied only to boxes with input.',
        element: base,
      );
    }

    final actions = _findActions(base).map(_toActionSpec).toList();

    return BoxSpec(
      implClassName: implName,
      publicClassName: publicName,
      generatedClassName: generatedName,
      kind: kind,
      implConstructorParams: ctorParams,
      compute: computeSpec,
      initMethod: initMethod,
      actions: actions,
      features: features,
      persistent: persistentSpec,
    );
  }

  BoxKind _computeKind(ComputeSpec c) {
    if (!c.hasInput) {
      return c.isAsync ? BoxKind.asyncNoInput : BoxKind.syncNoInput;
    }
    return c.isAsync ? BoxKind.asyncWithInput : BoxKind.syncWithInput;
  }

  ConstructorElement _getSingleConstructor(ClassElement base) {
    final ctors = base.constructors.where((c) => !c.isFactory).toList();
    if (ctors.isEmpty) {
      throw InvalidGenerationSourceError(
        '${base.name} must have a constructor.',
        element: base,
      );
    }
    if (ctors.length != 1) {
      throw InvalidGenerationSourceError(
        '${base.name} must have exactly one constructor.',
        element: base,
      );
    }
    return ctors.single;
  }

  DartObject? _getAnnotation(Element element, String annotationName) {
    for (final m in element.metadata.annotations) {
      final value = m.computeConstantValue();
      if (value == null) continue;

      final type = value.type;
      if (type?.element?.name == annotationName) {
        return value;
      }
    }
    return null;
  }

  String _readTypeArg(DartObject annotation, String fieldName) {
    final value = annotation.getField(fieldName);
    if (value == null || value.isNull) {
      throw InvalidGenerationSourceError(
        '@persistent requires "$fieldName" argument',
      );
    }

    final type = value.toTypeValue();
    if (type == null) {
      throw InvalidGenerationSourceError(
        '"$fieldName" must be a Type',
      );
    }

    final element = type.element;
    if (element == null) {
      throw InvalidGenerationSourceError(
        '"$fieldName" must be a concrete type',
      );
    }

    // ✅ ключевая строка — БЕЗ generic
    return element.name!;
  }

  bool _hasAnnotation(Element e, String annotationName) {
    return e.metadata.annotations.any((a) {
      final v = a.computeConstantValue();
      return v?.type?.element?.name == annotationName;
    });
  }

  MethodElement? _findInit(ClassElement base) {
    final methods = base.methods
        .where((m) => _hasAnnotation(m, 'BoxInitAnnotation'))
        .toList();

    if (methods.length > 1) {
      throw InvalidGenerationSourceError(
        'At most one @boxInit method is allowed.',
        element: base,
      );
    }
    return methods.isEmpty ? null : methods.first;
  }

  MethodElement _findCompute(ClassElement base) {
    final methods = base.methods
        .where((m) => _hasAnnotation(m, 'BoxComputeAnnotation'))
        .toList();

    if (methods.length != 1) {
      throw InvalidGenerationSourceError(
        'Exactly one @boxCompute method is required.',
        element: base,
      );
    }
    return methods.first;
  }

  List<MethodElement> _findActions(ClassElement base) {
    return base.methods
        .where((m) => _hasAnnotation(m, 'BoxActionAnnotation'))
        .toList();
  }

  PersistentSpec? _buildPersistentSpec(ClassElement base) {
    final ann = _getAnnotation(base, 'persistent');
    if (ann == null) return null;

    final keyFn = ann.getField('keyBuilder')?.toFunctionValue();
    if (keyFn == null) {
      throw InvalidGenerationSourceError(
        '@persistent.key must be a function reference',
        element: base,
      );
    }

    final keyFnElement = keyFn.baseElement;
    if (!keyFnElement.isStatic) {
      throw InvalidGenerationSourceError(
        '@persistent.keyBuilder must reference a top-level or static function',
        element: base,
      );
    }

    final keyRef = keyFnElement.enclosingElement is ClassElement
        ? '${keyFnElement.enclosingElement!.name}.${keyFnElement.name}'
        : keyFnElement.name;

    final storeType = _readTypeArg(ann, 'store');
    final codecType = _readTypeArg(ann, 'codec');

    return PersistentSpec(
      keyFunctionRef: keyRef!,
      storeType: storeType,
      codecType: codecType,
    );
  }

  ParamSpec _toParamSpec(FormalParameterElement p) {
    return ParamSpec(
      name: p.name!,
      type: _displayTypeBase(p.type), // <-- ВАЖНО: без '?'
      isNullable: p.type.getDisplayString().endsWith('?'),
      isNamed: p.isNamed,
      isRequired: p.isRequiredNamed,
    );
  }

  bool _isVoidReturn(DartType type) {
    return type is VoidType;
  }

  bool _isFutureVoidReturn(DartType type) {
    if (type is! InterfaceType) return false;
    if (type.element.name != 'Future') return false;
    if (type.typeArguments.length != 1) return false;
    return type.typeArguments.first is VoidType;
  }

  ActionSpec _toActionSpec(MethodElement m) {
    final rt = m.returnType;

    final isVoid = _isVoidReturn(rt);

    final isFutureVoid = _isFutureVoidReturn(rt);

    if (!isVoid && !isFutureVoid) {
      throw InvalidGenerationSourceError(
        '@boxAction methods must return void or Future<void>.',
        element: m,
      );
    }

    return ActionSpec(
      name: m.name!,
      params: m.formalParameters.map(_toParamSpec).toList(),
      isAsync: isFutureVoid,
    );
  }

  String _displayTypeBase(DartType type) {
    // analyzer's getDisplayString() includes trailing '?' for nullable types.
    // We store base type (without '?') and apply nullability via flags.
    final s = type.getDisplayString();
    if (s.endsWith('?')) {
      return s.substring(0, s.length - 1);
    }
    return s;
  }

  String _stripTrailingNullabilitySuffix(String type) {
    // на всякий случай убираем ВСЕ хвостовые '?', чтобы никогда не получить '??'
    while (type.endsWith('?')) {
      type = type.substring(0, type.length - 1);
    }
    return type;
  }

  String _outputWrapperType(BoxKind boxKind, String renderedOutputType) {
    if (boxKind == BoxKind.asyncNoInput || boxKind == BoxKind.asyncWithInput) {
      return 'AsyncOutput<$renderedOutputType>';
    }

    return 'SyncOutput<$renderedOutputType>';
  }

  ComputeSpec _analyzeCompute(MethodElement m) {
    final returnType = m.returnType;

    final isAsync =
        returnType is InterfaceType && returnType.element.name == 'Future';

    final rawOutputType =
        isAsync ? (returnType).typeArguments.first : returnType;

    final outputTypeBase = _displayTypeBase(rawOutputType);
    final outputNullable =
        rawOutputType.nullabilitySuffix != NullabilitySuffix.none;

    final params = m.formalParameters.toList();

    // We support:
    // - no input: compute(O? previous)
    // - with input: compute(I input, O? previous)
    // - multi input: compute(A a, B b, ..., O? previous)
    //
    // "previous" is last param and must be compatible with output type base.
    if (params.isEmpty) {
      throw InvalidGenerationSourceError(
        '@boxCompute must contain at least (previous) parameter.',
        element: m,
      );
    }

    final last = params.last;
    final lastTypeBase = _displayTypeBase(last.type);
    final lastIsDynamic = last.type is DynamicType;

    if (!lastIsDynamic) {
      if (lastTypeBase != outputTypeBase) {
        // If you want strictness — keep this error.
        // It prevents ambiguous "single param = input" cases.
        throw InvalidGenerationSourceError(
          '@boxCompute last parameter must be previous of type $outputTypeBase (nullable allowed).',
          element: m,
        );
      }
    }

    final previous = ParamSpec(
      name: last.name!,
      type: outputTypeBase,
      isNullable: true,
      isNamed: false,
      isRequired: false,
    );

    final inputParams = params.take(params.length - 1).toList();

    if (inputParams.isEmpty) {
      return ComputeSpec(
        isAsync: isAsync,
        outputType: outputTypeBase,
        outputNullable: outputNullable,
        singleInput: null,
        wrappedInputs: null,
        previous: previous,
        implMethodName: m.name!,
      );
    }

    if (inputParams.length == 1) {
      return ComputeSpec(
        isAsync: isAsync,
        outputType: outputTypeBase,
        outputNullable: outputNullable,
        singleInput: _toParamSpec(inputParams.first),
        wrappedInputs: null,
        previous: previous,
        implMethodName: m.name!,
      );
    }

    return ComputeSpec(
      isAsync: isAsync,
      outputType: outputTypeBase,
      outputNullable: outputNullable,
      singleInput: null,
      wrappedInputs: inputParams.map(_toParamSpec).toList(),
      previous: previous,
      implMethodName: m.name!,
    );
  }

  // ===========================================================
  // Render
  // ===========================================================

  String _renderInputClass(BoxSpec spec) {
    final inputs = spec.compute.wrappedInputs!;
    final className = '${spec.publicClassName}Input';

    return '''
class $className {
${inputs.map((p) => '  final ${p.renderType()} ${p.name};').join('\n')}

  const $className({
${inputs.map((p) => '    required this.${p.name},').join('\n')}
  });
}
''';
  }

  String _renderBoxBaseClass(BoxSpec spec) {
    final c = spec.compute;
    final inputType = c.renderInputType(spec.publicClassName);
    final outputType = c.renderOutputType();

    switch (spec.kind) {
      case BoxKind.syncNoInput:
        return 'Box<$outputType>';
      case BoxKind.asyncNoInput:
        return 'AsyncBox<$outputType>';
      case BoxKind.syncWithInput:
        return 'BoxWithInput<$inputType, $outputType>';
      case BoxKind.asyncWithInput:
        return 'AsyncBoxWithInput<$inputType, $outputType>';
    }
  }

  String buildInitCall({
    required BoxSpec spec,
    required List<ParamSpec> computeParamSpecs,
    required String computeArgs,
  }) {
    final init = spec.initMethod;
    if (init == null) return '';

    final params = init.formalParameters;

    // 1) Количество параметров должно совпадать с compute
    if (params.length != computeParamSpecs.length) {
      throw InvalidGenerationSourceError(
        '''
@boxInit must have the same parameters as compute.

Required signature:
${init.name}(${computeParamSpecs.map((p) => p.renderDeclaration()).join(', ')})
''',
        element: init,
      );
    }

//     // 2) Типы и nullable должны совпадать
//     for (var i = 0; i < params.length; i++) {
//       final actual = params[i];
//       final expected = computeParamSpecs[i];
//       final expectedType = _stripTrailingNullabilitySuffix(expected.type);

//       final actualBase = _displayTypeBase(actual.type);
//       final actualNullable =
//           actual.type.nullabilitySuffix != NullabilitySuffix.none;

//       if (actualBase != expectedType || actualNullable != expected.isNullable) {
//         throw InvalidGenerationSourceError(
//           '''
// @boxInit parameter #$i does not match compute.

// Required:
// ${expected.renderDeclaration()} ${expectedType} ${expected.isNullable}

// Found:
// ${actualBase} ${actual.name} ${actualNullable}
// ''',
//           element: actual,
//         );
//       }
//     }

    // 3) Вызов init теми же аргументами, что и compute
    return '''
    if (!_initialized) {
      _initialized = true;
      _impl.${init.name}($computeArgs);
    }
''';
  }

  String _renderGeneratedBox(BoxSpec spec) {
    final b = StringBuffer();

    final baseClass = _renderBoxBaseClass(spec);
    final c = spec.compute;

    final inputType = c.renderInputType(spec.publicClassName);
    final outputType = c.renderOutputType();
    final outputTypeOptional = c.renderOutputType(makeNullable: true);

    // --- ctor params: implementation ctor params + input (if any)
    final ctorParams = <ParamSpec>[
      ...spec.implConstructorParams,
      if (c.hasInput)
        ParamSpec(
          name: 'input',
          type: inputType,
          isNullable: false,
          isNamed: true,
          isRequired: true,
        ),
    ];

    // factory signature (same as ctor signature)
    final factorySignature = ArgumentsRenderer.renderParameterList(ctorParams);

    // impl ctor args (only impl deps)
    final implCtorArgs =
        ArgumentsRenderer.renderArgumentList(spec.implConstructorParams);

    const initFlag = '  bool _initialized = false;';

    // ------------------------------
    // persistent/observable locals in factory
    // ------------------------------
    final factoryBody = _renderFactoryBody(
      spec: spec,
      inputType: inputType,
      outputType: outputType,
    );

    // ------------------------------
    // super(...) call (real box constructors)
    // ------------------------------
    String superCall({required bool useInitialValue}) {
      if (!c.hasInput) {
        // Box / AsyncBox
        return useInitialValue
            ? 'super(initialValue: initialValue)'
            : 'super()';
      }
      // BoxWithInput / AsyncBoxWithInput
      return useInitialValue
          ? 'super(input, initialValue: initialValue)'
          : 'super(input)';
    }

    // Generated class:
    b.writeln('class ${spec.generatedClassName} extends $baseClass {');

    // private ctor
    // We always store impl + (optional) persistent/observable in fields only if needed.
    if (spec.features.persistent) {
      b.writeln('  final Persistent<$outputTypeOptional> _persistent;');
    }
    b.writeln('  final ${spec.implClassName} _impl;');
    if (spec.initMethod != null) {
      b.writeln('  $initFlag');
    }
    b.writeln('');

    final privateConstructorParams = <ParamSpec>[
      // impl constructor deps
      ...spec.implConstructorParams,

      if (c.hasInput)
        ParamSpec.namedDecl(
          inputType,
          'input',
          required: true,
        ),

      if (spec.features.persistent)
        ParamSpec.namedDecl(
          'Persistent<$outputType>',
          'persistent',
          required: true,
        ),

      ParamSpec.namedDecl(
        _stripTrailingNullabilitySuffix(outputType),
        'initialValue',
        nullable: true,
      ),
    ];

    final privateCtorSignature =
        ArgumentsRenderer.renderParameterList(privateConstructorParams);

    // Private constructor: takes impl deps + input + initialValue (already resolved in factory)
    b.writeln('');
    b.writeln('  ${spec.generatedClassName}._($privateCtorSignature) :');
    b.writeln('    _impl = ${spec.implClassName}($implCtorArgs),');

    if (spec.features.persistent) {
      b.writeln('    _persistent = persistent,');
    }

    b.writeln('    ${superCall(useInitialValue: true)} {');

    // attach order: persistent then observable
    if (spec.features.persistent) {
      b.writeln('    _persistent.attach(this);');
    }
    b.writeln('  }');
    b.writeln('');

    // Factory
    b.writeln('  factory ${spec.generatedClassName}($factorySignature) {');
    b.writeln(factoryBody);
    b.writeln('  }');
    b.writeln('');

    // compute override signature:
    // - no input: compute(O? previous)
    // - with input: compute(I input, O? previous)
    final computeParamSpecs = <ParamSpec>[
      if (c.hasInput)
        ParamSpec.positionalDecl(
          inputType,
          'input',
          nullable: false,
        ),
      ParamSpec.positionalDecl(
        _stripTrailingNullabilitySuffix(outputType),
        'previousOutputValue',
        nullable: true,
      ),
    ];

    final computeParams =
        ArgumentsRenderer.renderParameterList(computeParamSpecs);

    final computeArgSpecs = <ParamSpec>[
      if (c.hasInput && c.inputIsWrapped)
        ...c.wrappedInputs!.map(
          (p) => ParamSpec.positionalArg('input.${p.name}'),
        ),
      if (c.hasInput && !c.inputIsWrapped) ParamSpec.positionalArg('input'),
      ParamSpec.positionalArg('previousOutputValue'),
    ];

    final computeArgs = ArgumentsRenderer.renderArgumentList(computeArgSpecs);

    b.writeln('''
  @override
  @protected
  @visibleForOverriding
  ${c.renderReturnType()} compute($computeParams) {
${buildInitCall(
      spec: spec,
      computeParamSpecs: computeParamSpecs,
      computeArgs: computeArgs,
    )}

    return _impl.${c.implMethodName}($computeArgs);
  }
''');
    b.writeln('');

    // action methods: call action(() => _impl.xxx(...));
    for (final a in spec.actions) {
      final params = ArgumentsRenderer.renderParameterList(a.params);
      final args = ArgumentsRenderer.renderArgumentList(a.params);

      b.writeln('''
  ${a.isAsync ? "Future<void>" : "void"} ${a.name}($params) ${a.isAsync ? "async" : ""} =>
    action(() ${a.isAsync ? "async" : ""} => _impl.${a.name}($args));
''');
    }

    if (spec.features.observable) {
      b.writeln('  @override');
      b.writeln('  ${_outputWrapperType(spec.kind, outputType)} get output {');
      b.writeln('    BoxObserver.trackBox(this);');
      b.writeln('    return super.output;');
      b.writeln('  }');
    }

    b.writeln('}');
    return b.toString();
  }

  String _renderFactoryBody({
    required BoxSpec spec,
    required String inputType,
    required String outputType,
  }) {
    final c = spec.compute;
    final lines = <String>[];

    // --- persistent
    if (spec.features.persistent) {
      lines.add(
        '    final persistent = Persistent<$outputType>('
        'key: ${spec.persistent!.keyFunctionRef}(input),'
        'store: ${spec.persistent!.storeType}(),'
        'codec: ${spec.persistent!.codecType}(),'
        ');',
      );
      lines.add('    final initialValue = persistent.load();');
    } else {
      lines.add(
          '    final ${spec.compute.renderOutputType(makeNullable: true)} initialValue = null;');
    }

    // --- build ctor argument specs
    final ctorArgs = <ParamSpec>[];

    // impl constructor deps (positional or named preserved)
    ctorArgs.addAll(spec.implConstructorParams);

    // input
    if (c.hasInput) {
      ctorArgs.add(
        ParamSpec.namedArg(
          'input',
          'input',
        ),
      );
    }

    // persistent
    if (spec.features.persistent) {
      ctorArgs.add(
        ParamSpec.namedArg(
          'persistent',
          'persistent',
        ),
      );
    }

    // initialValue (ALWAYS named)
    ctorArgs.add(
      ParamSpec.namedArg(
        'initialValue',
        'initialValue',
      ),
    );

    final ctorCallArgs = ArgumentsRenderer.renderArgumentList(ctorArgs);

    lines.add(
      '    final box = ${spec.generatedClassName}._($ctorCallArgs);',
    );

    lines.add('    return box;');

    return lines.join('\n');
  }

  String _renderLazyWrapper(BoxSpec spec) {
    final c = spec.compute;

    final inputType = c.renderInputType(spec.publicClassName);
    final outputType = c.renderOutputType();

    final buffer = StringBuffer();

    buffer.writeln(
        'class ${spec.publicClassName} extends LazyBox<$inputType, $outputType> {');
    buffer.writeln('  ${spec.publicClassName}({');

    // expose same input parameter as required named
    buffer.writeln('    required $inputType input,');
    buffer.writeln(
        '  }) : super(create: (_) => ${spec.generatedClassName}(input: input));');
    buffer.writeln('');

    // proxy actions to inner
    for (final a in spec.actions) {
      final params = ArgumentsRenderer.renderParameterList(a.params);
      final args = ArgumentsRenderer.renderArgumentList(a.params);

      buffer.writeln(
          '  ${a.isAsync ? "Future<void>" : "void"}  ${a.name}($params) {');
      // requireInner() belongs to LazyBox in твоей версии
      final call =
          '(requireInner() as ${spec.generatedClassName}).${a.name}($args)';
      buffer.writeln('    ${a.isAsync == false ? '' : 'return '}$call;');
      buffer.writeln('  }');
      buffer.writeln('');
    }

    buffer.writeln('}');
    return buffer.toString();
  }
}
