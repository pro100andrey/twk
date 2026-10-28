/// The assist that moves the widget at the cursor into a widget of its
/// own: [ExtractWidget].
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

import '../twk_types.dart';
import 'names.dart';
import 'wrap.dart' show twkLibrary;

/// Moves the widget the cursor is on into the `build` of a new
/// `StatelessWidget`, `NewWidget`, after the declaration it is in, and
/// puts `NewWidget(...)` in its place, the name selected in its three
/// places to be typed over in all of them at once.
///
/// What the widget reads from around it becomes a field of the new
/// widget, passed by the old place: a local variable or parameter, or a
/// field, getter or method (torn off) of the class it is in, named as it
/// is without its leading `_`s. A `BuildContext` it reads, and a `State`'s
/// `context`, become the new `build`'s `context`; a static member of the
/// class is qualified by the class's name. A widget that calls a method
/// of the class, assigns to what is around it, uses `this` or `super`,
/// awaits, or names a type parameter from around it is not extracted.
///
/// In a build that shows a name it was given, the cursor on `Text`:
///
/// ```dart-nocheck
/// Widget build(BuildContext context) =>
///     Box(child: Text('Hello, $name'));
/// ```
///
/// becomes, the new widget after the class:
///
/// ```dart-nocheck
/// Widget build(BuildContext context) => Box(child: NewWidget(name: name));
///
/// class NewWidget extends StatelessWidget {
///   const NewWidget({required this.name, super.key});
///
///   final String name;
///
///   @override
///   Widget build(BuildContext context) => Text('Hello, $name');
/// }
/// ```
final class ExtractWidget extends ResolvedCorrectionProducer {
  /// The assist for the request [context] describes.
  ExtractWidget({required super.context});

  /// The assist as the editor lists it: "Extract widget".
  static const kind = AssistKind(
    'twk.assist.extractWidget',
    DartFixKindPriority.standard,
    'Extract widget',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final widget = widgetExpressionAt(node);
    final top = widget?.thisOrAncestorOfType<CompilationUnitMember>();
    if (widget == null ||
        top == null ||
        widget is Identifier ||
        widget is PropertyAccess) {
      return;
    }
    final scan = _Reads(widget);
    widget.accept(scan);
    if (scan.unsupported) {
      return;
    }

    final name = freeName(unit, 'NewWidget');
    final eol = utils.endOfLine;
    final indent = utils.oneIndent;
    final fields = scan.fields;
    var body = utils.getNodeText(widget);
    final edits = [...scan.edits]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final (offset, length, replacement) in edits) {
      body = body.replaceRange(
        offset - widget.offset,
        offset - widget.offset + length,
        replacement,
      );
    }
    body = utils.replaceSourceIndent(
      body,
      utils.getLinePrefix(widget.offset),
      indent,
    );

    // One replacement, from the widget to the end of the declaration it is
    // in, the text between them written again as it was: the analysis
    // server sends a change of more than one edit to the editor as a plain
    // edit, its linked edit groups dropped, and the name is then left to
    // rename by hand (test/support.dart, expectSnippetShape).
    await builder.addDartFileEdit(file, (builder) {
      builder.addReplacement(
        range.startOffsetEndOffset(widget.offset, top.end),
        (builder) {
          builder
            ..addLinkedEdit('NAME', (builder) => builder.write(name))
            ..write('(')
            ..write(
              [for (final f in fields) '${f.name}: ${f.argument}'].join(', '),
            )
            ..write(')')
            ..write(
              utils.getRangeText(
                range.startOffsetEndOffset(widget.end, top.end),
              ),
            )
            ..write('$eol${eol}class ')
            ..addLinkedEdit('NAME', (builder) => builder.write(name))
            ..write(' extends ')
            ..writeImportedName([twkLibrary], 'StatelessWidget')
            ..write(' {$eol$indent')
            ..write('const ')
            ..addLinkedEdit('NAME', (builder) => builder.write(name));
          final parameters = [
            for (final f in fields) 'required this.${f.name}',
            'super.key',
          ];
          final line = '${indent}const $name({${parameters.join(', ')}});';
          if (line.length <= 80) {
            builder.write('({${parameters.join(', ')}});');
          } else {
            builder.write('({$eol');
            for (final p in parameters) {
              builder.write('$indent$indent$p,$eol');
            }
            builder.write('$indent});');
          }
          builder.write(eol);
          if (fields.isNotEmpty) {
            builder.write(eol);
            for (final f in fields) {
              builder
                ..write('${indent}final ')
                ..writeType(f.type, required: true, shouldWriteDynamic: true)
                ..write(' ${f.name};$eol');
            }
          }
          builder
            ..write('$eol$indent@override$eol$indent')
            ..writeImportedName([twkLibrary], 'Widget')
            ..write(' build(')
            ..writeImportedName([twkLibrary], 'BuildContext')
            ..write(' context) => $body;$eol}');
        },
      );
    });
  }
}

/// A field of the new widget: its name, its type, and the argument the
/// old place passes.
typedef _Field = ({String name, DartType type, String argument});

/// What a widget to extract reads from around it.
final class _Reads extends RecursiveAstVisitor<void> {
  _Reads(this.widget);

  final Expression widget;

  /// The fields of the new widget, in the order the widget reads them.
  final fields = <_Field>[];

  /// The replacements of names in the widget's source, at offsets in the
  /// file.
  final edits = <(int, int, String)>[];

  var unsupported = false;

  final _names = <Element, String>{};
  final _taken = {'key', 'context', 'build'};
  var _functions = 0;

  bool _inside(Element element) {
    final offset =
        element.firstFragment.nameOffset ?? element.firstFragment.offset;
    return offset >= widget.offset && offset < widget.end;
  }

  void _read(SimpleIdentifier node, Element element, DartType type) {
    if (_mentionsTypeParameter(type)) {
      unsupported = true;
      return;
    }
    final known = _names[element];
    final name =
        known ?? _free(node.name.replaceFirst(_leadingUnderscores, ''));
    if (known == null) {
      _names[element] = name;
      fields.add((name: name, type: type, argument: node.name));
    }
    if (name != node.name) {
      edits.add((node.offset, node.length, name));
    }
  }

  String _free(String base) {
    var name = base.isEmpty ? 'value' : base;
    for (
      var i = 2;
      _taken.contains(name) || Keyword.keywords.containsKey(name);
      i++
    ) {
      name = '$base$i';
    }
    _taken.add(name);
    return name;
  }

  void _context(SimpleIdentifier node) {
    if (node.name != 'context') {
      edits.add((node.offset, node.length, 'context'));
    }
  }

  @override
  void visitThisExpression(ThisExpression node) => unsupported = true;

  @override
  void visitSuperExpression(SuperExpression node) => unsupported = true;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    if (_functions == 0) {
      unsupported = true;
    }
    super.visitAwaitExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _functions++;
    super.visitFunctionExpression(node);
    _functions--;
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.element is TypeParameterElement && !_inside(node.element!)) {
      unsupported = true;
    }
    super.visitNamedType(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _written(node.leftHandSide, node.writeElement);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.type.isIncrementOperator) {
      _written(node.operand, node.writeElement);
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.type.isIncrementOperator) {
      _written(node.operand, node.writeElement);
    }
    super.visitPostfixExpression(node);
  }

  void _written(Expression target, Element? element) {
    if (target is SimpleIdentifier && element != null && !_inside(element)) {
      unsupported = true;
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element == null || node.inDeclarationContext() || _hasTarget(node)) {
      return;
    }
    switch (element) {
      case LocalVariableElement() || FormalParameterElement()
          when !_inside(element):
        final type = (element as VariableElement).type;
        if (isTwkClass(type.element, 'BuildContext')) {
          _context(node);
        } else {
          _read(node, element, type);
        }
      case LocalFunctionElement() when !_inside(element):
        if (_isCalled(node)) {
          unsupported = true;
        } else {
          _read(node, element, element.type);
        }
      case ExecutableElement(:final InterfaceElement enclosingElement):
        _member(node, element, enclosingElement);
      case ExecutableElement(enclosingElement: ExtensionElement())
          when !element.isStatic:
        unsupported = true;
      default:
    }
  }

  void _member(
    SimpleIdentifier node,
    ExecutableElement element,
    InterfaceElement enclosing,
  ) {
    if (element is ConstructorElement) {
      return;
    }
    if (element.isStatic) {
      edits.add(prefixed(node, '${enclosing.displayName}.'));
      return;
    }
    switch (element) {
      case GetterElement(:final returnType):
        if (element.name == 'context' && isTwkClass(enclosing, 'State')) {
          _context(node);
        } else if (isTwkClass(returnType.element, 'BuildContext')) {
          _context(node);
        } else {
          _read(node, element, returnType);
        }
      case MethodElement() when !_isCalled(node):
        _read(node, element, element.type);
      default:
        unsupported = true;
    }
  }

  static bool _isCalled(SimpleIdentifier node) =>
      node.parent is MethodInvocation &&
      identical((node.parent! as MethodInvocation).methodName, node);

  static bool _hasTarget(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final identifier) => identical(identifier, node),
    PropertyAccess(:final propertyName) => identical(propertyName, node),
    MethodInvocation(:final methodName, :final target) =>
      identical(methodName, node) &&
          (target != null || node.parent!.isCascaded),
    Label() || ConstructorName() => true,
    _ => false,
  };

  static bool _mentionsTypeParameter(DartType type) => switch (type) {
    TypeParameterType() => true,
    InterfaceType(:final typeArguments) => typeArguments.any(
      _mentionsTypeParameter,
    ),
    FunctionType(:final returnType, :final formalParameters) =>
      _mentionsTypeParameter(returnType) ||
          formalParameters.any((p) => _mentionsTypeParameter(p.type)),
    RecordType(:final positionalFields, :final namedFields) =>
      positionalFields.any((f) => _mentionsTypeParameter(f.type)) ||
          namedFields.any((f) => _mentionsTypeParameter(f.type)),
    _ => false,
  };
}

extension on AstNode {
  bool get isCascaded =>
      this is MethodInvocation && (this as MethodInvocation).isCascaded;
}

/// The underscores a private name starts with.
final _leadingUnderscores = RegExp('^_+');
