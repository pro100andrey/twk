/// Places an app names in its tree that code it does not know fills, as a
/// plugin's contribution: a [Slot] shows the [SlotEntry]s registered for
/// its name in the [SlotRegistry] of the nearest [SlotScope].
library;

import '../foundation/change_notifier.dart';
import 'framework.dart';

/// Lays out the widgets of a slot's entries, such as `(context, children)
/// => Row(children: children)`.
typedef SlotLayout = Widget Function(
  BuildContext context,
  List<Widget> children,
);

/// What a plugin puts in the [Slot]s named [slot]: what [builder] returns,
/// among the other entries of the slot by [order].
final class SlotEntry {
  /// An entry [id] of the slots named [slot], showing what [builder]
  /// returns, at [order] among the others, 0 by default.
  const SlotEntry({
    required this.slot,
    required this.id,
    required this.builder,
    this.order = 0,
  });

  /// The name of the slots it is shown in.
  final String slot;

  /// What tells it apart from the other entries of [slot]: a [Slot] shows
  /// it under a [ValueKey] of it, by which it keeps its element and state
  /// wherever it moves among them.
  final String id;

  /// Where it goes among the entries of [slot]: those of a lower order
  /// first, those of an equal one in the order their ids were registered.
  /// 0 by default.
  final int order;

  /// Builds what the entry shows, as an element of its own: what it throws
  /// is shown in place of this entry only ([BuildOwner.onBuildError]).
  final Widget Function(BuildContext context) builder;

  /// `SlotEntry(slot, id)`.
  @override
  String toString() => 'SlotEntry($slot, $id)';
}

/// The entries plugins put in the slots of an app, by the name of the
/// slot; a [SlotScope] puts it above the tree. It notifies its listeners
/// of each change.
///
/// A status bar that a plugin adds a clock to:
///
/// ```dart
/// final slots = SlotRegistry()
///   ..register(
///     SlotEntry(slot: 'status', id: 'clock', builder: (_) => Text('12:00')),
///   );
///
/// final app = SlotScope(
///   registry: slots,
///   child: Slot(
///     'status',
///     layout: (context, children) => Row(children: children),
///     placeholder: const Text('ready'),
///   ),
/// );
/// ```
final class SlotRegistry extends ChangeNotifier {
  // the entries of each slot by id, in the order their ids were registered
  final _byId = <String, Map<String, SlotEntry>>{};
  // the entries of each slot in order, as entriesOf gives them
  final _ordered = <String, List<SlotEntry>>{};

  /// The entries of [slot] in order ([SlotEntry.order]): an unmodifiable
  /// list, the same one until they change.
  List<SlotEntry> entriesOf(String slot) => _ordered[slot] ?? const [];

  /// Adds [entry] to its slot, in place of the entry of its id there,
  /// whose place among those of its order it then keeps.
  void register(SlotEntry entry) {
    final entries = _byId.putIfAbsent(entry.slot, () => {});
    if (identical(entries[entry.id], entry)) {
      return;
    }
    entries[entry.id] = entry;
    _changed(entry.slot);
  }

  /// Removes the entry of [id] from [slot]; false when it has none.
  bool unregister(String slot, String id) {
    if (_byId[slot]?.remove(id) == null) {
      return false;
    }
    _changed(slot);
    return true;
  }

  void _changed(String slot) {
    final entries = _byId[slot]!;
    if (entries.isEmpty) {
      _byId.remove(slot);
      _ordered.remove(slot);
    } else {
      // by order, then as registered: List.sort is not stable
      final indexed = [...entries.values.indexed]
        ..sort((a, b) {
          final byOrder = a.$2.order.compareTo(b.$2.order);
          return byOrder != 0 ? byOrder : a.$1 - b.$1;
        });
      _ordered[slot] = List.unmodifiable([for (final (_, e) in indexed) e]);
    }
    notifyListeners();
  }
}

/// Puts [registry] above [child]: the [Slot]s below show its entries.
///
/// See [SlotRegistry] for an example.
final class SlotScope extends InheritedWidget {
  /// Gives the [Slot]s in [child]'s subtree [registry]'s entries.
  const SlotScope({required this.registry, required super.child, super.key});

  /// The entries the slots below show; one replaced by another rebuilds
  /// them with its entries.
  final SlotRegistry registry;

  /// The registry of the nearest [SlotScope] above [context], if any.
  /// [context] depends on it.
  static SlotRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlotScope>()?.registry;

  /// The registry of the nearest [SlotScope] above [context]; a
  /// [StateError] if there is none. [context] depends on it.
  static SlotRegistry of(BuildContext context) =>
      maybeOf(context) ??
      (throw StateError('no SlotScope above ${context.widget.runtimeType}'));

  @override
  bool updateShouldNotify(SlotScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// Shows the entries registered for [name] in the registry of the nearest
/// [SlotScope], in order, as [layout] lays them out; [placeholder], when
/// given, while there are none. Without a SlotScope above, there are none.
///
/// It builds again when its entries change, and only then: a change to
/// another slot does not build it. Each entry is an element of its own
/// under a [ValueKey] of its [SlotEntry.id]: it keeps its state wherever
/// it moves among the others, is built again only when registered anew or
/// when what it depends on changes, and what its builder throws shows in
/// its place only, the others shown as ever ([BuildOwner.onBuildError]:
/// an `ErrorWidget` in an app that `runApp` runs). Slots of one name show
/// the same entries, each in elements of its own.
///
/// The toolbar of an editor, whose buttons plugins register:
///
/// ```dart
/// Slot(
///   'toolbar',
///   layout: (context, children) => Row(gap: 1, children: children),
/// )
/// ```
///
/// See [SlotRegistry] for the entries and a whole example.
final class Slot extends StatefulWidget {
  /// Shows the entries of the slot [name], laid out by [layout];
  /// [placeholder] while there are none.
  const Slot(this.name, {required this.layout, super.key, this.placeholder});

  /// The name of the slot: the entries whose [SlotEntry.slot] it is are
  /// shown.
  final String name;

  /// Lays out the widgets of the entries, in order; with no entries and no
  /// [placeholder], it gets an empty list.
  final SlotLayout layout;

  /// What is shown while the slot has no entries, in place of what
  /// [layout] makes of none; null, the default, for that.
  final Widget? placeholder;

  @override
  State<Slot> createState() => _SlotState();

  /// Adds the slot's [name].
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.addValue(name);
  }
}

final class _SlotState extends State<Slot> {
  SlotRegistry? _registry;

  // the entries the last build showed, and the widget of each
  List<SlotEntry> _shown = const [];
  var _widgets = Map<SlotEntry, Widget>.identity();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = SlotScope.maybeOf(context);
    if (!identical(registry, _registry)) {
      _registry?.removeListener(_changed);
      _registry = registry?..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _registry?.removeListener(_changed);
    super.dispose();
  }

  // the list of a slot is replaced when its entries change
  void _changed() {
    if (!identical(_registry!.entriesOf(widget.name), _shown)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _registry?.entriesOf(widget.name) ?? const <SlotEntry>[];
    _shown = entries;
    final placeholder = widget.placeholder;
    if (entries.isEmpty && placeholder != null) {
      _widgets = Map.identity();
      return placeholder;
    }
    // an entry shown before keeps its widget, and is not built again
    final widgets = Map<SlotEntry, Widget>.identity();
    for (final entry in entries) {
      widgets[entry] =
          _widgets[entry] ?? _Entry(entry, key: ValueKey(entry.id));
    }
    _widgets = widgets;
    return widget.layout(context, [...widgets.values]);
  }
}

/// What [entry] builds, as an element of its own.
final class _Entry extends StatelessWidget {
  const _Entry(this.entry, {super.key});

  final SlotEntry entry;

  @override
  Widget build(BuildContext context) => entry.builder(context);
}
