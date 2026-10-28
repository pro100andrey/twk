/// The fix of `dispose_controllers`: [DisposeField].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

/// Disposes the field reported in the state's `dispose`: `_x.dispose();`
/// (`_x?.dispose();` for a nullable field) on a line of its own before
/// its `super.dispose();`; where the class has no `dispose`, an override
/// that does so and calls `super.dispose()`, before `build` (after the
/// last member where there is no `build`).
///
/// Not offered where the class's `dispose` has no `super.dispose();`
/// statement in its block (an arrow body, or the call somewhere else),
/// nor where it declares a variable of the field's name. One location at
/// a time: two fixes of one class without a `dispose` would each write
/// the override.
final class DisposeField extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  DisposeField({required super.context});

  /// What the fix is called: `Dispose of '_x' in 'dispose'`.
  static const kind = FixKind(
    'twk.fix.disposeField',
    DartFixKindPriority.standard,
    "Dispose of '{0}' in 'dispose'",
  );

  var _name = 'controller';

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [_name];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final declaration = node.thisOrAncestorOfType<VariableDeclaration>();
    final field = declaration?.declaredFragment?.element;
    final state = node.thisOrAncestorOfType<ClassDeclaration>();
    if (field is! FieldElement || state == null) {
      return;
    }
    _name = field.displayName;
    final nullable = !typeSystem.isNonNullable(field.type);
    final call = '$_name${nullable ? '?' : ''}.dispose();';
    final members = state.body.members;
    final dispose = members
        .whereType<MethodDeclaration>()
        .where((m) => m.name.lexeme == 'dispose' && !m.isStatic)
        .firstOrNull;
    final eol = utils.endOfLine;
    if (dispose != null) {
      final superCall = switch (dispose.body) {
        BlockFunctionBody(:final block) =>
          block.statements.where(_isSuperDispose).firstOrNull,
        _ => null,
      };
      if (superCall == null || _declares(dispose, _name)) {
        return;
      }
      final prefix = utils.getLinePrefix(superCall.offset);
      await builder.addDartFileEdit(file, (builder) {
        builder.addSimpleInsertion(superCall.offset, '$call$eol$prefix');
      });
      return;
    }
    final build = members
        .whereType<MethodDeclaration>()
        .where((m) => m.name.lexeme == 'build' && !m.isStatic)
        .firstOrNull;
    final last = members.lastOrNull;
    if (last == null) {
      return;
    }
    final prefix = utils.getLinePrefix((build ?? last).offset);
    final override = [
      '@override',
      'void dispose() {',
      '${utils.oneIndent}$call',
      '${utils.oneIndent}super.dispose();',
      '}',
    ].join('$eol$prefix');
    await builder.addDartFileEdit(file, (builder) {
      if (build != null) {
        builder.addSimpleInsertion(build.offset, '$override$eol$eol$prefix');
      } else {
        builder.addSimpleInsertion(last.end, '$eol$eol$prefix$override');
      }
    });
  }

  /// Whether [statement] is `super.dispose();`.
  bool _isSuperDispose(Statement statement) => switch (statement) {
    ExpressionStatement(
      expression: MethodInvocation(
        target: SuperExpression(),
        methodName: SimpleIdentifier(name: 'dispose'),
      ),
    ) =>
      true,
    _ => false,
  };

  /// Whether [method] declares a parameter or a variable named [name],
  /// which would hide the field.
  bool _declares(MethodDeclaration method, String name) {
    var found = false;
    method.accept(_Declares(name, () => found = true));
    return found;
  }
}

final class _Declares extends RecursiveAstVisitor<void> {
  _Declares(this.name, this.found);

  final String name;
  final void Function() found;

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) {
      found();
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    if (node.parameters.any((p) => p.name?.lexeme == name)) {
      found();
    }
    super.visitFormalParameterList(node);
  }
}
