/// The warning of key names that fire only with the kitty keyboard
/// protocol, and of those that fail the build: [KeyNames].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../key_names.dart';
import '../test_directory.dart';
import '../twk_types.dart';

/// A key name, a string written in place, that a terminal without the
/// kitty keyboard protocol never sends as that key, so that a binding of
/// it fires only on the protocol's terminals: `ctrl+i` arrives as `tab`,
/// `ctrl+shift+c` as `ctrl+c`, `shift+enter` as `enter`, and `super+s`
/// not at all, as twk's `KeyCombo` documents; and a name that fails the
/// build: one twk's parser rejects (`'esc'`, `'cmd+s'`), two names of one
/// map that are the same keys (`'A'` and `'shift+a'`), a hint for a key
/// the bindings written beside it do not bind.
///
/// The names are read where twk reads them: the keys of the maps of
/// `KeyBindings` and `Shortcuts` and of their `hints`, `LeaderKey`'s
/// leader, `SelectionArea`'s `copyKey` and `clearKey`, `KeyCombo.parse`
/// and `KeyCombo.parseSequence`, and twk_term's `TerminalView.ignoredKeys`.
/// The names are read by [parseKeys], twk's parser ported, and the keys
/// sent by [withoutKitty]. A key that fires only with the protocol is not
/// reported in a file under the package's `test/`, whose tests say which
/// terminal they are on.
///
/// ```dart-nocheck
/// KeyBindings({'ctrl+i': indent}, child: editor) // reported: as 'tab'
/// ```
///
/// With a key every terminal sends:
///
/// ```dart-nocheck
/// KeyBindings({'tab': indent}, child: editor)
/// ```
final class KeyNames extends MultiAnalysisRule {
  /// The rule, named `key_names`, a warning.
  KeyNames()
    : super(
        name: 'key_names',
        description:
            'Name keys that every terminal sends, as twk reads key names.',
      );

  /// What it reports of a key that fires only with the kitty protocol:
  /// the key, and how other terminals send it.
  static const kittyOnly = LintCode(
    'key_names',
    "'{0}' fires only with the kitty keyboard protocol: other terminals "
        'send it {1}.',
    correctionMessage: 'Try a key every terminal sends as itself.',
    uniqueName: 'key_names_kitty_only',
    severity: DiagnosticSeverity.WARNING,
  );

  /// What it reports of a name twk's parser rejects: the name, and the
  /// parser's message.
  static const notAKey = LintCode(
    'key_names',
    "The key name '{0}' fails the build: {1}",
    uniqueName: 'key_names_not_a_key',
    severity: DiagnosticSeverity.ERROR,
  );

  /// What it reports of the second of two names of one map that are the
  /// same keys.
  static const sameKeys = LintCode(
    'key_names',
    "The key names '{0}' and '{1}' fail the build: they are the same {2}.",
    correctionMessage: 'Try removing one of them.',
    uniqueName: 'key_names_same_keys',
    severity: DiagnosticSeverity.ERROR,
  );

  /// What it reports of a hint for keys the bindings beside it do not
  /// bind.
  static const unboundHint = LintCode(
    'key_names',
    "The hint of '{0}' fails the build: it is not bound.",
    correctionMessage: 'Try binding it, or removing the hint.',
    uniqueName: 'key_names_unbound_hint',
    severity: DiagnosticSeverity.ERROR,
  );

  @override
  List<DiagnosticCode> get diagnosticCodes => [
    kittyOnly,
    notAKey,
    sameKeys,
    unboundHint,
  ];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, kitty: !inTestDirectory(context));
    registry
      ..addInstanceCreationExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.kitty});

  final KeyNames rule;

  /// Whether keys that fire only with the protocol are reported.
  final bool kitty;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.type.element;
    final constructor = node.constructorName.name?.name;
    final arguments = node.argumentList.arguments;
    switch (element?.name) {
      case 'KeyBindings' || 'Shortcuts'
          when constructor == null && _isTwk(element):
        _layer(node);
      case 'LeaderKey' when _isTwk(element):
        if (arguments.firstOrNull case final StringLiteral leader?) {
          _name(leader, one: true);
        }
      case 'SelectionArea' when _isTwk(element):
        for (final name in ['copyKey', 'clearKey']) {
          if (_named(node, name) case final StringLiteral key) {
            _name(key, leader: true);
          }
        }
      case 'KeyCombo' when constructor == 'parse' && _isTwk(element):
        if (arguments.firstOrNull case final StringLiteral spec?) {
          _name(spec, one: true);
        }
      case 'TerminalView' when isFromPackage(element, 'twk_term'):
        if (_named(node, 'ignoredKeys') case final ListLiteral keys) {
          for (final key in keys.elements.whereType<StringLiteral>()) {
            _name(key, one: true);
          }
        }
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'parseSequence') {
      return;
    }
    final target = node.target;
    if (target is! Identifier || !_isTwk(target.element)) {
      return;
    }
    if (target.element?.name != 'KeyCombo') {
      return;
    }
    final arguments = node.argumentList.arguments;
    if (arguments.firstOrNull case final StringLiteral spec?) {
      final leader = arguments.any(
        (a) => a is NamedArgument && a.name.lexeme == 'leader',
      );
      _name(spec, leader: leader);
    }
  }

  /// The maps of a `KeyBindings` or a `Shortcuts`: their names, the same
  /// keys twice in one, and hints for keys not bound.
  void _layer(InstanceCreationExpression node) {
    final bindings = node.argumentList.arguments.firstOrNull;
    final bound = <String, String>{};
    var complete = false;
    if (bindings is SetOrMapLiteral) {
      complete = bindings.elements.every((e) => e is MapLiteralEntry);
      _map(bindings, bound);
    }
    if (_named(node, 'hints') case final SetOrMapLiteral hints) {
      final hinted = <String, String>{};
      for (final (literal, id) in _map(hints, hinted)) {
        if (complete && !bound.containsKey(id)) {
          rule.reportAtNode(
            literal,
            diagnosticCode: KeyNames.unboundHint,
            arguments: [literal.stringValue!],
          );
        }
      }
    }
  }

  /// The names of [map]'s keys, read; the same keys twice among its
  /// entries reported, those of each kept in [seen] by their keys as
  /// text. Returns the names read, with their keys as text.
  List<(StringLiteral, String)> _map(
    SetOrMapLiteral map,
    Map<String, String> seen,
  ) {
    final read = <(StringLiteral, String)>[];
    void entries(Iterable<CollectionElement> elements, {required bool top}) {
      for (final element in elements) {
        switch (element) {
          case MapLiteralEntry(key: final StringLiteral literal):
            final keys = _name(literal, leader: true);
            if (keys == null) {
              continue;
            }
            final id = keys.join(' ');
            final name = literal.stringValue!;
            if (top) {
              if (seen[id] case final before? when before != name) {
                final what = keys.length > 1 ? 'keys' : 'key';
                rule.reportAtNode(
                  literal,
                  diagnosticCode: KeyNames.sameKeys,
                  arguments: [before, name, what],
                );
              }
              seen[id] = name;
            }
            read.add((literal, id));
          case IfElement(:final thenElement, :final elseElement):
            entries([thenElement, ?elseElement], top: false);
          case ForElement(:final body):
            entries([body], top: false);
          default:
        }
      }
    }

    entries(map.elements, top: true);
    return read;
  }

  /// The keys [literal] names, read: null, and reported, where it names
  /// none; a key that fires only with the protocol reported. [one] for a
  /// single key, [leader] where `leader` stands for one.
  List<KeySpec>? _name(
    StringLiteral literal, {
    bool one = false,
    bool leader = false,
  }) {
    final spec = literal.stringValue;
    if (spec == null) {
      return null;
    }
    final List<KeySpec> keys;
    try {
      keys = one ? [parseKey(spec)] : parseKeys(spec, leader: leader);
    } on KeyNameException catch (e) {
      rule.reportAtNode(
        literal,
        diagnosticCode: KeyNames.notAKey,
        arguments: [spec, e.message],
      );
      return null;
    }
    if (kitty) {
      for (final key in keys) {
        final sent = switch (withoutKitty(key)) {
          AsItself() => null,
          AsOther(key: final other) => "as '$other'",
          NotSent(superKey: true) => 'not at all, as Super is not sent',
          NotSent() => 'as no key of its own',
        };
        if (sent != null) {
          rule.reportAtNode(
            literal,
            diagnosticCode: KeyNames.kittyOnly,
            arguments: ['$key', sent],
          );
        }
      }
    }
    return keys;
  }

  static bool _isTwk(Element? element) =>
      element is InterfaceElement && isTwkClass(element, element.name ?? '');

  /// The expression of [node]'s argument named [name]; null where it has
  /// none.
  static Expression? _named(InstanceCreationExpression node, String name) {
    for (final argument in node.argumentList.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == name) {
        return argument.argumentExpression;
      }
    }
    return null;
  }
}
