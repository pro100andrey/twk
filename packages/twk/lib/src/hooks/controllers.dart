/// The hooks of the objects widgets are controlled by: [useFocusNode],
/// [useFocusScopeNode], [useTextEditingController], [useScrollController]
/// and [useListController]. Each is made by the first build and disposed
/// with the element.
library;

import '../../twk.dart';

import 'hook.dart';

// Examples can assume:
// late List<String> files;

/// A [FocusNode] of the first build, for a `Focus` widget's `focusNode`;
/// each build sets its [debugLabel], [onKeyEvent], [canRequestFocus],
/// [skipTraversal] and [descendantsAreFocusable].
///
/// A field that takes the focus when a key asks for it:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final node = useFocusNode(debugLabel: 'search');
///     return KeyBindings({
///       '/': node.requestFocus,
///     }, child: TextField(focusNode: node));
///   },
/// )
/// ```
FocusNode useFocusNode({
  String? debugLabel,
  FocusOnKeyEventCallback? onKeyEvent,
  bool canRequestFocus = true,
  bool skipTraversal = false,
  bool descendantsAreFocusable = true,
}) => use(
  _FocusNodeHook<FocusNode>(
    FocusNode.new,
    'useFocusNode',
    nodeLabel: debugLabel,
    onKeyEvent: onKeyEvent,
    canRequestFocus: canRequestFocus,
    skipTraversal: skipTraversal,
    descendantsAreFocusable: descendantsAreFocusable,
  ),
);

/// A [FocusScopeNode] of the first build, for a `FocusScope` widget's
/// `node`; each build sets what [useFocusNode]'s does.
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final scope = useFocusScopeNode(debugLabel: 'sidebar');
///     return FocusScope(node: scope, child: TextField(autofocus: true));
///   },
/// )
/// ```
FocusScopeNode useFocusScopeNode({
  String? debugLabel,
  FocusOnKeyEventCallback? onKeyEvent,
  bool canRequestFocus = true,
  bool skipTraversal = false,
  bool descendantsAreFocusable = true,
}) => use(
  _FocusNodeHook<FocusScopeNode>(
    FocusScopeNode.new,
    'useFocusScopeNode',
    nodeLabel: debugLabel,
    onKeyEvent: onKeyEvent,
    canRequestFocus: canRequestFocus,
    skipTraversal: skipTraversal,
    descendantsAreFocusable: descendantsAreFocusable,
  ),
);

final class _FocusNodeHook<N extends FocusNode> extends Hook<N> {
  const _FocusNodeHook(
    this.create,
    this.debugLabel, {
    required this.nodeLabel,
    required this.onKeyEvent,
    required this.canRequestFocus,
    required this.skipTraversal,
    required this.descendantsAreFocusable,
  });

  final N Function() create;

  @override
  final String debugLabel;

  final String? nodeLabel;
  final FocusOnKeyEventCallback? onKeyEvent;
  final bool canRequestFocus;
  final bool skipTraversal;
  final bool descendantsAreFocusable;

  @override
  _FocusNodeHookState<N> createState() => _FocusNodeHookState<N>();
}

final class _FocusNodeHookState<N extends FocusNode>
    extends HookState<N, _FocusNodeHook<N>> {
  late final N _node;

  @override
  void initHook() {
    super.initHook();
    _node = hook.create();
    _configure();
  }

  @override
  void didUpdateHook(_FocusNodeHook<N> oldHook) {
    super.didUpdateHook(oldHook);
    _configure();
  }

  void _configure() => _node
    ..debugLabel = hook.nodeLabel
    ..onKeyEvent = hook.onKeyEvent
    ..canRequestFocus = hook.canRequestFocus
    ..skipTraversal = hook.skipTraversal
    ..descendantsAreFocusable = hook.descendantsAreFocusable;

  @override
  N build(BuildContext context) => _node;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }
}

/// A [TextEditingController] of the first build, of a text, or of a value
/// (`useTextEditingController.fromValue`), made anew when the keys of a
/// build differ from the last one's; the text of later builds is ignored.
///
/// A field that starts with a name and says how long it is:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final controller = useTextEditingController(text: 'Ada');
///     useListenable(controller);
///     return Column(
///       children: [
///         TextField(controller: controller),
///         Text('${controller.text.length} characters'),
///       ],
///     );
///   },
/// )
/// ```
const useTextEditingController = TextEditingControllerHookCreator._();

/// What [useTextEditingController] is: a [call] or a [fromValue].
final class TextEditingControllerHookCreator {
  const TextEditingControllerHookCreator._();

  /// A controller of [text] with the caret at its end.
  TextEditingController call({String text = '', List<Object?>? keys}) => use(
    _ControllerHook(
      () => TextEditingController(text: text),
      keys,
      'useTextEditingController',
    ),
  );

  /// A controller of [value].
  TextEditingController fromValue(
    TextEditingValue value, [
    List<Object?>? keys,
  ]) => use(
    _ControllerHook(
      () => TextEditingController.fromValue(value),
      keys,
      'useTextEditingController.fromValue',
    ),
  );
}

/// A [ScrollController] of the first build, whose scrollable starts at
/// [initialOffset], made anew when the [keys] of a build differ from the
/// last one's.
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final controller = useScrollController();
///     return KeyBindings({
///       'g': () => controller.jumpTo(0),
///     }, child: SingleChildScrollView(
///       controller: controller,
///       child: Text(files.join('\n')),
///     ));
///   },
/// )
/// ```
ScrollController useScrollController({
  int initialOffset = 0,
  List<Object?>? keys,
}) => use(
  _ControllerHook(
    () => ScrollController(initialOffset: initialOffset),
    keys,
    'useScrollController',
  ),
);

/// A [ListController] of the first build, whose list starts at
/// [initialOffset], made anew when the [keys] of a build differ from the
/// last one's.
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final controller = useListController();
///     return ListView.builder(
///       controller: controller,
///       itemCount: files.length,
///       itemBuilder: (context, i) => Text(files[i]),
///     );
///   },
/// )
/// ```
ListController useListController({
  int initialOffset = 0,
  List<Object?>? keys,
}) => use(
  _ControllerHook(
    () => ListController(initialOffset: initialOffset),
    keys,
    'useListController',
  ),
);

final class _ControllerHook<C extends ChangeNotifier> extends Hook<C> {
  const _ControllerHook(this.create, List<Object?>? keys, this.debugLabel)
    : super(keys: keys);

  final C Function() create;

  @override
  final String debugLabel;

  @override
  _ControllerHookState<C> createState() => _ControllerHookState<C>();
}

final class _ControllerHookState<C extends ChangeNotifier>
    extends HookState<C, _ControllerHook<C>> {
  late final C _controller;

  @override
  void initHook() {
    super.initHook();
    _controller = hook.create();
  }

  @override
  C build(BuildContext context) => _controller;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
