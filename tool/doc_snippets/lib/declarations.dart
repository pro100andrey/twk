/// The declarations of a Dart file, each with its qualified name, the
/// lines it spans and whether its name is public: what the coverage report
/// ties uncovered lines to, and the undocumented report names a finding by.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';

/// One declaration of a file: a type, a member of one, or a top-level
/// function or variable.
final class Declaration {
  /// The declaration [name]d, of [kind], whose name starts at [nameOffset].
  const Declaration({
    required this.name,
    required this.kind,
    required this.nameOffset,
    required this.line,
    required this.firstLine,
    required this.lastLine,
    required this.isPublic,
    required this.hasCode,
  });

  /// Its name, qualified by its type's: `Box`, `Box.child`, `Box.new`,
  /// `Box.named`, `runApp`; an unnamed extension is `extension on T`.
  final String name;

  /// What it declares: `class`, `mixin`, `enum`, `extension`,
  /// `extension type`, `typedef`, `function`, `getter`, `setter`,
  /// `variable`, `constructor`, `method`, `operator`, `field`,
  /// `enum value`.
  final String kind;

  /// Where its name starts in the file, from 0.
  final int nameOffset;

  /// The line its name is on, from 1.
  final int line;

  /// The first line of its code (after its doc comment and annotations).
  final int firstLine;

  /// Its last line.
  final int lastLine;

  /// Whether it, and the type it is in, have public names.
  final bool isPublic;

  /// Whether it has code that runs: a body, an initializer; not a type, an
  /// abstract or external member, a field without an initializer, nor a
  /// constant, whose value the compiler makes.
  final bool hasCode;

  /// Whether it is a type, whose members are declarations of their own.
  bool get isType => const {
    'class',
    'mixin',
    'enum',
    'extension',
    'extension type',
  }.contains(kind);

  @override
  String toString() => '$kind $name ($firstLine-$lastLine)';
}

/// The declarations of the Dart file [source], in the order they come.
List<Declaration> declarationsOf(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final lines = parsed.lineInfo;
  final found = <Declaration>[];

  void add(
    AstNode node,
    Token name,
    String qualified,
    String kind, {
    required bool public,
    bool code = false,
  }) {
    final start = node is AnnotatedNode
        ? node.firstTokenAfterCommentAndMetadata.offset
        : node.offset;
    found.add(
      Declaration(
        name: qualified,
        kind: kind,
        nameOffset: name.offset,
        line: _line(lines, name.offset),
        firstLine: _line(lines, start),
        lastLine: _line(lines, node.end > start ? node.end - 1 : start),
        isPublic: public && !name.lexeme.startsWith('_'),
        hasCode: code,
      ),
    );
  }

  void members(String type, List<ClassMember> members, {required bool public}) {
    for (final m in members) {
      switch (m) {
        case ConstructorDeclaration():
          final name = m.name;
          add(
            m,
            name ?? m.typeName?.token ?? m.beginToken,
            '$type.${name?.lexeme ?? 'new'}',
            'constructor',
            public: public,
            code: m.externalKeyword == null,
          );
        case MethodDeclaration():
          add(
            m,
            m.name,
            '$type.${m.name.lexeme}',
            m.isGetter
                ? 'getter'
                : m.isSetter
                ? 'setter'
                : m.isOperator
                ? 'operator'
                : 'method',
            public: public,
            code: m.externalKeyword == null && m.body is! EmptyFunctionBody,
          );
        case FieldDeclaration():
          for (final v in m.fields.variables) {
            add(
              v,
              v.name,
              '$type.${v.name.lexeme}',
              'field',
              public: public,
              code:
                  m.externalKeyword == null &&
                  !m.fields.isConst &&
                  v.initializer != null,
            );
          }
        default:
      }
    }
  }

  for (final d in parsed.unit.declarations) {
    switch (d) {
      case ClassDeclaration():
        final name = d.namePart.typeName;
        add(d, name, name.lexeme, 'class', public: true);
        members(name.lexeme, d.body.members, public: _public(name));
      case MixinDeclaration():
        add(d, d.name, d.name.lexeme, 'mixin', public: true);
        members(d.name.lexeme, d.body.members, public: _public(d.name));
      case EnumDeclaration():
        final name = d.namePart.typeName;
        add(d, name, name.lexeme, 'enum', public: true);
        for (final c in d.body.constants) {
          add(
            c,
            c.name,
            '${name.lexeme}.${c.name.lexeme}',
            'enum value',
            public: _public(name),
          );
        }
        members(name.lexeme, d.body.members, public: _public(name));
      case ExtensionTypeDeclaration():
        final name = d.namePart.typeName;
        add(d, name, name.lexeme, 'extension type', public: true);
        members(name.lexeme, d.body.members, public: _public(name));
      case ExtensionDeclaration():
        final name = d.name;
        final label =
            name?.lexeme ??
            'extension on ${d.onClause?.extendedType.toSource() ?? '?'}';
        add(d, name ?? d.extensionKeyword, label, 'extension', public: true);
        members(
          label,
          d.body.members,
          public: name == null || _public(name),
        );
      case GenericTypeAlias():
        add(d, d.name, d.name.lexeme, 'typedef', public: true);
      case FunctionTypeAlias():
        add(d, d.name, d.name.lexeme, 'typedef', public: true);
      case ClassTypeAlias():
        add(d, d.name, d.name.lexeme, 'class', public: true);
      case FunctionDeclaration():
        add(
          d,
          d.name,
          d.name.lexeme,
          d.isGetter
              ? 'getter'
              : d.isSetter
              ? 'setter'
              : 'function',
          public: true,
          code:
              d.externalKeyword == null &&
              d.functionExpression.body is! EmptyFunctionBody,
        );
      case TopLevelVariableDeclaration():
        for (final v in d.variables.variables) {
          add(
            v,
            v.name,
            v.name.lexeme,
            'variable',
            public: true,
            code:
                d.externalKeyword == null &&
                !d.variables.isConst &&
                v.initializer != null,
          );
        }
      default:
    }
  }
  return found;
}

bool _public(Token name) => !name.lexeme.startsWith('_');

int _line(LineInfo lines, int offset) => lines.getLocation(offset).lineNumber;
