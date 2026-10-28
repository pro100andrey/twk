/// The assist that turns a `StatefulWidget` whose `State` keeps nothing
/// into a `StatelessWidget`: [ConvertToStatelessWidget].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'convert_to_stateful_widget.dart'
    show WriteOrReadElement, classHeadAt, hasTarget;
import 'wrap.dart' show twkLibrary;

/// Turns the `StatefulWidget` whose declaration the cursor is in the head
/// of into a `StatelessWidget`, the reverse of Convert to StatefulWidget:
/// the members of its `State` (`build` among them) take the place of
/// `createState`, where they read the widget's members without `widget.`,
/// and the `State` is deleted.
///
/// Offered only where nothing changes but the shape: the `State` is the
/// private class of the same file that `createState` creates, with no
/// arguments, and that nothing else names; it extends twk's `State`
/// directly, with the widget's type parameters, mixes nothing in and
/// implements nothing; it has no constructor, no field that is not
/// `final` or is `late` (and no instance field at all where the widget
/// has a `const` constructor), overrides nothing of `State` but `build`
/// (`initState`, `dispose`, `didUpdateWidget`, ... ), reads nothing of it
/// but `widget` (`setState`, `mounted`, `context`, ...), and uses `super`
/// nowhere and `this` only to read its own members; and no name it
/// declares or reads is one the widget has, or reads, for another thing.
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
///
/// becomes:
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
final class ConvertToStatelessWidget extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  ConvertToStatelessWidget({required super.context});

  /// The assist as the editor lists it: "Convert to StatelessWidget".
  static const kind = AssistKind(
    'twk.assist.convertToStatelessWidget',
    DartFixKindPriority.standard,
    'Convert to StatelessWidget',
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
    final widget = declaration == null ? null : classElementOf(declaration);
    if (declaration == null ||
        superclass == null ||
        body is! BlockClassBody ||
        widget == null ||
        !isTwkClass(superclass.element, 'StatefulWidget')) {
      return;
    }
    final createState = body.members
        .whereType<MethodDeclaration>()
        .where((m) => m.name.lexeme == 'createState' && !m.isStatic)
        .firstOrNull;
    final creation = switch (createState?.body) {
      ExpressionFunctionBody(:final InstanceCreationExpression expression) =>
        expression,
      BlockFunctionBody(
        block: Block(
          statements: [
            ReturnStatement(:final InstanceCreationExpression expression),
          ],
        ),
      ) =>
        expression,
      _ => null,
    };
    final state = creation?.constructorName.element?.enclosingElement;
    if (createState == null || creation == null || state == null) {
      return;
    }
    final stateDeclaration = unit.declarations
        .whereType<ClassDeclaration>()
        .where((d) => classElementOf(d) == state)
        .firstOrNull;
    final stateBody = stateDeclaration?.body;
    if (stateDeclaration == null ||
        stateBody is! BlockClassBody ||
        !_isPlainState(stateDeclaration, declaration) ||
        _references(state) != 1) {
      return;
    }
    final members = stateBody.members;
    final stateApi = _memberNames(
      stateDeclaration.extendsClause!.superclass.element! as InterfaceElement,
    );
    if (!_keepsNothing(members, declaration, stateApi)) {
      return;
    }
    final moved = {
      for (final m in members) ..._declaredNames(m),
    };
    final kept = {
      for (final m in body.members)
        if (!identical(m, createState)) ..._declaredNames(m),
      ..._memberNames(superclass.element! as InterfaceElement, above: true),
    };
    if (moved.any(kept.contains)) {
      return;
    }

    final edits = <(int, int, String)>[];
    for (final m in members) {
      final reads = _StateReads(
        state,
        widget,
        kept,
        _localNames(m),
        unitResult.content,
        edits,
      );
      m.accept(reads);
      if (reads.refused) {
        return;
      }
    }
    final widgetReads = _ShadowedReads(moved);
    for (final m in body.members) {
      if (!identical(m, createState)) {
        m.accept(widgetReads);
      }
    }
    if (widgetReads.shadowed) {
      return;
    }

    final start =
        (members.first.beginToken.precedingComments ?? members.first.beginToken)
            .offset;
    var text = utils.getText(start, members.last.end - start);
    edits.sort((a, b) => b.$1.compareTo(a.$1));
    for (final (offset, length, replacement) in edits) {
      text = text.replaceRange(
        offset - start,
        offset - start + length,
        replacement,
      );
    }
    final previous = [
      ...unit.directives,
      ...unit.declarations,
    ].where((n) => n.end <= stateDeclaration.offset).lastOrNull;

    await builder.addDartFileEdit(file, (builder) {
      builder
        ..addReplacement(range.node(superclass), (builder) {
          builder.writeImportedName([twkLibrary], 'StatelessWidget');
        })
        ..addSimpleReplacement(range.node(createState), text)
        ..addDeletion(
          previous != null
              ? range.endEnd(previous, stateDeclaration)
              // first in a file of no directive: the widget is after it
              : range.startStart(stateDeclaration, declaration),
        );
    });
  }

  /// Whether [state] is a private class that extends twk's `State`, with
  /// the type parameters of [widget], and is nothing more.
  bool _isPlainState(ClassDeclaration state, ClassDeclaration widget) =>
      state.namePart.typeName.lexeme.startsWith('_') &&
      state.withClause == null &&
      state.implementsClause == null &&
      isTwkClass(state.extendsClause?.superclass.element, 'State') &&
      state.namePart.typeParameters?.toSource() ==
          widget.namePart.typeParameters?.toSource();

  /// How many times the units of the library name [state]: once where
  /// `createState` creates it and nothing else does, as no constructor of
  /// it does (whose name names it too).
  int _references(Element state) {
    final counter = _References(state);
    for (final u in libraryResult.units) {
      u.unit.accept(counter);
    }
    return counter.count;
  }

  /// Whether the `State` [members] keep nothing a widget cannot: no field
  /// but a `final` one (none where [widget] has a `const` constructor),
  /// no member named as one of `State`'s, [stateApi], but `build`.
  bool _keepsNothing(
    List<ClassMember> members,
    ClassDeclaration widget,
    Set<String> stateApi,
  ) {
    final body = widget.body;
    final constWidget =
        body is BlockClassBody &&
        body.members.whereType<ConstructorDeclaration>().any(
          (c) => c.constKeyword != null,
        );
    for (final m in members) {
      switch (m) {
        case FieldDeclaration(isStatic: false, :final fields)
            when !fields.isFinal || fields.isLate || constWidget:
          return false;
        case MethodDeclaration(isStatic: false) ||
                FieldDeclaration(isStatic: false)
            when _declaredNames(m).any(
              (n) => n != 'build' && stateApi.contains(n),
            ):
          return false;
        default:
      }
    }
    return true;
  }
}

/// The names of the members of [type] and of the classes above it but
/// `Object`; with [above], of those above it only.
Set<String> _memberNames(InterfaceElement type, {bool above = false}) => {
  for (final t in [if (!above) type.thisType, ...type.allSupertypes])
    if (!t.isDartCoreObject)
      for (final m in [
        ...t.element.methods,
        ...t.element.getters,
        ...t.element.setters,
      ])
        ?m.name,
};

/// The names [member] declares in its class.
Iterable<String> _declaredNames(ClassMember member) => switch (member) {
  MethodDeclaration(:final name) => [name.lexeme],
  FieldDeclaration(:final fields) => [
    for (final v in fields.variables) v.name.lexeme,
  ],
  ConstructorDeclaration(:final name?) => [name.lexeme],
  _ => const [],
};

/// The names declared inside [member]: its parameters, local variables,
/// local functions and type parameters, at any depth.
Set<String> _localNames(AstNode member) {
  final names = <String>{};
  member.accept(_LocalNames(names));
  return names;
}

final class _LocalNames extends GeneralizingAstVisitor<void> {
  _LocalNames(this.names);

  final Set<String> names;

  void _add(Token? name) {
    if (name != null) {
      names.add(name.lexeme);
    }
  }

  @override
  void visitFormalParameter(FormalParameter node) {
    _add(node.name);
    super.visitFormalParameter(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _add(node.name);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(node.name);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _add(node.name);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _add(node.name);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _add(node.name);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitTypeParameter(TypeParameter node) {
    _add(node.name);
    super.visitTypeParameter(node);
  }
}

/// Counts the names of [element]: as a type, a constructor's class or a
/// name read.
final class _References extends RecursiveAstVisitor<void> {
  _References(this.element);

  final Element element;
  var count = 0;

  @override
  void visitNamedType(NamedType node) {
    if (node.element == element) {
      count++;
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element) {
      count++;
    }
  }
}

/// Collects the edits that make a member of the `State` read the widget's
/// members as the widget's own: `widget.x` becomes `x` (`this.x` where a
/// local name [locals] has is `x`), `widget` alone `this`, and `W.s` of
/// a static member of the widget `s`; and finds what refuses the move —
/// [refused] — a read of the `State`'s members but `widget`, `super`,
/// `this` but to read the `State`'s own members, and a name from outside
/// that a name of the widget, [widgetNames], would hide.
final class _StateReads extends RecursiveAstVisitor<void> {
  _StateReads(
    this.state,
    this.widget,
    this.widgetNames,
    this.locals,
    this.source,
    this.edits,
  );

  final Element state;
  final InterfaceElement widget;
  final Set<String> widgetNames;
  final Set<String> locals;
  final String source;
  final List<(int, int, String)> edits;
  var refused = false;

  @override
  void visitSuperExpression(SuperExpression node) {
    refused = true;
  }

  @override
  void visitThisExpression(ThisExpression node) {
    final member = switch (node.parent) {
      PropertyAccess(:final propertyName, :final target)
          when identical(target, node) =>
        propertyName.writeOrReadElement,
      MethodInvocation(:final methodName, :final target)
          when identical(target, node) =>
        methodName.element,
      _ => null,
    };
    if (member?.enclosingElement != state) {
      refused = true;
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.writeOrReadElement;
    if (element == null || node.inDeclarationContext() || hasTarget(node)) {
      return;
    }
    final enclosing = element.enclosingElement;
    if (enclosing is InterfaceElement && isTwkClass(enclosing, 'State')) {
      if (element.name == 'widget') {
        _unqualify(node, 'this');
      } else {
        refused = true;
      }
      return;
    }
    if (enclosing is LibraryElement && widgetNames.contains(node.name)) {
      refused = true;
    }
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final element = node.identifier.writeOrReadElement;
    if (node.prefix.element == widget &&
        element != null &&
        element.enclosingElement == widget) {
      _unqualify(node.prefix, widget.displayName);
      return;
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    if (target is SimpleIdentifier &&
        target.element == widget &&
        node.methodName.element?.enclosingElement == widget) {
      _unqualify(target, widget.displayName);
      node.argumentList.accept(this);
      node.typeArguments?.accept(this);
      return;
    }
    super.visitMethodInvocation(node);
  }

  /// The edit that drops the qualifier [node] (`widget` or the widget's
  /// name) before a member of the widget, or, where [node] qualifies
  /// nothing, puts [alone] in its place.
  void _unqualify(SimpleIdentifier node, String alone) {
    final (member, dot, qualified) = switch (node.parent) {
      PrefixedIdentifier(:final prefix, :final identifier, :final period) &&
              final p
          when identical(prefix, node) =>
        (identifier.name, period, p as AstNode),
      MethodInvocation(:final target, :final methodName, :final operator?)
          when identical(target, node) && operator.lexeme == '.' =>
        (methodName.name, operator, null),
      _ => (null, null, null),
    };
    if (member == null || dot == null) {
      edits.add((node.offset, node.length, alone));
      return;
    }
    if (locals.contains(member)) {
      edits.add((node.offset, node.length, 'this'));
      return;
    }
    final interpolation = qualified?.parent;
    if (interpolation is InterpolationExpression &&
        interpolation.rightBracket != null) {
      final end = interpolation.end;
      final after = end < source.length ? source[end] : '';
      final bare = after.isEmpty || !_identifierPart.hasMatch(after);
      edits.add((
        interpolation.offset,
        interpolation.length,
        bare ? '\$$member' : '\${$member}',
      ));
      return;
    }
    edits.add((node.offset, dot.end - node.offset, ''));
  }
}

/// Finds whether a member of the widget reads, without a qualifier, a
/// name from outside the class that a member moved in, of [moved], would
/// hide: [shadowed].
final class _ShadowedReads extends RecursiveAstVisitor<void> {
  _ShadowedReads(this.moved);

  final Set<String> moved;
  var shadowed = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.writeOrReadElement;
    if (element != null &&
        element.enclosingElement is LibraryElement &&
        moved.contains(node.name) &&
        !node.inDeclarationContext() &&
        !hasTarget(node)) {
      shadowed = true;
    }
  }
}

/// A character that may follow an identifier's last in a name.
final _identifierPart = RegExp('[A-Za-z0-9_]');
