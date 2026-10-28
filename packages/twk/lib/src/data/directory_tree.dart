/// The files under a directory as a tree, for a side panel: a
/// [DirectoryTree], which lists each directory as it is opened and again
/// as it changes on disk, and the [DirectoryTreeController] that reveals a
/// path in it and lists directories again.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show Attr, TextOverflow, TextWrap;

import '../controls/file_picker.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../foundation/format.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/flex.dart';
import '../platform/paths.dart';
import '../platform/platform.dart' show describeFileError, isWindows;
import '../style/style.dart';
import '../text/widgets.dart';
import 'gitignore.dart';
import 'tree.dart';

// Examples can assume:
// late BuildContext context;
// void edit(String path) {}

/// Reads and moves what a [DirectoryTree] shows from outside: given to it
/// as its `controller`, the path [selected], the directories expanded, and
/// a path to [reveal].
///
/// Its listeners are told as the selection or the directories expanded
/// change, by the controller or by the tree's keys and mouse. [expand] and
/// [collapse] work before a tree has it, and the tree shows what they
/// did; [reveal] and [refresh] need the tree, but for a path revealed
/// before, which the tree reveals as it starts. One tree at a time has it:
/// given to another, that one takes it over.
///
/// A tree that shows the file an editor opened, and a key that lists the
/// tree again:
///
/// ```dart
/// final controller = DirectoryTreeController();
/// final tree = KeyBindings(
///   {'f5': controller.refresh},
///   child: DirectoryTree(root: '.', controller: controller, onOpened: edit),
/// );
/// await controller.reveal('lib/main.dart');
/// ```
final class DirectoryTreeController extends ChangeNotifier {
  /// A controller that selects nothing and expands nothing but the root
  /// its tree expands as it starts.
  DirectoryTreeController() {
    _tree.addListener(_treeChanged);
  }

  final _tree = TreeController();
  final _hosts = ControllerHost<_DirectoryTreeState>();

  _DirectoryTreeState? get _state => _hosts.host;

  // a path revealed before a tree had the controller
  String? _pending;

  // what the listeners were told of last
  String? _toldSelected;
  var _toldExpanded = const <Object>{};

  // whether a change is the tree's own, which tells nobody
  var _quiet = false;

  /// The absolute path of the entry selected; null for none.
  String? get selected => switch (_tree.selectedKey) {
    final String path => path,
    _ => null,
  };

  /// Whether the children of [directory] show.
  bool isExpanded(String directory) => _tree.isExpanded(_full(directory));

  /// Expands [directory]: its entries show, listed as they first do.
  void expand(String directory) => _tree.expand(_full(directory));

  /// Collapses [directory]: its entries no longer show, and are listed
  /// again as it is next expanded.
  void collapse(String directory) => _tree.collapse(_full(directory));

  /// Expands the directories from the root down to [path], each listed in
  /// turn, and selects it: the tree scrolls to it. The future completes
  /// once it is selected. A path is absolute, or relative to the tree's
  /// root, `~` at its start the home directory; one outside the root does
  /// nothing, and one the tree does not show (not there, hidden or
  /// ignored) selects nothing that shows. Before a tree has the
  /// controller, the tree it is given to reveals the path as it starts,
  /// and the future completes at once.
  Future<void> reveal(String path) {
    final state = _state;
    if (state == null) {
      _pending = path;
      return Future.value();
    }
    return state._reveal(path);
  }

  /// Lists [directory] again, or every directory listed when null, as a
  /// change on disk does: what shows meanwhile stays, the selection and
  /// what is expanded too. The future completes once they are listed; at
  /// once while no tree has the controller.
  Future<void> refresh([String? directory]) =>
      _state?._refresh(directory) ?? Future.value();

  String _full(String path) => _state?._full(path) ?? path;

  /// Runs [change], whose changes to the tree tell no listener.
  void _quietly(VoidCallback change) {
    _quiet = true;
    try {
      change();
    } finally {
      _quiet = false;
    }
    _toldSelected = selected;
    _toldExpanded = {..._tree.expanded};
  }

  void _treeChanged() {
    final selected = this.selected;
    final expanded = _tree.expanded;
    if (_quiet ||
        (selected == _toldSelected &&
            expanded.length == _toldExpanded.length &&
            _toldExpanded.containsAll(expanded))) {
      return;
    }
    _toldSelected = selected;
    _toldExpanded = {...expanded};
    notifyListeners();
  }

  @override
  void dispose() {
    _tree
      ..removeListener(_treeChanged)
      ..dispose();
    _hosts.dispose();
    super.dispose();
  }
}

/// The files and directories under [root] as a tree, for a side panel:
/// each directory listed as it is first expanded, and listed again while
/// it shows as it changes on disk.
///
/// ```text
/// ▾ lib/
///   ▸ src/
///   ▾ widgets/
///     button.dart   4.3 kB
///     table.dart   18.5 kB
///   twk.dart
/// ```
///
/// A panel of the working directory beside an editor, a file opened by
/// Enter or a double click:
///
/// ```dart
/// Row(
///   children: [
///     SizedBox(
///       width: 30,
///       child: DirectoryTree(root: '.', onOpened: edit, autofocus: true),
///     ),
///     const Expanded(child: Text('editor')),
///   ],
/// )
/// ```
///
/// It is a [TreeView] of the entries of [fileSystem]: the root first,
/// expanded as it starts, then the entries of each directory expanded
/// below it, the directories first, in bold with a separator after their
/// names, then the files, each kind by name in any case. A directory
/// expanded shows a spinner below it while it is listed; one that fails to
/// list shows why below it in [ThemeData.muted], as `(permission denied)`.
/// Its keys, mouse, guides ([showGuides], none by default) and selection
/// are the TreeView's; Enter and a double click open a file
/// ([onOpened]) and expand or collapse a directory. [onSelected] is called
/// with the path of each entry selected, by the keys, the mouse or the
/// [controller].
///
/// The entries whose names start with a dot show with [showHidden]. With
/// [gitignore], those the `.gitignore` files of the root and of the
/// directories below it ignore do not show ([Gitignore]), the patterns of
/// a file deeper down deciding before those above it, nor does `.git`; a
/// directory's `.gitignore` is read as it is listed. With a [filter], the
/// files it accepts show, and every directory. With [showSizes], each
/// file's size shows at the end of its row, as `4.3 kB`. [icon] gives
/// what shows before an entry's name, such as a glyph of a Nerd Font;
/// null for nothing.
///
/// With [watch], each directory expanded is watched
/// ([PickerFileSystem.watch]) and listed again a tenth of a second after
/// it changes, the changes in between taken with it: the selection and
/// what is expanded stay, by path. A change of [root], [fileSystem],
/// [gitignore] or [showSizes] lists every directory again.
///
/// It takes all the room it is given, which must be bounded. With a
/// [controller], the app reads what is selected, expands and collapses
/// directories, reveals a path and lists directories again.
///
/// See also:
///
///  * [FilePicker], a file picked in a dialog.
///  * [InMemoryFileSystem], a tree of files of the app's own.
final class DirectoryTree extends StatefulWidget {
  /// A tree of the entries under [root], relative to the current directory
  /// of [fileSystem], `~` at its start the home directory.
  const DirectoryTree({
    required this.root,
    super.key,
    this.fileSystem = PickerFileSystem.local,
    this.controller,
    this.onSelected,
    this.onOpened,
    this.showHidden = false,
    this.gitignore = true,
    this.watch = true,
    this.showSizes = false,
    this.filter,
    this.icon,
    this.showGuides = false,
    this.focusNode,
    this.autofocus = false,
  });

  /// The directory at the top.
  final String root;

  /// What the directories are listed from: the machine's by default.
  final PickerFileSystem fileSystem;

  /// Reads what is selected and moves it from outside; null for one of its
  /// own.
  final DirectoryTreeController? controller;

  /// Called with the absolute path of each entry selected.
  final void Function(String path)? onSelected;

  /// Called with the absolute path of a file opened by Enter or a double
  /// click.
  final void Function(String path)? onOpened;

  /// Whether the entries whose names start with a dot show.
  final bool showHidden;

  /// Whether what the `.gitignore` files under [root] ignore is hidden,
  /// `.git` too.
  final bool gitignore;

  /// Whether the directories expanded are listed again as they change.
  final bool watch;

  /// Whether each file's size shows at the end of its row.
  final bool showSizes;

  /// Which files show; null for all of them. Every directory shows.
  final FileFilter? filter;

  /// What shows before the name of an entry, a space after it; null, or a
  /// null from it, for nothing.
  final String? Function(DirectoryEntry entry)? icon;

  /// Whether lines join the entries to their directories.
  final bool showGuides;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  @override
  State<DirectoryTree> createState() => _DirectoryTreeState();
}

/// An entry of a directory shown, or the note of why a directory does not
/// list ([note]).
@immutable
final class _Node {
  const _Node(this.path, this.name, {required this.isDirectory, this.size})
    : note = null;

  const _Node.note(this.path, String this.note)
    : name = '',
      isDirectory = false,
      size = null;

  /// Its absolute path; a note's is its directory's.
  final String path;
  final String name;
  final bool isDirectory;

  /// The size of a file, where it was asked for and is known.
  final int? size;
  final String? note;

  Object get key => note == null ? path : _NoteKey(path);
}

/// The key of the note below the directory at [path].
@immutable
final class _NoteKey {
  const _NoteKey(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is _NoteKey && other.path == path;

  @override
  int get hashCode => Object.hash(_NoteKey, path);
}

/// What listing a directory came to: its entries in order, or the error
/// it failed with, and the text of its `.gitignore`.
typedef _Read = ({List<_Node>? entries, Object? error, String? ignore});

/// A directory listed, or being listed: what it holds, what of that shows,
/// and its watch.
final class _Listing {
  _Listing(this.dir);

  final String dir;

  // what the last listing came to: none before the first ends
  List<_Node>? entries;
  Object? error;
  String? ignoreText;
  Gitignore? ignore;

  // what shows of it, and the directories among them; null to work out
  List<_Node>? shown;
  Set<String>? shownDirs;

  // the first listing; the listings started so far
  Future<void>? reading;
  var runs = 0;

  StreamSubscription<void>? _watching;

  bool get loaded => entries != null || error != null;

  /// Whether [watch] watches the directory.
  bool get watched => _watching != null;

  /// Calls [changed] as [files] says the directory changed, until the
  /// watch ends: the directory is watched again as it is next listed.
  void watch(PickerFileSystem files, VoidCallback changed) {
    late final StreamSubscription<void> watching;
    watching = _watching = files
        .watch(dir)
        .listen(
          (_) => changed(),
          onError: (Object _) {},
          onDone: () {
            if (identical(_watching, watching)) {
              _watching = null;
            }
          },
        );
  }

  /// Stops watching the directory.
  void close() {
    unawaited(_watching?.cancel());
    _watching = null;
  }
}

final class _DirectoryTreeState extends State<DirectoryTree> {
  DirectoryTreeController? _own;

  DirectoryTreeController get _controller =>
      widget.controller ?? (_own ??= DirectoryTreeController());

  TreeController get _tree => _controller._tree;

  late String _root;
  late _Node _rootNode;

  // the directories listed, by path
  final _listings = <String, _Listing>{};

  // the directories that changed since the timer started
  final _changed = <String>{};
  Timer? _debounce;

  // the path onSelected was called with last
  String? _selected;

  @override
  void initState() {
    super.initState();
    _setRoot();
    _attach(_controller);
  }

  @override
  void didUpdateWidget(DirectoryTree old) {
    super.didUpdateWidget(old);
    final w = widget;
    final oldController = old.controller ?? _own;
    var reread =
        w.root != old.root ||
        w.fileSystem != old.fileSystem ||
        w.gitignore != old.gitignore ||
        w.showSizes != old.showSizes;
    if (!identical(oldController, _controller)) {
      if (oldController != null) {
        _detach(oldController);
      }
      reread = true;
    }
    if (reread) {
      for (final listing in _listings.values) {
        listing.close();
      }
      _listings.clear();
      _changed.clear();
      _setRoot();
      if (!identical(oldController, _controller)) {
        _attach(_controller);
      } else {
        _controller._quietly(() => _tree.expand(_root));
      }
      _tree.reload();
      return;
    }
    if (w.showHidden != old.showHidden || !_sameFilter(w.filter, old.filter)) {
      for (final listing in _listings.values) {
        listing
          ..shown = null
          ..shownDirs = null;
      }
      _tree.reload();
      _prune();
    }
    if (w.watch != old.watch) {
      for (final listing in _listings.values) {
        if (w.watch) {
          _watch(listing);
        } else {
          listing.close();
        }
      }
    }
  }

  @override
  void dispose() {
    _detach(_controller);
    for (final listing in _listings.values) {
      listing.close();
    }
    _debounce?.cancel();
    _own?.dispose();
    super.dispose();
  }

  void _setRoot() {
    final files = widget.fileSystem;
    _root = resolvePath(
      files.currentDirectory,
      widget.root,
      files.homeDirectory,
    );
    final name = rootOf(_root) == _root ? '' : baseName(_root);
    _rootNode = _Node(_root, name, isDirectory: true);
  }

  void _attach(DirectoryTreeController controller) {
    controller._hosts.attach(this);
    controller.addListener(_controllerChanged);
    _selected = controller.selected;
    controller._quietly(() => controller._tree.expand(_root));
    final pending = controller._pending;
    controller._pending = null;
    if (pending != null) {
      controller._hosts.afterBuild(() {
        if (mounted && identical(_controller, controller)) {
          unawaited(_reveal(pending));
        }
      });
    }
  }

  void _detach(DirectoryTreeController controller) {
    controller.removeListener(_controllerChanged);
    controller._hosts.detach(this);
  }

  /// [path] made absolute: relative to the root, `~` the home directory.
  String _full(String path) =>
      resolvePath(_root, path, widget.fileSystem.homeDirectory);

  void _controllerChanged() {
    _prune();
    final selected = _controller.selected;
    if (selected != _selected) {
      _selected = selected;
      if (selected != null) {
        widget.onSelected?.call(selected);
      }
    }
  }

  /// The entries of the directory of [node] that show: from its listing
  /// where it is listed, else once it is.
  FutureOr<List<_Node>> _children(_Node node) {
    if (!node.isDirectory) {
      return const [];
    }
    final listing = _listings[node.path] ??= _Listing(node.path);
    if (listing.loaded) {
      return _shownOf(listing);
    }
    return _read(listing).then((_) => _shownOf(listing));
  }

  /// What shows of [listing]: its entries that [_shows], or the note of
  /// why it does not list; none before it is listed, or where it was
  /// dropped before.
  List<_Node> _shownOf(_Listing listing) {
    if (listing.shown case final shown?) {
      return shown;
    }
    final List<_Node> shown;
    if (listing.error case final error?) {
      shown = [_Node.note(listing.dir, '(${_reason(error)})')];
    } else if (listing.entries case final entries?) {
      shown = [
        for (final entry in entries)
          if (_shows(entry)) entry,
      ];
    } else {
      return const [];
    }
    listing.shownDirs = {
      for (final entry in shown)
        if (entry.isDirectory) entry.path,
    };
    return listing.shown = shown;
  }

  /// Whether [entry] shows: hidden, filtered out or ignored, it does not.
  bool _shows(_Node entry) {
    final w = widget;
    if (!w.showHidden && entry.name.startsWith('.')) {
      return false;
    }
    final filter = w.filter;
    if (!entry.isDirectory && filter != null && !filter.accepts(entry.name)) {
      return false;
    }
    if (!w.gitignore) {
      return true;
    }
    if (entry.name == '.git') {
      return false;
    }
    // the .gitignore files from the entry's directory up to the root's,
    // the first that decides deciding
    for (var dir = parentOf(entry.path); ; dir = parentOf(dir)) {
      if (_listings[dir]?.ignore case final ignore?) {
        final from = dir.endsWith(separator) ? dir.length : dir.length + 1;
        final relative = entry.path.substring(from);
        final decided = ignore.match(
          isWindows ? relative.replaceAll(r'\', '/') : relative,
          isDirectory: entry.isDirectory,
        );
        if (decided != null) {
          return !decided;
        }
      }
      if (dir == _root || !isWithin(_root, dir)) {
        return true;
      }
    }
  }

  /// The first listing of [listing]'s directory, started where it is not.
  Future<void> _read(_Listing listing) {
    if (listing.loaded) {
      return Future.value();
    }
    return listing.reading ??= _run(listing);
  }

  /// Lists [listing]'s directory again, what it shows meanwhile kept.
  Future<void> _relist(_Listing listing) =>
      listing.loaded ? _run(listing) : _read(listing);

  /// Lists [listing]'s directory, and puts what it holds in its place
  /// unless it was dropped, or listed again, meanwhile.
  Future<void> _run(_Listing listing) async {
    final run = ++listing.runs;
    final read = await _list(listing.dir);
    if (!mounted ||
        run != listing.runs ||
        !identical(_listings[listing.dir], listing)) {
      return;
    }
    final first = !listing.loaded;
    final ignoreBefore = listing.ignoreText;
    listing
      ..entries = read.entries
      ..error = read.error
      ..ignoreText = read.ignore
      ..ignore = switch (read.ignore) {
        final text? => Gitignore(text),
        null => null,
      }
      ..shown = null
      ..shownDirs = null;
    _watch(listing);
    if (!first) {
      if (read.ignore != ignoreBefore) {
        // what shows below it is ignored by its patterns too
        for (final other in _listings.values) {
          if (isWithin(listing.dir, other.dir)) {
            other
              ..shown = null
              ..shownDirs = null;
            _tree.reload(other.dir);
          }
        }
      }
      _tree.reload(listing.dir);
    }
    _prune();
  }

  /// The entries of [dir], in order, and the text of its `.gitignore`
  /// where they are read; or the error listing it failed with.
  Future<_Read> _list(String dir) async {
    final files = widget.fileSystem;
    final gitignore = widget.gitignore;
    final sizes = widget.showSizes;
    final found = <DirectoryEntry>[];
    try {
      await for (final entry in files.list(dir)) {
        found.add(entry);
      }
    } on Object catch (error) {
      return (entries: null, error: error, ignore: null);
    }
    String? ignore;
    if (gitignore) {
      final file = joinPath(dir, '.gitignore');
      if (found.any(
        (e) => !e.isDirectory && baseName(e.path) == '.gitignore',
      )) {
        try {
          ignore = await files.read(file);
        } on Object {
          // a .gitignore that does not read ignores nothing
        }
      }
    }
    final entries = await Future.wait([
      for (final entry in found)
        _entry(files, dir, entry, size: sizes && !entry.isDirectory),
    ]);
    return (entries: entries..sort(_order), error: null, ignore: ignore);
  }

  static Future<_Node> _entry(
    PickerFileSystem files,
    String dir,
    DirectoryEntry entry, {
    required bool size,
  }) async {
    final name = baseName(entry.path);
    final path = joinPath(dir, name);
    int? bytes;
    if (size) {
      try {
        bytes = await files.sizeOf(path);
      } on Object {
        // a size that cannot be told shows none
      }
    }
    return _Node(path, name, isDirectory: entry.isDirectory, size: bytes);
  }

  /// Watches [listing]'s directory, with [DirectoryTree.watch], where it
  /// is not watched yet.
  void _watch(_Listing listing) {
    if (!widget.watch || listing.watched) {
      return;
    }
    try {
      listing.watch(widget.fileSystem, () => _changedOnDisk(listing.dir));
    } on Object {
      // a directory that cannot be watched is listed as it is opened
    }
  }

  void _changedOnDisk(String dir) {
    _changed.add(dir);
    _debounce ??= Timer(const Duration(milliseconds: 100), () {
      _debounce = null;
      final changed = [..._changed];
      _changed.clear();
      for (final dir in changed) {
        if (_listings[dir] case final listing?) {
          unawaited(_relist(listing));
        }
      }
    });
  }

  /// Drops the listings of the directories that no longer show: collapsed,
  /// below one collapsed, or gone from their directory's entries. Each is
  /// listed again as it next shows.
  void _prune() {
    if (_listings.isEmpty) {
      return;
    }
    final visible = <String, bool>{};
    final gone = [
      for (final dir in _listings.keys)
        if (!_visible(dir, visible)) dir,
    ];
    for (final dir in gone) {
      _listings.remove(dir)!.close();
      _changed.remove(dir);
    }
    for (final dir in gone) {
      _tree.reload(dir);
    }
  }

  /// Whether the entries of [dir] show, or may once the directory above it
  /// is listed; [known] holds what was found so far.
  bool _visible(String dir, Map<String, bool> known) => known[dir] ??= () {
    if (!_tree.isExpanded(dir)) {
      return false;
    }
    if (dir == _root) {
      return true;
    }
    if (!isWithin(_root, dir)) {
      return false;
    }
    final parent = _listings[parentOf(dir)];
    if (parent == null || !_visible(parent.dir, known)) {
      return false;
    }
    if (!parent.loaded) {
      return true;
    }
    _shownOf(parent);
    return parent.shownDirs!.contains(dir);
  }();

  Future<void> _reveal(String path) async {
    final full = _full(path);
    if (full != _root && !isWithin(_root, full)) {
      return;
    }
    final dirs = <String>[];
    for (var dir = full; dir != _root;) {
      dir = parentOf(dir);
      dirs.add(dir);
    }
    final controller = _controller;
    for (final dir in dirs.reversed) {
      _tree.expand(dir);
      await _read(_listings[dir] ??= _Listing(dir));
      if (!mounted || !identical(controller, _controller)) {
        return;
      }
    }
    _tree.selectedKey = full;
  }

  Future<void> _refresh(String? directory) async {
    if (directory == null) {
      await Future.wait([
        for (final l in [..._listings.values]) _relist(l),
      ]);
    } else if (_listings[_full(directory)] case final listing?) {
      await _relist(listing);
    }
  }

  /// Enter or a double click on [node]: a file opened, a directory
  /// expanded or collapsed.
  void _activate(_Node node) {
    if (node.note != null) {
      return;
    }
    if (node.isDirectory) {
      _tree.toggle(node.path);
    } else {
      widget.onOpened?.call(node.path);
    }
  }

  @override
  Widget build(BuildContext context) => TreeView<_Node>(
    roots: [_rootNode],
    children: _children,
    hasChildren: (node) => node.isDirectory,
    nodeKey: (node) => node.key,
    label: _label,
    controller: _tree,
    onActivated: _activate,
    showGuides: widget.showGuides,
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
  );

  Widget _label(BuildContext context, TreeEntry<_Node> entry) {
    final node = entry.node;
    final theme = Theme.of(context);
    if (node.note case final note?) {
      return Text(
        note,
        style: theme.muted,
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
      );
    }
    final icon = widget.icon?.call((
      path: node.path,
      isDirectory: node.isDirectory,
    ));
    final name = node.isDirectory && !node.name.endsWith(separator)
        ? '${node.name}$separator'
        : node.name;
    final Widget label = Text.rich(
      [
        if (icon != null) Span('$icon '),
        Span(
          name,
          node.isDirectory ? const Style(attrs: Attr.bold) : const Style(),
        ),
      ],
      wrap: TextWrap.none,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final size = node.size;
    return GestureDetector(
      onDoubleTap: (_) => _activate(node),
      child: size == null || !widget.showSizes
          ? label
          : Row(
              children: [
                Expanded(child: label),
                Text(' ${formatBytes(size)}', style: theme.muted),
              ],
            ),
    );
  }
}

/// Whether [a] and [b] accept the same files.
bool _sameFilter(FileFilter? a, FileFilter? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null || a.extensions.length != b.extensions.length) {
    return false;
  }
  for (var i = 0; i < a.extensions.length; i++) {
    if (a.extensions[i] != b.extensions[i]) {
      return false;
    }
  }
  return true;
}

/// The directories first, then the files, each kind by name in any case.
int _order(_Node a, _Node b) {
  if (a.isDirectory != b.isDirectory) {
    return a.isDirectory ? -1 : 1;
  }
  final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return order != 0 ? order : a.name.compareTo(b.name);
}

/// Why listing failed with [error], its first letter small:
/// `permission denied`.
String _reason(Object error) {
  final why = describeFileError(error);
  return why.isEmpty ? why : '${why[0].toLowerCase()}${why.substring(1)}';
}
