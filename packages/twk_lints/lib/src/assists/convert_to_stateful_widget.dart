/// The assist that turns a `StatelessWidget` into a `StatefulWidget`:
/// [ConvertToStatefulWidget].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'names.dart';
import 'wrap.dart' show twkLibrary;

/// Turns the `StatelessWidget` whose declaration the cursor is in the
/// head of into a `StatefulWidget`: its fields and constructors stay, its
/// other instance members (`build` among them) move to a new `State`
/// class after it, `_NameState`, where they read the widget's members
/// through `widget`, and `createState` takes the place of `build`.
///
/// ```dart-nocheck
/// final class Greeting extends StatelessWidget {
///   const Greeting(this.name, {super.key});
///
///   final String name;
///
///   @override
///   Widget build(BuildContext context) => Text('Hello, $name');
/// }
/// ```
///
/// becomes:
///
/// ```dart-nocheck
/// final class Greeting extends StatefulWidget {
///   const Greeting(this.name, {super.key});
///
///   final String name;
///
///   @override
///   State<Greeting> createState() => _GreetingState();
/// }
///
/// final class _GreetingState extends State<Greeting> {
///   @override
///   Widget build(BuildContext context) => Text('Hello, ${widget.name}');
/// }
/// ```
final class ConvertToStatefulWidget extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  ConvertToStatefulWidget({required super.context});

  /// The assist as the editor lists it: "Convert to StatefulWidget".
  static const kind = AssistKind(
    'twk.assist.convertToStatefulWidget',
    DartFixKindPriority.standard,
    'Convert to StatefulWidget',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final declaration = classHeadAt(node, selectionOffset, selectionEnd);
    final superclass = declaration?.extendsClause?.superclass;
    final body = declaration?.body;
    final element = declaration == null ? null : classElementOf(declaration);
    if (declaration == null ||
        superclass == null ||
        body is! BlockClassBody ||
        element == null ||
        !isTwkClass(superclass.element, 'StatelessWidget')) {
      return;
    }
    final members = body.members;
    final moved = [
      for (final m in members)
        if (m is MethodDeclaration && !m.isStatic) m,
    ];
    final build = moved
        .where((m) => m.name.lexeme == 'build' && !m.isGetter && !m.isSetter)
        .firstOrNull;
    if (build == null) {
      return;
    }
    final movedElements = {
      for (final m in moved) ?m.declaredFragment?.element,
    };

    final name = declaration.namePart.typeName.lexeme;
    final typeParameters = declaration.namePart.typeParameters;
    final typeNames = [
      for (final p in typeParameters?.typeParameters ?? const <TypeParameter>[])
        p.name.lexeme,
    ];
    final typeArguments = typeNames.isEmpty ? '' : '<${typeNames.join(', ')}>';
    final widgetType = '$name$typeArguments';
    final stateName = freeName(
      unit,
      '_${name.startsWith('_') ? name.substring(1) : name}State',
    );
    final eol = utils.endOfLine;
    final indent = utils.oneIndent;

    final texts = [
      for (final m in moved) _rewritten(m, element, movedElements),
    ];
    final lastKept = members.lastIndexWhere(
      (m) => identical(m, build) || !moved.contains(m),
    );

    await builder.addDartFileEdit(file, (builder) {
      builder
        ..addReplacement(range.node(superclass), (builder) {
          builder.writeImportedName([twkLibrary], 'StatefulWidget');
        })
        ..addReplacement(range.node(build), (builder) {
          builder
            ..write('@override')
            ..write(eol)
            ..write(indent)
            ..writeImportedName([twkLibrary], 'State')
            ..write(
              '<$widgetType> createState() => $stateName$typeArguments();',
            );
        });
      for (final (i, m) in members.indexed) {
        if (i < lastKept && !identical(m, build) && moved.contains(m)) {
          builder.addDeletion(range.deletionRange(m));
        }
      }
      if (lastKept < members.length - 1) {
        builder.addDeletion(range.endEnd(members[lastKept], members.last));
      }
      builder.addInsertion(declaration.end, (builder) {
        builder
          ..write(eol)
          ..write(eol);
        if (declaration.finalKeyword != null) {
          builder.write('final ');
        }
        builder
          ..write(
            'class $stateName${typeParameters?.toSource() ?? ''} extends ',
          )
          ..writeImportedName([twkLibrary], 'State')
          ..write('<$widgetType> {')
          ..write(eol);
        for (final (i, text) in texts.indexed) {
          if (i > 0) {
            builder.write(eol);
          }
          builder
            ..write(indent)
            ..write(text)
            ..write(eol);
        }
        builder.write('}');
      });
    });
  }

  /// The source of [member] (and the comments before it), reading the
  /// members of [widget] it does not move through `widget`.
  String _rewritten(
    MethodDeclaration member,
    InterfaceElement widget,
    Set<Element> moved,
  ) {
    final start =
        (member.beginToken.precedingComments ?? member.beginToken).offset;
    final edits = <(int, int, String)>[];
    member.accept(_WidgetReads(widget, moved, edits));
    var text = utils.getText(start, member.end - start);
    edits.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (offset, length, replacement) in edits) {
      text = text.replaceRange(
        offset - start,
        offset - start + length,
        replacement,
      );
    }
    return text;
  }
}

/// The class declaration whose head (up to its `{`) [node] is in, the
/// selection from [selectionOffset] to [selectionEnd] with it.
ClassDeclaration? classHeadAt(
  AstNode node,
  int selectionOffset,
  int selectionEnd,
) {
  final declaration = node.thisOrAncestorOfType<ClassDeclaration>();
  final body = declaration?.body;
  if (declaration == null || body is! BlockClassBody) {
    return null;
  }
  final start = declaration.firstTokenAfterCommentAndMetadata.offset;
  return selectionOffset >= start && selectionEnd <= body.leftBracket.offset
      ? declaration
      : null;
}

/// Collects the edits that make a member moved to the state read the
/// widget's members through `widget`: `x` becomes `widget.x`, `this.x`
/// `widget.x` and `this` `widget`, unless `x` moves too; a static member
/// read unqualified is qualified by the widget's name.
final class _WidgetReads extends RecursiveAstVisitor<void> {
  _WidgetReads(this.widget, this.moved, this.edits);

  final InterfaceElement widget;
  final Set<Element> moved;
  final List<(int, int, String)> edits;

  bool _isWidgetMember(Element? element) {
    final enclosing = element?.enclosingElement;
    return element != null &&
        enclosing is InterfaceElement &&
        widget.thisType.asInstanceOf(enclosing) != null;
  }

  bool _isStatic(Element element) =>
      element is ExecutableElement && element.isStatic ||
      element is FieldElement && element.isStatic;

  @override
  void visitThisExpression(ThisExpression node) {
    final parent = node.parent;
    final member = switch (parent) {
      PropertyAccess(:final propertyName) => propertyName.element,
      MethodInvocation(:final methodName) => methodName.element,
      _ => null,
    };
    if (member == null || !moved.contains(member)) {
      edits.add((node.offset, node.length, 'widget'));
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.writeOrReadElement;
    if (element == null ||
        moved.contains(element) ||
        !_isWidgetMember(element) ||
        node.inDeclarationContext() ||
        hasTarget(node)) {
      return;
    }
    edits.add(
      prefixed(node, _isStatic(element) ? '${widget.displayName}.' : 'widget.'),
    );
  }
}

/// Whether [node] is the name of a member read through a target, as
/// `t.x`, or a name that reads no member: a label, a constructor's.
bool hasTarget(SimpleIdentifier node) => switch (node.parent) {
  PrefixedIdentifier(:final identifier) => identical(identifier, node),
  PropertyAccess(:final propertyName) => identical(propertyName, node),
  MethodInvocation(:final methodName, :final target) =>
    identical(methodName, node) && target != null,
  Label() || ConstructorName() => true,
  _ => false,
};

/// The element a name writes or reads.
extension WriteOrReadElement on SimpleIdentifier {
  /// The element this name writes in an assignment, else the one it reads.
  Element? get writeOrReadElement => switch (parent) {
    AssignmentExpression(:final leftHandSide, :final writeElement)
        when identical(leftHandSide, this) =>
      writeElement,
    _ => element,
  };
}
