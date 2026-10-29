/// Debugging aids: describing and dumping the tree, and debug overlays:
/// the log console, and the lines it shows a stack in ([stackLines]).
/// The binding shows the console and the frame overlay over an app, and
/// outlines a node of it (`AppBinding.debug`).
library;

import 'dart:async';

import '../framework/framework.dart';
import 'console_record.dart';

// Examples can assume:
// late BuildContext context;

export 'console.dart' hide RenderConsolePanel;
export 'console_record.dart' show stackLines;
export 'editor.dart';
export 'traceback.dart';

/// Prints the element tree [context] is in, from its root down, as
/// [DiagnosticsNode.toStringDeep] renders [Element.describe]: each
/// element's widget type and key, its properties (its widget's, its
/// state's, its render object's and what the render object's parent keeps
/// on it), its size, and flags such as a repaint boundary (◆). In an app,
/// `print` goes to the app's log.
///
/// A key that dumps the tree to the log, to read in the console:
///
/// ```dart
/// KeyBindings(
///   {'f12': () => debugDumpTree(context)},
///   child: const Text('app'),
/// )
/// ```
///
/// See also:
///
///  * [debugDumpRenderTree], the render objects instead.
void debugDumpTree(BuildContext context) =>
    Zone.current.print(_rootOf(context).describe().toStringDeep());

/// Prints the render tree [context]'s render object is in, from its root
/// down, as [DiagnosticsNode.toStringDeep] renders the root's
/// `describe()`: each render object's type, properties, offset in its
/// parent, constraints, size and flags; `no render object` for a tree
/// without one.
///
/// ```dart
/// debugDumpRenderTree(context);
/// ```
void debugDumpRenderTree(BuildContext context) {
  var o = context.findRenderObject() ?? _rootOf(context).renderObject;
  while (o?.parent != null) {
    o = o!.parent;
  }
  Zone.current.print(o?.describe().toStringDeep() ?? 'no render object');
}

/// The element at the top of the tree [context] is in.
Element _rootOf(BuildContext context) {
  var root = context as Element;
  context.visitAncestorElements((e) {
    root = e;
    return true;
  });
  return root;
}
