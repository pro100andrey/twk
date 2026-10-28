/// Names the assists write: [freeName] for a new declaration, [prefixed]
/// for a reference moved into another class.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// [base], or [base] with the first number from 2 on after it that no
/// declaration or import of [unit]'s library names.
String freeName(CompilationUnit unit, String base) {
  final scope = unit.declaredFragment?.scope;
  bool taken(String name) {
    final found = scope?.lookup(name);
    return found != null && (found.getter != null || found.setter != null);
  }

  if (!taken(base)) {
    return base;
  }
  for (var i = 2; ; i++) {
    if (!taken('$base$i')) {
      return '$base$i';
    }
  }
}

/// The edit, as (offset, length, replacement), that puts [prefix] (such
/// as `widget.`) before [node]: in braces where [node] is interpolated as
/// `$name`.
(int, int, String) prefixed(SimpleIdentifier node, String prefix) =>
    switch (node.parent) {
      final InterpolationExpression p when p.rightBracket == null => (
        p.offset,
        p.length,
        '\${$prefix${node.name}}',
      ),
      _ => (node.offset, 0, prefix),
    };
