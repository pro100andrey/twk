/// The element each render object of the tree belongs to. Internal: not
/// exported.
library;

import 'package:twk_core/twk_core.dart' show RenderObject;

import '../framework/framework.dart' show Element;

/// The [Element] whose render object a [RenderObject] is, from its mount to
/// its unmount: what a path of the tree is told from a render object by,
/// walking up the render tree, not down the element tree. Kept in debug
/// only (inside `assert`): a release build walks the element tree when an
/// error needs a path, and pays nothing per mount.
final renderElements = Expando<Element>('renderElements');
