/// The wraps in a builder, on [WrapAssist]: [WrapWithBuilder] and
/// [WrapWithValueListenableBuilder], the widget at the cursor becoming
/// what the builder returns.
library;

import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';

import '../twk_types.dart';
import 'wrap.dart';

/// Wraps the widget at the cursor in a builder: what the builder returns,
/// its parameters named [parameters] (a number after a name the widget
/// reads from around it; `context` kept where what it reads is a
/// `BuildContext`, which the builder's then is). Not offered in a
/// constant context, which a function may not be in.
abstract base class _WrapInBuilder extends WrapAssist {
  _WrapInBuilder({required super.context});

  /// The names of the builder's parameters.
  List<String> get parameters;

  @override
  bool get takesNonNullable => true;

  @override
  bool offeredFor(Expression widget) => !widget.inConstantContext;

  @override
  void writeChild(DartEditBuilder builder, String source, String? inner) {
    final read = <String, List<SimpleIdentifier>>{};
    widgetExpressionAt(node)?.accept(_Reads(read));
    String free(String name) {
      bool taken(String name) => switch (read[name]) {
        null => false,
        final reads when name == 'context' => reads.any(
          (r) => !isTwkSubtype(r.staticType, 'BuildContext'),
        ),
        _ => true,
      };
      var free = name;
      for (var i = 2; taken(free); i++) {
        free = '$name$i';
      }
      return free;
    }

    builder
      ..write('builder: (')
      ..write(parameters.map(free).join(', '))
      ..write(') => ')
      ..write(source);
  }
}

/// Keeps the identifiers it visits by name, but for those that name no
/// variable of the scope: the names of members after a `.` and of named
/// constructors (a named argument's name is a token, not an identifier).
final class _Reads extends RecursiveAstVisitor<void> {
  _Reads(this.read);

  final Map<String, List<SimpleIdentifier>> read;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    final member = switch (parent) {
      ConstructorName() => true,
      PrefixedIdentifier(:final identifier) => identical(identifier, node),
      PropertyAccess(:final propertyName) => identical(propertyName, node),
      MethodInvocation(:final target?, :final methodName) =>
        target != node && identical(methodName, node),
      _ => false,
    };
    if (!member) {
      (read[node.name] ??= []).add(node);
    }
  }
}

/// Wraps the widget at the cursor in a `Builder`, which gives it a
/// context of its own.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// Builder(builder: (context) => Text('hi'))
/// ```
final class WrapWithBuilder extends _WrapInBuilder {
  /// The assist for the request [context] describes.
  WrapWithBuilder({required super.context});

  /// The assist as the editor lists it: "Wrap with Builder".
  static const kind = AssistKind(
    'twk.assist.wrapWithBuilder',
    DartFixKindPriority.standard,
    'Wrap with Builder',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  List<String> get parameters => const ['context'];

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'Builder');
  }
}

/// Wraps the widget at the cursor in a `ValueListenableBuilder`, which
/// builds it again whenever what it listens to notifies; what it listens
/// to, `valueListenable`, is selected to be named.
///
/// `Text('hi')` at the cursor becomes:
///
/// ```dart-nocheck
/// ValueListenableBuilder(
///   valueListenable: valueListenable,
///   builder: (context, value, child) => Text('hi'),
/// )
/// ```
final class WrapWithValueListenableBuilder extends _WrapInBuilder {
  /// The assist for the request [context] describes.
  WrapWithValueListenableBuilder({required super.context});

  /// The assist as the editor lists it: "Wrap with ValueListenableBuilder".
  static const kind = AssistKind(
    'twk.assist.wrapWithValueListenableBuilder',
    DartFixKindPriority.standard,
    'Wrap with ValueListenableBuilder',
  );

  @override
  AssistKind get assistKind => kind;

  @override
  bool get hasArguments => true;

  @override
  List<String> get parameters => const ['context', 'value', 'child'];

  @override
  void writeName(DartEditBuilder builder) {
    builder.writeImportedName([twkLibrary], 'ValueListenableBuilder');
  }

  @override
  void writeArguments(DartEditBuilder builder, String next) {
    builder
      ..write('valueListenable: ')
      ..addLinkedEdit(
        'VALUE_LISTENABLE',
        (builder) => builder.write('valueListenable'),
      )
      ..write(',')
      ..write(next);
  }
}
