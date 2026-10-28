/// The fix of `missing_key_in_children`: [AddValueKey].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../assists/wrap.dart' show twkLibrary;
import '../rules/missing_key_in_children.dart';

/// Gives the widget reported `key: ValueKey(item)`, `item` the variable
/// of the loop it is made in: before its first named argument, or after
/// its last argument where it has no named one; its `const` dropped.
///
/// Offered only where that variable is a key of its item: the one
/// variable of a `for`-in element of the list (not one in another loop)
/// or the one parameter of the function a spread `.map` calls, of type
/// `String`, `int` or an enum. An object of another type is equal to
/// itself alone, so that a list rebuilt of new objects would make new
/// keys; which of its fields names it (`item.id`) is the author's call.
final class AddValueKey extends ResolvedCorrectionProducer {
  /// The fix, in the [context] of a diagnostic.
  AddValueKey({required super.context});

  /// What the fix is called: `Add 'key: ValueKey(item)'`.
  static const kind = FixKind(
    'twk.fix.addValueKey',
    DartFixKindPriority.standard,
    "Add 'key: ValueKey({0})'",
  );

  /// What the fix of every such widget of a file is called.
  static const multiKind = FixKind(
    'twk.fix.addValueKey.multi',
    DartFixKindPriority.inFile,
    'Add a ValueKey of its item to each widget made for one',
  );

  var _name = 'item';

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossFiles;

  @override
  FixKind get fixKind => kind;

  @override
  FixKind get multiFixKind => multiKind;

  @override
  List<String> get fixArguments => [_name];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    // fixing a file, the server runs the fix on every diagnostic of it
    if (diagnostic?.diagnosticCode != MissingKeyInChildren.code) {
      return;
    }
    final widget = node.thisOrAncestorOfType<InstanceCreationExpression>();
    if (widget == null) {
      return;
    }
    final variable = _itemOf(widget);
    if (variable == null || !_isKeyOfItem(variable.type)) {
      return;
    }
    final keyword = widget.keyword;
    final isConst = keyword?.type == Keyword.CONST;
    if (widget.inConstantContext && !isConst) {
      return;
    }
    _name = variable.displayName;
    final arguments = widget.argumentList;
    final named = arguments.arguments.whereType<NamedArgument>().firstOrNull;
    final last = arguments.arguments.lastOrNull;
    final eol = utils.endOfLine;
    await builder.addDartFileEdit(file, (builder) {
      if (isConst) {
        builder.addDeletion(range.startStart(keyword!, keyword.next!));
      }
      void writeKey(DartEditBuilder builder) {
        builder
          ..write('key: ')
          ..writeImportedName([twkLibrary], 'ValueKey')
          ..write('($_name)');
      }

      if (named != null) {
        final ownLine =
            utils.getLineThis(named.offset) !=
            utils.getLineThis(arguments.leftParenthesis.offset);
        builder.addInsertion(named.offset, (builder) {
          writeKey(builder);
          builder.write(
            ownLine ? ',$eol${utils.getLinePrefix(named.offset)}' : ', ',
          );
        });
      } else if (last == null) {
        builder.addInsertion(arguments.leftParenthesis.end, writeKey);
      } else if (last.endToken.next case final comma?
          when comma.type == TokenType.COMMA) {
        builder.addInsertion(comma.end, (builder) {
          builder.write('$eol${utils.getLinePrefix(last.offset)}');
          writeKey(builder);
          builder.write(',');
        });
      } else {
        builder.addInsertion(last.end, (builder) {
          builder.write(', ');
          writeKey(builder);
        });
      }
    });
  }

  /// The variable of the loop [widget] is made in, as the rule finds it:
  /// through `if` elements, conditional and parenthesized expressions, to
  /// a `for`-in element of a list or the function of a spread `.map`.
  VariableElement? _itemOf(InstanceCreationExpression widget) {
    AstNode child = widget;
    for (var parent = widget.parent; parent != null; parent = parent.parent) {
      switch (parent) {
        case IfElement(:final expression) when !identical(child, expression):
        case ConditionalExpression(:final condition)
            when !identical(child, condition):
        case ParenthesizedExpression():
        case ReturnStatement():
        case Block(parent: BlockFunctionBody()):
        case BlockFunctionBody():
        case ExpressionFunctionBody():
          break;
        case ForElement(
              forLoopParts: ForEachPartsWithDeclaration(:final loopVariable),
              parent: ListLiteral(),
            )
            when identical(child, parent.body):
          return loopVariable.declaredFragment?.element;
        case FunctionExpression(
              parameters: FormalParameterList(
                parameters: [FormalParameter(:final declaredFragment?)],
              ),
              parent: ArgumentList(
                parent: MethodInvocation(
                  methodName: SimpleIdentifier(name: 'map'),
                ),
              ),
            )
            when identical(child, parent.body):
          return declaredFragment.element;
        default:
          return null;
      }
      child = parent;
    }
    return null;
  }

  /// Whether a value of [type] names its item: a `String`, an `int` or an
  /// enum's, not null.
  bool _isKeyOfItem(DartType type) =>
      typeSystem.isNonNullable(type) &&
      type is InterfaceType &&
      (type.isDartCoreString ||
          type.isDartCoreInt ||
          type.element is EnumElement);
}
