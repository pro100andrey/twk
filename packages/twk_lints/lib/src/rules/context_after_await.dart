/// The warning of a `BuildContext` used where its widget may have left
/// the tree: [ContextAfterAwait].
library;

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import '../mounted_flow.dart';
import '../test_directory.dart';
import '../twk_types.dart';

/// A `State`'s `context`, or a variable or parameter of twk's
/// `BuildContext` type, used after an `await` or in a callback of a
/// `Future` (`then`, `catchError`, `whenComplete`, `Future.delayed`), with
/// no check of `mounted` since on some path to it. By then the widget may
/// have left the tree: `State.context` asserts once the state is disposed,
/// and a context kept from before finds no inherited widget (`Theme.of`)
/// or ancestor (`Navigator.of`). The Dart linter's
/// `use_build_context_synchronously` knows Flutter's `BuildContext`, not
/// twk's.
///
/// The paths and the checks are [MountedFlow]'s, as for
/// `set_state_after_dispose`: `if (!mounted) return;` (or
/// `if (!context.mounted) return;`) before the use, `if (mounted)` around
/// it, or a check in each branch of an `if` that awaited. A context passed
/// to the awaited call itself is used before the gap, and a variable
/// assigned after the gap is fresh, as is one a function written beside it
/// assigns (a builder that keeps its context). A context kept in a field,
/// and a guard of the code's own (a token, a flag), are not followed. In a
/// file under the package's `test/` only the code of classes is checked:
/// a test's body awaits its tester and knows what is mounted.
///
/// ```dart-nocheck
/// Future<void> _save() async {
///   await store.save(_draft);
///   showToast(context, 'Saved'); // reported: after an await
/// }
/// ```
///
/// With the check the rule asks for:
///
/// ```dart-nocheck
/// Future<void> _save() async {
///   await store.save(_draft);
///   if (!mounted) return;
///   showToast(context, 'Saved');
/// }
/// ```
final class ContextAfterAwait extends AnalysisRule {
  /// The rule, named `context_after_await`, a warning.
  ContextAfterAwait()
    : super(
        name: 'context_after_await',
        description:
            "Don't use a BuildContext where its widget may have left the "
            'tree.',
      );

  /// What it reports: the context's name, the gap it follows, and the
  /// check to make.
  static const code = LintCode(
    'context_after_await',
    "'{0}' may be used after its widget left the tree: {1}, with no check "
        "of '{2}'.",
    correctionMessage: "Try 'if (!{2}) return;' before it.",
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addSimpleIdentifier(
      this,
      _Visitor(this, inTests: inTestDirectory(context)),
    );
  }
}

/// The check that stands for [node], a use of a context: `mounted` for a
/// `State`'s `context`, `name.mounted` for a variable; null when [node] is
/// not a use of one.
String? mountedCheckFor(SimpleIdentifier node) {
  final element = node.element;
  if (element is GetterElement &&
      element.name == 'context' &&
      isTwkClass(element.enclosingElement, 'State')) {
    return 'mounted';
  }
  if ((element is LocalVariableElement || element is FormalParameterElement) &&
      isTwkSubtype((element! as VariableElement).type, 'BuildContext')) {
    return '${node.name}.mounted';
  }
  return null;
}

final class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, {required this.inTests});

  final ContextAfterAwait rule;

  /// Whether the file is under the package's `test/`, where only the code
  /// of classes is the app's: a test's own body awaits its tester and
  /// knows the tree it built.
  final bool inTests;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // the cheapest test first, as this runs for every identifier: a use of
    // a context has twk's `BuildContext` (or a subtype) for its type
    if (!isTwkSubtype(node.staticType, 'BuildContext') ||
        node.inDeclarationContext() ||
        node.inSetterContext()) {
      return;
    }
    final check = mountedCheckFor(node);
    if (check == null || _readsMounted(node)) {
      return;
    }
    final body = node.thisOrAncestorOfType<FunctionBody>();
    if (body == null ||
        (inTests && node.thisOrAncestorOfType<ClassDeclaration>() == null)) {
      return;
    }
    final gap = MountedFlow.of(body).gapAt(node);
    if (gap == null) {
      return;
    }
    rule.reportAtNode(
      node,
      arguments: [node.name, gap.why, check],
    );
  }

  /// Whether [node] is the context of `context.mounted`: the check itself.
  bool _readsMounted(SimpleIdentifier node) => switch (node.parent) {
    PrefixedIdentifier(:final prefix, :final identifier) =>
      identical(prefix, node) && identifier.name == 'mounted',
    PropertyAccess(:final target, :final propertyName) =>
      identical(target, node) && propertyName.name == 'mounted',
    _ => false,
  };
}
