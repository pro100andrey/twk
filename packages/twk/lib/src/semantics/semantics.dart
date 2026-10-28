/// What the widgets of an app are to a screen reader: a [Semantics] gives
/// what is below it a [SemanticsRole], a label, a value, a
/// [SemanticsState] and a hint, a [BlockSemantics] leaves out what it
/// covers, an [ExcludeSemantics] what is below it, and [SemanticsNode.of]
/// reads the tree of them, with the text of the [Text]s among them, as the
/// lines of text the screen-reader mode of an app shows
/// (`AppBinding.screenReader`).
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show RenderObject;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../text/widgets.dart';

// Examples can assume:
// late BuildContext context;
// late bool wifi;

/// What a node of the semantics is, as its line says it ([word]): ARIA's
/// roles. A [container] has a line of its own, label or
/// not, before those of the nodes in it.
enum SemanticsRole {
  /// A message that asks for attention: an error, a toast.
  alert('alert'),

  /// What runs an action when pressed.
  button('button'),

  /// What is checked or not ([SemanticsState.checked]).
  checkbox('checkbox'),

  /// A window over the rest of the app, a container.
  dialog('dialog', container: true),

  /// The title of a section.
  heading('heading'),

  /// What goes somewhere else when pressed.
  link('link'),

  /// A container of [listItem]s.
  list('list', container: true),

  /// An item of a [list].
  listItem('listitem'),

  /// A container of [menuItem]s: a popup menu.
  menu('menu', container: true),

  /// A row of menus, a container.
  menuBar('menubar', container: true),

  /// An entry of a [menu] or a [menuBar].
  menuItem('menuitem'),

  /// How far something has got, its value the part done.
  progressBar('progressbar'),

  /// One of a group of which one is checked.
  radio('radio'),

  /// A value picked in a range, its value the one picked.
  slider('slider'),

  /// What the app says of itself: a status line.
  status('status'),

  /// A tab of a [tabList], selected or not ([SemanticsState.selected]).
  tab('tab'),

  /// A row of [tab]s, a container.
  tabList('tablist', container: true),

  /// A field that text is typed in, its value the text.
  textBox('textbox'),

  /// What is on or off, ARIA's `switch`: checked reads as `on`.
  toggle('switch');

  const SemanticsRole(this.word, {this.container = false});

  /// What the line says the node is.
  final String word;

  /// Whether the node holds others: it has a line without a label too.
  final bool container;
}

/// The state of a node of the semantics, ARIA's states, as its line says
/// it after the label: `checked` or `not checked` ([checked];
/// `on` or `off` for a [SemanticsRole.toggle]), `selected`, `expanded` or
/// `collapsed` ([expanded]), `disabled`.
@immutable
final class SemanticsState {
  /// A state of the words given; by default none: neither checked nor
  /// expanded, not selected, not disabled.
  const SemanticsState({
    this.checked,
    this.selected = false,
    this.expanded,
    this.disabled = false,
  });

  /// Whether it is checked, or a switch on; null for what is neither.
  final bool? checked;

  /// Whether it is the one chosen of those around it (a tab, an item).
  final bool selected;

  /// Whether what it opens is shown; null for what opens nothing.
  final bool? expanded;

  /// Whether it cannot be used, as a button greyed out.
  final bool disabled;

  /// What the line of a node of [role] in this state says after its label.
  List<String> wordsFor(SemanticsRole? role) {
    final toggle = role == SemanticsRole.toggle;
    return [
      if (checked ?? false)
        if (toggle) 'on' else 'checked'
      else if (checked != null)
        if (toggle) 'off' else 'not checked',
      if (selected) 'selected',
      if (expanded ?? false) 'expanded' else if (expanded != null) 'collapsed',
      if (disabled) 'disabled',
    ];
  }

  /// Whether [other] is a state of equal fields.
  @override
  bool operator ==(Object other) =>
      other is SemanticsState &&
      other.checked == checked &&
      other.selected == selected &&
      other.expanded == expanded &&
      other.disabled == disabled;

  @override
  int get hashCode => Object.hash(checked, selected, expanded, disabled);
}

/// Gives what [child] shows a node of the semantics ([SemanticsNode.of]):
/// a [role], a [label], a [value], a [state] and a [hint]. Below a node with no
/// other node below it and a role that is no [SemanticsRole.container],
/// the text of the [Text]s is its label when [label] is null, and left out
/// when it is not; below any other, each text is a node of its own, read
/// in its place.
///
/// [nodes] stand for what [child] draws in a render object of its own (the
/// tabs of a bar, the entries of a menu): read in place of what is below
/// it. Of them, one [SemanticsNode.focused] is the focused node while this
/// one is ([SemanticsNode.of]); elsewhere none is.
///
/// One with a [hint] and neither [role], [label], [value] nor [nodes] is
/// no node of its own where there is a node with a line below it: the
/// first of them, depth first, gets the hint, after one it has (a
/// `Tooltip` around a button: `button Help, Opens help`).
///
/// A base class: a widget whose element does work of its own can be one
/// (the items of a `ListView`).
///
/// A row drawn as a switch, read as one:
///
/// ```dart
/// Semantics(
///   role: SemanticsRole.toggle,
///   label: 'Wi-Fi',
///   state: SemanticsState(checked: wifi),
///   child: Text(wifi ? '[on ] Wi-Fi' : '[off] Wi-Fi'),
/// )
/// ```
///
/// Its line is `switch Wi-Fi, on` while [SemanticsState.checked] is true.
///
/// See also:
///
///  * [ExcludeSemantics], which leaves what is below it out.
///  * [SemanticsNode.of], which reads the tree.
base class Semantics extends StatelessWidget {
  /// Gives what [child] shows a node of [role], [label], [value], [state]
  /// and [hint], or the [nodes] given.
  const Semantics({
    required this.child,
    super.key,
    this.role,
    this.label,
    this.value,
    this.state = const SemanticsState(),
    this.hint,
    this.nodes,
  });

  /// What the node is of.
  final Widget child;

  /// What it is; null for a node that is its label alone.
  final SemanticsRole? role;

  /// What it is called: a button's text, a field's name.
  final String? label;

  /// What it holds: a field's text, how far a bar is.
  final String? value;

  /// Whether it is checked, selected, expanded or disabled; none of them
  /// by default.
  final SemanticsState state;

  /// What more there is to say of it, read last: what it does, a tooltip's
  /// message.
  final String? hint;

  /// The nodes of what [child] draws, read in place of what is below it;
  /// null to read what is below it.
  final List<SemanticsNode>? nodes;

  @override
  Widget build(BuildContext context) => child;

  /// Adds those of the role, label, value, state, hint and the number of
  /// [nodes] that are given.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add('role', role?.word, defaultValue: null)
      ..add('label', label, defaultValue: null)
      ..add('value', value, defaultValue: null)
      ..add('state', state.wordsFor(role).join(', '), defaultValue: '')
      ..add('hint', hint, defaultValue: null)
      ..add('nodes', nodes?.length, defaultValue: null);
  }
}

/// Leaves out of the semantics the nodes read before [child] in the node
/// it is in ([SemanticsNode.of]): what is under it, as under a modal
/// barrier.
///
/// A dialog over a page, the page left unread while it shows:
///
/// ```dart
/// Stack(
///   children: [
///     const Text('page'),
///     BlockSemantics(
///       child: Semantics(role: SemanticsRole.dialog, child: Text('Quit?')),
///     ),
///   ],
/// )
/// ```
final class BlockSemantics extends StatelessWidget {
  /// Leaves out what is read before [child].
  const BlockSemantics({required this.child, super.key});

  /// What is read, in place of what was read before it.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Leaves out of the semantics what is below it while [excluding]
/// ([SemanticsNode.of]): its [Semantics] and the texts of its [Text]s, as
/// though it were not there, the label a [Semantics] above takes of the
/// texts below it read without them; a node focused there reads as the
/// node above it that has a line. As Flutter's `ExcludeSemantics`; an
/// `Offstage` is one while its child is off the stage.
///
/// A row of decoration a screen reader need not read:
///
/// ```dart
/// const ExcludeSemantics(child: Text('~~~~~~~~'))
/// ```
final class ExcludeSemantics extends StatelessWidget {
  /// Leaves [child] out of the semantics while [excluding], as it is by
  /// default.
  const ExcludeSemantics({
    required this.child,
    this.excluding = true,
    super.key,
  });

  /// What is left out.
  final Widget child;

  /// Whether what is below it is left out; true by default.
  final bool excluding;

  @override
  Widget build(BuildContext context) => child;

  /// Adds [excluding] when it is false.
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('excluding', excluding, defaultValue: true);
  }
}

/// A node of the semantics of an app: what a [Semantics] says of what is
/// below it, or the text of a [Text], and the nodes read in it, in order
/// ([children]). A screen reader reads it as a line of text ([line]); the
/// tree as the lines of its nodes, one after another ([lines]).
///
/// What a screen reader would read of a subtree, line by line:
///
/// ```dart
/// final lines = SemanticsNode.of(context).lines;
/// ```
///
/// A widget that draws its parts in one render object hands nodes of its
/// own to [Semantics.nodes]:
///
/// ```dart
/// const tabs = [
///   SemanticsNode(role: SemanticsRole.tab, label: 'Files', focused: true),
///   SemanticsNode(role: SemanticsRole.tab, label: 'Search'),
/// ];
/// ```
@immutable
final class SemanticsNode {
  /// A node of [role], [label], [value], [state] and [hint], [focused] or
  /// not, with [children] read in it.
  const SemanticsNode({
    this.role,
    this.label,
    this.value,
    this.state = const SemanticsState(),
    this.hint,
    this.focused = false,
    this.children = const [],
  });

  /// The semantics of the widget of [context] and of what is below it: a
  /// node with neither role nor label whose [children] are the nodes read
  /// there, of the [Semantics] and of the texts of the [Text]s, in the
  /// order of the tree. What is not laid out with the widget of [context]
  /// is left out: a route covered, a tab not shown; so is what is below an
  /// [ExcludeSemantics].
  ///
  /// The node of [focus] is [focused], by default of the primary focus of
  /// the focus tree [context] is in: of the [Semantics] nearest above the
  /// widget of that node whose node has a line, or whose [Semantics.nodes]
  /// have one focused, which is the focused node then; with none above,
  /// the node read first below it.
  factory SemanticsNode.of(BuildContext context, {FocusNode? focus}) {
    final element = context as Element;
    final node =
        focus ??
        Focus.maybeOf(context, createDependency: false)?.manager?.primaryFocus;
    final focused = switch (node?.context) {
      final Element e => e,
      _ => null,
    };
    final reader = _Reader(element.renderObject, focused);
    final root = _Reading(null, null);
    reader.visit(element, root);
    final pick = reader.focused(root);
    return SemanticsNode(children: [for (final r in root.items) r.node(pick)]);
  }

  /// What it is ([Semantics.role]); null for a node that is its label
  /// alone, or the nodes in it.
  final SemanticsRole? role;

  /// What it is called ([Semantics.label]), or the text of a [Text].
  final String? label;

  /// What it holds ([Semantics.value]).
  final String? value;

  /// Whether it is checked, selected, expanded or disabled.
  final SemanticsState state;

  /// What more there is to say of it, read last ([line]).
  final String? hint;

  /// Whether the focus is on it: the node of the primary focus, as
  /// [SemanticsNode.of] finds it.
  final bool focused;

  /// The nodes read in it, in order; none by default.
  final List<SemanticsNode> children;

  /// What a screen reader reads of it: the [SemanticsRole.word] of its
  /// role, its label, after `: ` its value (after a blank without a label),
  /// after `, ` each word of its state, and after `, ` its hint, as
  /// `button OK`, `checkbox Remember me, checked`, `textbox Name: anna`,
  /// `button Save, disabled, Writes the file`; [lines] breaks it where its
  /// label, value or hint does. Empty for a node that is read as the nodes
  /// in it: one with neither role nor label nor value, or with a role that
  /// is not a [SemanticsRole.container] and nodes but neither label nor
  /// value; a hint alone does not give it a line.
  String get line {
    final role = this.role;
    final label = this.label ?? '';
    final value = this.value ?? '';
    if (label.isEmpty && value.isEmpty) {
      if (role == null || !role.container && children.isNotEmpty) {
        return '';
      }
    }
    final named = [?role?.word, if (label.isNotEmpty) label].join(' ');
    final line = value.isEmpty
        ? named
        : named.isEmpty
        ? value
        : '$named${label.isEmpty ? ' ' : ': '}$value';
    final hint = this.hint ?? '';
    return [
      line,
      ...state.wordsFor(role),
      if (hint.isNotEmpty) hint,
    ].join(', ');
  }

  /// This node with [more] after its hint, or the first node with a line
  /// below it given it, depth first; null when none has a line.
  SemanticsNode? _hinted(String more) {
    if (line.isNotEmpty) {
      final hint = this.hint ?? '';
      return _with(hint: hint.isEmpty ? more : '$hint, $more');
    }
    for (var i = 0; i < children.length; i++) {
      final hinted = children[i]._hinted(more);
      if (hinted != null) {
        return _with(children: [...children]..[i] = hinted);
      }
    }
    return null;
  }

  SemanticsNode _with({String? hint, List<SemanticsNode>? children}) =>
      SemanticsNode(
        role: role,
        label: label,
        value: value,
        state: state,
        hint: hint ?? this.hint,
        focused: focused,
        children: children ?? this.children,
      );

  /// The lines of the tree from this node down, depth first, the nodes
  /// whose [line] is empty left out.
  List<String> get lines => [
    for (final node in _depthFirst)
      if (node.line case final line when line.isNotEmpty) ...line.split('\n'),
  ];

  /// Which of [lines] is the first of the [focused] node's; null when no
  /// node with a line is.
  int? get focusedLine {
    var at = 0;
    for (final node in _depthFirst) {
      final line = node.line;
      if (line.isEmpty) {
        continue;
      }
      if (node.focused) {
        return at;
      }
      at += '\n'.allMatches(line).length + 1;
    }
    return null;
  }

  Iterable<SemanticsNode> get _depthFirst sync* {
    yield this;
    for (final child in children) {
      yield* child._depthFirst;
    }
  }
}

/// A [Semantics] or a text being read, with what is read below it.
final class _Reading {
  _Reading(this.widget, this.element);

  _Reading.text(String this.text) : widget = null, element = null;

  final Semantics? widget;
  final Element? element;
  String? text;
  final items = <_Reading>[];

  /// Whether its label is the texts below it, there being nothing else: a
  /// node that holds none ([SemanticsRole.container]).
  bool get _leaf =>
      widget?.nodes == null &&
      !(widget?.role?.container ?? false) &&
      items.every((r) => r.text != null);

  /// What it reads as, [focused] the node that is.
  SemanticsNode node(_Reading? focused) {
    final text = this.text;
    if (text != null) {
      return SemanticsNode(label: text, focused: identical(this, focused));
    }
    final w = widget!;
    final leaf = _leaf;
    final nodes = w.nodes;
    final mine = identical(this, focused);
    final node = SemanticsNode(
      role: w.role,
      label: w.label ?? (leaf ? items.map((r) => r.text).join(' ') : null),
      value: w.value,
      state: w.state,
      hint: w.hint,
      focused: mine && !_hasFocused(nodes),
      children: [
        if (nodes != null && mine)
          ...nodes
        else if (nodes != null)
          for (final n in nodes) _unfocused(n)
        else if (!leaf)
          for (final r in items) r.node(focused),
      ],
    );
    // a hint alone: the first node with a line below gets it
    final hint = w.hint ?? '';
    if (hint.isEmpty || node.line.isNotEmpty) {
      return node;
    }
    final hinted = SemanticsNode(
      focused: node.focused,
      children: node.children,
    )._hinted(hint);
    return hinted ?? node;
  }

  /// Whether it reads as a node with a line.
  bool get _hasLine => node(null).line.isNotEmpty;

  static bool _hasFocused(List<SemanticsNode>? nodes) =>
      nodes != null && nodes.any((n) => n._depthFirst.any((d) => d.focused));

  static SemanticsNode _unfocused(SemanticsNode n) =>
      !n._depthFirst.any((d) => d.focused)
      ? n
      : SemanticsNode(
          role: n.role,
          label: n.label,
          value: n.value,
          state: n.state,
          children: [for (final c in n.children) _unfocused(c)],
        );
}

/// Reads the elements below one whose render object is [root], and where
/// the one of the focus, [focus], is.
final class _Reader {
  _Reader(this.root, this.focus);

  final RenderObject? root;
  final Element? focus;

  // the reading of each Semantics element
  final _readings = Map<Element, _Reading>.identity();

  // in the subtree of focus; what was read there first
  var _inFocus = false;
  _Reading? _first;

  void visit(Element e, _Reading into) {
    final o = e.renderObject;
    // not laid out with the root: off the stage, or out in a commit
    if (o != null && !identical(o.owner, root?.owner)) {
      return;
    }
    final entered = identical(e, focus);
    if (entered) {
      _inFocus = true;
    }
    switch (e.widget) {
      case final Semantics widget:
        final r = _readings[e] = _Reading(widget, e);
        _add(into, r);
        if (widget.nodes == null) {
          e.visitChildren((c) => visit(c, r));
        }
      case BlockSemantics():
        into.items.clear();
        e.visitChildren((c) => visit(c, into));
      case ExcludeSemantics(excluding: true):
        break;
      case Text(:final data, :final spans):
        final text = (data ?? [for (final s in spans!) s.text].join()).trim();
        if (text.isNotEmpty) {
          _add(into, _Reading.text(text));
        }
      case _:
        e.visitChildren((c) => visit(c, into));
    }
    if (entered) {
      _inFocus = false;
    }
  }

  void _add(_Reading into, _Reading r) {
    into.items.add(r);
    if (_inFocus) {
      _first ??= r;
    }
  }

  /// The reading the focus is on, of those left below [root]
  /// ([SemanticsNode.of]).
  _Reading? focused(_Reading root) {
    final focus = this.focus;
    if (focus == null) {
      return null;
    }
    final kept = Set<_Reading>.identity();
    void keep(_Reading r) {
      kept.add(r);
      r.items.forEach(keep);
    }

    keep(root);
    _Reading? found;
    focus.visitAncestorElements((e) {
      final r = _readings[e];
      if (r != null &&
          kept.contains(r) &&
          (_Reading._hasFocused(r.widget!.nodes) || r._hasLine)) {
        found = r;
        return false;
      }
      return true;
    });
    final first = _first;
    return found ?? (first != null && kept.contains(first) ? first : null);
  }
}
