/// Where a widget was made, found in the app's code: [InspectNode],
/// [creationOwners], [constructorCalls] and what they use.
///
/// twk keeps no creation locations (its widgets' constructors are `const`
/// and run no code, and `dart run` has no kernel transformer such as
/// Flutter's track-widget-creation), so an element's widget is looked for
/// in the `build` methods above it ([creationOwners]), the nearest first,
/// as a call of its type's constructor in that method's source
/// ([constructorCalls]); among several, the one in the place the element
/// has among those of its type that build made ([CreationOwner.index]).
/// Pure functions over the tree and source text; the VM service lookups
/// are `SourceLocator`'s. The VS Code extension does the same in
/// `source_find.ts`, in the same steps.
library;

import 'app_client.dart' show Json;

/// A node of a tree an app describes (`ext.twk.tree`).
final class InspectNode {
  /// The node [json] describes, and the nodes below it.
  InspectNode(this.json)
    : id = json['id']! as int,
      children = [
        for (final child in json['children'] as List<Object?>? ?? const [])
          InspectNode(child! as Json),
      ];

  /// What the app said of it.
  final Json json;

  /// Its id in the app.
  final int id;

  /// The nodes below it.
  final List<InspectNode> children;

  /// Its type.
  String get name => json['name'] as String? ?? '?';

  /// The type whose `build` makes its child (a stateless widget's, a
  /// state's); null for a node that does not build.
  String? get build => json['build'] as String?;

  /// The id of the node's counterpart in the other tree: an element's
  /// render object, a render object's element.
  int? get counterpart => (json['render'] ?? json['element']) as int?;

  /// The value of its first property without a name, which says most of
  /// it (a text's string).
  String? get summary {
    for (final p in json['properties'] as List<Object?>? ?? const []) {
      if (p case final Json p when p['name'] == null) {
        return p['value'] as String?;
      }
    }
    return null;
  }

  /// This node and every one below it, depth first.
  Iterable<InspectNode> get all sync* {
    yield this;
    for (final c in children) {
      yield* c.all;
    }
  }

  /// The nodes from [root] down to the node [id], or null where [root] has
  /// none of that id.
  static List<InspectNode>? pathTo(InspectNode? root, int id) {
    if (root == null) {
      return null;
    }
    if (root.id == id) {
      return [root];
    }
    for (final c in root.children) {
      final below = pathTo(c, id);
      if (below != null) {
        return [root, ...below];
      }
    }
    return null;
  }
}

/// A build method that may have made the widget: the component element
/// whose build it is, and what it made of that type.
final class CreationOwner {
  /// The build of [build], at [node], which made [count] elements of the
  /// widget's type, the widget the [index]th.
  const CreationOwner(this.node, this.build, this.index, this.count);

  /// The element whose child its `build` makes.
  final InspectNode node;

  /// The type of that `build` (the widget's, the state's).
  final String build;

  /// Where the widget is among the elements of its type this build made, in
  /// the tree's order.
  final int index;

  /// How many elements of its type this build made.
  final int count;
}

/// The type [name] (a runtimeType's text) is a class of: `Foo<int>` is
/// `Foo`.
String className(String name) {
  final lt = name.indexOf('<');
  return lt < 0 ? name : name.substring(0, lt);
}

/// The builds that may have made the widget of the element [id] names, the
/// nearest first: each element above it that builds (a stateless widget's,
/// a stateful one's), with where the element is among those of its type it
/// made. What one build made: the elements below it, but those below
/// another build that [makes] widgets of that type, which that one made;
/// below one that makes none, they were passed to it (a `child`), and so
/// are counted; the builds on the way to [id] are looked into, as the
/// widget may have been passed through them (a `child`, a builder's
/// closure).
List<CreationOwner> creationOwners(
  InspectNode? root,
  int id, [
  bool Function(String build) makes = _always,
]) {
  final path = InspectNode.pathTo(root, id);
  if (path == null) {
    return const [];
  }
  final target = path.last;
  final onPath = {for (final n in path) n.id};
  final type = className(target.name);
  final owners = <CreationOwner>[];
  for (var i = path.length - 2; i >= 0; i--) {
    final node = path[i];
    final build = node.build;
    if (build == null) {
      continue;
    }
    final made = <InspectNode>[];
    void visit(InspectNode n) {
      if (className(n.name) == type) {
        made.add(n);
      }
      // another build's elements are its own, but on the way to the target
      // or where it makes none of the type
      if (n.build == null || onPath.contains(n.id) || !makes(n.build!)) {
        n.children.forEach(visit);
      }
    }

    node.children.forEach(visit);
    final at = made.indexOf(target);
    owners.add(CreationOwner(node, build, at < 0 ? 0 : at, made.length));
  }
  return owners;
}

bool _always(String build) => true;

/// [source] with its comments and string literals blanked out, each
/// character's offset kept.
String codeOnly(String source) {
  final out = source.codeUnits.toList();
  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      if (out[k] != 0x0A) {
        out[k] = 0x20;
      }
    }
  }

  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      final end = source.indexOf('\n', i);
      final to = end < 0 ? source.length : end;
      blank(i, to);
      i = to;
    } else if (c == '/' && next == '*') {
      // Dart's block comments nest
      var depth = 1;
      var k = i + 2;
      while (k < source.length && depth > 0) {
        if (source.startsWith('/*', k)) {
          depth++;
          k += 2;
        } else if (source.startsWith('*/', k)) {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      var k = i + quote.length;
      while (k < source.length &&
          !source.startsWith(quote, k) &&
          (triple || source[k] != '\n')) {
        k += !raw && source[k] == r'\' ? 2 : 1;
      }
      final to = k + quote.length > source.length
          ? source.length
          : k + quote.length;
      blank(i, to);
      i = to;
    } else {
      i++;
    }
  }
  return String.fromCharCodes(out);
}

/// The offsets in [source] between [from] and [to] where a constructor of
/// [type] is called: `Text(`, `const Text(`, `Text.rich(`, `Foo<int>(`,
/// `w.Text(` with an import prefix; in code only, not in a comment or a
/// string.
List<int> constructorCalls(String source, int from, int to, String type) {
  final code = codeOnly(source);
  final call = RegExp(
    r'(?<![\w$])(?:[a-z_][\w$]*\.)?('
    '${RegExp.escape(type)}'
    r')\s*(?:<[^()]*?>)?\s*(?:\.[A-Za-z_$][\w$]*)?\s*\(',
  );
  return [
    for (final m in call.allMatches(code, from))
      if (m.start < to)
        // where the type's name is, after any prefix
        m.start + m[0]!.indexOf(m[1]!),
  ];
}

/// The line and column, both from 1, of [offset] in [source].
({int line, int column}) lineColumnOf(String source, int offset) {
  var line = 1;
  var start = 0;
  for (
    var i = source.indexOf('\n');
    i >= 0 && i < offset;
    i = source.indexOf('\n', i + 1)
  ) {
    line++;
    start = i + 1;
  }
  return (line: line, column: offset - start + 1);
}

/// The offset in [source] of [line] and [column], both from 1.
int offsetOf(String source, int line, int column) {
  var start = 0;
  for (var l = 1; l < line; l++) {
    final nl = source.indexOf('\n', start);
    if (nl < 0) {
      return source.length;
    }
    start = nl + 1;
  }
  final at = start + column - 1;
  return at < source.length ? at : source.length;
}

/// The line and column of [tokenPos] in a script's `tokenPosTable` (the VM
/// service's: rows of a line, then pairs of a token position and its
/// column); null where the table has none.
({int line, int column})? tokenLineColumn(
  List<List<int>> table,
  int tokenPos,
) {
  for (final row in table) {
    for (var k = 1; k + 1 < row.length; k += 2) {
      if (row[k] == tokenPos) {
        return (line: row[0], column: row[k + 1]);
      }
    }
  }
  return null;
}

/// Which of [calls] (of the widget's type, in a build's source) made the
/// widget: the only one, or the one at its [index] among the [count] the
/// build made when there are as many calls; else the one nearest that
/// place, the guess said not to be exact. Null for no calls.
({int offset, bool exact})? pickCall(List<int> calls, int index, int count) {
  if (calls.isEmpty) {
    return null;
  }
  // one call makes every element of its type the build made
  final exact = calls.length == 1 || calls.length == count;
  final at = index < calls.length - 1 ? index : calls.length - 1;
  return (offset: calls[at], exact: exact);
}

/// The types whose builds make the elements of the tree [root], by name,
/// each once: what [creationOwners]' `makes` is asked of.
Set<String> buildsIn(InspectNode? root) => {
  for (final n in root?.all ?? const <InspectNode>[])
    if (n.build != null) n.build!,
};
