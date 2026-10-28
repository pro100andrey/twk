// A file manager after Midnight Commander: the directories in a tree on
// the left, the files of one directory in a table on the right, side by
// side in a split view whose divider drags; a menu bar over them, a status
// bar and the keys that can be pressed under them.
//
// Each pane has a directory: the tree the one selected in it, the table
// the one it shows. F5 copies what is selected in the pane focused last
// into the directory of the other pane, F6 moves it there: from the
// table the files marked (Space marks one), or the one selected; from the
// tree the directory selected. A dialog asks first, with the directory to
// copy to in a field; then a progress bar fills as the files are copied,
// a slice of them each frame, until all are or Escape cancels. A file or a
// directory dragged with the mouse from one pane onto the other, or onto a
// directory in either, is copied or moved there, as the dialog then asks.
//
// Enter opens a directory in the table, from either pane; Backspace and
// ../ go up. Tab moves the focus from pane to pane and to the divider
// between them, which the arrows move. F2 renames what is selected and F7
// makes a directory, each in a form; F9 shows the settings on a screen of
// their own, which Ctrl+S saves and Escape leaves. F10 opens the menus,
// Ctrl+P lists the commands, Ctrl+Q quits. The bytes of the files are
// copied, not their permissions or times; the root of the tree stays
// where it is.
//
//   dart run example/files.dart [directory]
import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:twk/twk.dart' hide Link;

Future<void> main(List<String> args) async {
  final directory = args.isEmpty ? Directory.current.path : args.first;
  if (!FileSystemEntity.isDirectorySync(directory)) {
    stderr.writeln('no such directory: $directory');
    exitCode = 2;
    return;
  }
  await runApp(FileManager(directory: directory));
}

/// The order of the entries of a directory, its directories first.
enum SortBy { name, size, modified }

/// What the settings screen sets.
final class Settings {
  const Settings({
    this.showHidden = false,
    this.showGuides = true,
    this.confirm = true,
    this.sortBy = SortBy.name,
  });

  /// Whether the entries whose names start with a dot show.
  final bool showHidden;

  /// Whether lines join the directories of the tree to their parents.
  final bool showGuides;

  /// Whether F5 and F6 ask before they copy and move.
  final bool confirm;

  final SortBy sortBy;

  Settings copyWith({
    bool? showHidden,
    bool? showGuides,
    bool? confirm,
    SortBy? sortBy,
  }) => Settings(
    showHidden: showHidden ?? this.showHidden,
    showGuides: showGuides ?? this.showGuides,
    confirm: confirm ?? this.confirm,
    sortBy: sortBy ?? this.sortBy,
  );
}

/// The file manager of [directory]: its tree on the left, a directory's
/// files on the right; a copy or a move does [bytesPerFrame] bytes of the
/// work in a frame.
final class FileManager extends StatelessWidget {
  const FileManager({
    required this.directory,
    super.key,
    this.bytesPerFrame = defaultBytesPerFrame,
  });

  final String directory;

  final int bytesPerFrame;

  static const int defaultBytesPerFrame = 4 << 20;

  @override
  Widget build(BuildContext context) => Navigator(
    home: _Browser(directory: directory, bytesPerFrame: bytesPerFrame),
  );
}

/// What a [Transfer] does.
enum Operation {
  copy('Copy', 'Copying', 'Copied', 'copied'),
  move('Move', 'Moving', 'Moved', 'moved');

  const Operation(this.label, this.doing, this.done, this.past);

  final String label;
  final String doing;
  final String done;
  final String past;
}

/// What a file's entry counts for in the work of a [Transfer], beside its
/// bytes: so that empty files and directories take their share.
const _entryCost = 4096;

/// A copy or a move of [sources], files, links and directories, into the
/// directory [target], done a slice at a time ([step]).
///
/// A copy makes the directories and copies the files and links below them.
/// A move renames each source; one renamed onto a directory that is there
/// already moves its entries into it, and one that cannot be renamed
/// there, as across file systems, is copied, then deleted.
final class Transfer {
  Transfer(this.operation, this.sources, this.target) {
    for (final (i, source) in sources.indexed) {
      final to = _join(target, _name(source));
      _work.addAll(
        operation == .copy ? _copying(i, source, to) : [_Rename(i, source, to)],
      );
    }
    for (final work in _work) {
      _total += work.cost;
      if (work is _CopyFile) {
        _totalBytes += work.size;
      }
    }
  }

  final Operation operation;
  final List<String> sources;
  final String target;

  // what is left to do, the next first
  final _work = Queue<_Work>();
  var _total = 0;
  var _done = 0;
  var _totalBytes = 0;
  var _bytes = 0;
  var _items = 0;
  var _cancelled = false;
  var _current = '';

  static final _buffer = Uint8List(64 << 10);

  /// How much is done, from 0 to 1.
  double get progress => _total == 0 ? 1 : min(_done / _total, 1);

  /// The sources done.
  int get items => _items;

  /// The bytes of the files copied so far, and of all of them.
  int get bytes => _bytes;
  int get totalBytes => _totalBytes;

  /// What is being copied or moved.
  String get current => _current;

  /// Whether [cancel] stopped it before it was done.
  bool get isCancelled => _cancelled;

  /// Does the work of about [budget] bytes; returns whether some is left.
  /// A [FileSystemException] stops it at the work that failed, which
  /// [cancel] then takes back.
  bool step(int budget) {
    var left = budget;
    while (left > 0 && _work.isNotEmpty) {
      final work = _work.first;
      _current = work.from;
      switch (work) {
        case _CopyFile():
          final copied = _copy(work, left);
          left -= copied;
          _done += copied;
          _bytes += copied;
          if (work.input != null) {
            continue;
          }
        case _MakeDirectory(:final to):
          Directory(to).createSync();
        case _CopyLink(:final from, :final to):
          Link(to).createSync(Link(from).targetSync());
        case _Rename():
          if (!_rename(work)) {
            continue;
          }
        case _Remove(:final from, :final recursive):
          _entity(from).deleteSync(recursive: recursive);
      }
      _work.removeFirst();
      _current = _work.firstOrNull?.from ?? _current;
      left -= _entryCost;
      _done += _entryCost;
      if (_work.firstOrNull?.item != work.item) {
        _items++;
      }
    }
    return _work.isNotEmpty;
  }

  /// Stops it before what is left: a file half copied is deleted, those
  /// copied and moved before it stay.
  void cancel() {
    if (_work.isEmpty) {
      return;
    }
    if (_work.first case final _CopyFile work) {
      work.input?.closeSync();
      if (work.output case final output?) {
        output.closeSync();
        File(work.to).deleteSync();
      }
    }
    _work.clear();
    _cancelled = true;
  }

  /// The work of copying [from], the [item]th source, to [to].
  List<_Work> _copying(int item, String from, String to) =>
      switch (FileSystemEntity.typeSync(from, followLinks: false)) {
        .directory => [
          _MakeDirectory(item, from, to),
          for (final e in Directory(from).listSync(followLinks: false))
            ..._copying(item, e.path, _join(to, _name(e.path))),
        ],
        .link => [_CopyLink(item, from, to)],
        _ => [_CopyFile(item, from, to, File(from).lengthSync())],
      };

  /// Copies up to [budget] bytes of [work]; returns how many.
  int _copy(_CopyFile work, int budget) {
    final input = work.input ??= File(work.from).openSync();
    final output = work.output ??= File(work.to).openSync(mode: .write);
    var copied = 0;
    while (copied < budget) {
      final n = input.readIntoSync(
        _buffer,
        0,
        min(_buffer.length, budget - copied),
      );
      if (n == 0) {
        input.closeSync();
        output.closeSync();
        work
          ..input = null
          ..output = null;
        break;
      }
      output.writeFromSync(_buffer, 0, n);
      copied += n;
    }
    return copied;
  }

  /// Renames [work]'s source; returns false where other work took its
  /// place: the moves of its entries into a directory there already, or
  /// its copy and deletion where it cannot be renamed.
  bool _rename(_Rename work) {
    final _Rename(:item, :from, :to) = work;
    final type = FileSystemEntity.typeSync(from, followLinks: false);
    final List<_Work> instead;
    if (type == .directory && FileSystemEntity.isDirectorySync(to)) {
      instead = [
        for (final e in Directory(from).listSync(followLinks: false))
          _Rename(item, e.path, _join(to, _name(e.path))),
        _Remove(item, from, recursive: false),
      ];
    } else {
      try {
        _entity(from).renameSync(to);
        return true;
      } on FileSystemException catch (e) {
        // across file systems
        if (e.osError?.errorCode != _crossDevice) {
          rethrow;
        }
      }
      instead = [..._copying(item, from, to), _Remove(item, from)];
    }
    _work.removeFirst();
    for (final w in instead.reversed) {
      _work.addFirst(w);
      _total += w.cost;
      if (w is _CopyFile) {
        _totalBytes += w.size;
      }
    }
    _total -= work.cost;
    return false;
  }

  /// EXDEV: a rename that would cross file systems.
  static const _crossDevice = 18;
}

/// A part of the work of a [Transfer]: of its [item]th source, from [from]
/// to [to].
sealed class _Work {
  _Work(this.item, this.from, this.to);

  final int item;
  final String from;
  final String to;

  int get cost => _entryCost;
}

final class _MakeDirectory extends _Work {
  _MakeDirectory(super.item, super.from, super.to);
}

final class _CopyFile extends _Work {
  _CopyFile(super.item, super.from, super.to, this.size);

  final int size;

  // open while it is copied
  RandomAccessFile? input;
  RandomAccessFile? output;

  @override
  int get cost => size + _entryCost;
}

final class _CopyLink extends _Work {
  _CopyLink(super.item, super.from, super.to);
}

final class _Rename extends _Work {
  _Rename(super.item, super.from, super.to);
}

/// Deletes [from] once it is copied, or once a directory's entries are
/// moved out of it (not [recursive]).
final class _Remove extends _Work {
  _Remove(int item, String from, {this.recursive = true})
    : super(item, from, from);

  final bool recursive;
}

/// What is at [path], a link not followed.
FileSystemEntity _entity(String path) =>
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      .directory => Directory(path),
      .link => Link(path),
      _ => File(path),
    };

/// The paths dragged from a pane.
final class _Paths {
  const _Paths(this.paths);

  final List<String> paths;
}

/// An entry of the table: a file or a directory, or `../`.
final class _Entry {
  const _Entry(
    this.path, {
    this.isDirectory = false,
    this.size = 0,
    this.modified,
  }) : isUp = false;

  /// `../`, for [path], the parent.
  const _Entry.up(this.path)
    : isDirectory = true,
      size = 0,
      modified = null,
      isUp = true;

  factory _Entry.of(FileSystemEntity entity) {
    final stat = entity.statSync();
    return _Entry(
      entity.path,
      isDirectory: stat.type == .directory,
      size: stat.size,
      modified: stat.modified,
    );
  }

  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final bool isUp;

  String get name => isUp ? '..' : _name(path);

  /// Its key in the table.
  String get key => isUp ? '..' : path;
}

final class _Browser extends StatefulWidget {
  const _Browser({required this.directory, required this.bytesPerFrame});

  final String directory;
  final int bytesPerFrame;

  @override
  State<_Browser> createState() => _BrowserState();
}

final class _BrowserState extends State<_Browser> {
  late final String _root = Directory(
    widget.directory,
  ).resolveSymbolicLinksSync();

  /// The table's directory.
  late String _directory = _root;

  late final _tree = TreeController(selectedKey: _root, expanded: [_root])
    ..addListener(_treeChanged);
  final _table = TableController();
  final _split = SplitController(fractions: [1, 2]);
  final _treeNode = FocusNode(debugLabel: 'tree');
  final _tableNode = FocusNode(debugLabel: 'files');
  var _settings = const Settings();

  // the rows of the table, the paths marked among them, and why the
  // directory could not be listed
  var _entries = const <_Entry>[];
  final _marked = <String>{};
  String? _error;

  // the directories in each directory listed for the tree, hidden or not
  final _subdirectories = <String, List<String>>{};

  // whether the tree was focused after the table
  var _treeActive = false;

  late final _drops = _Drops(accepts: _accepts, drop: _drop);

  @override
  void initState() {
    super.initState();
    _treeNode.addListener(_focusChanged);
    _tableNode.addListener(_focusChanged);
    _list();
    _table.selectedKey = _first;
  }

  @override
  void dispose() {
    _tree.dispose();
    _table.dispose();
    _split.dispose();
    _treeNode.dispose();
    _tableNode.dispose();
    super.dispose();
  }

  void _treeChanged() => setState(() {});

  void _focusChanged() {
    final tree = _treeNode.hasFocus || !_tableNode.hasFocus && _treeActive;
    if (tree != _treeActive) {
      setState(() => _treeActive = tree);
    }
  }

  /// Lists the table's directory.
  void _list() {
    final parent = _parent(_directory);
    final entries = [if (parent != null) _Entry.up(parent)];
    try {
      entries.addAll(
        [
          for (final e in Directory(_directory).listSync())
            if (_shows(e.path)) _Entry.of(e),
        ]..sort(_order),
      );
      _error = null;
    } on FileSystemException catch (e) {
      _error = 'cannot list: ${_message(e)}';
    }
    _entries = entries;
    _marked.retainAll({for (final e in entries) e.path});
  }

  int _order(_Entry a, _Entry b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    final by = switch (_settings.sortBy) {
      .name => 0,
      // a directory's size says nothing of what is in it
      .size => a.isDirectory ? 0 : b.size.compareTo(a.size),
      .modified => b.modified!.compareTo(a.modified!),
    };
    return by != 0 ? by : _byName(a.path, b.path);
  }

  bool _shows(String path) =>
      _settings.showHidden || !_name(path).startsWith('.');

  /// The directories in [path] the tree shows.
  List<String> _directories(String path) => [
    for (final d in _subdirectories[path] ??= _listDirectories(path))
      if (_shows(d)) d,
  ];

  static List<String> _listDirectories(String path) {
    try {
      return [
        for (final e in Directory(path).listSync())
          if (e is Directory) e.path,
      ]..sort(_byName);
    } on FileSystemException {
      return const [];
    }
  }

  /// The key of the first entry below `../`.
  String? get _first =>
      (_entries.where((e) => !e.isUp).firstOrNull ?? _entries.firstOrNull)?.key;

  _Entry? get _selected =>
      _entries.where((e) => e.key == _table.selectedKey).firstOrNull;

  /// The tree's directory.
  String get _treeDirectory => _tree.selectedKey as String? ?? _root;

  /// What F5 and F6 take from the pane focused last: the directory the
  /// tree selects, or the files marked in the table, or the one selected.
  List<String> get _sources {
    if (_treeActive) {
      return [_treeDirectory];
    }
    if (_marked.isNotEmpty) {
      return _markedPaths;
    }
    final selected = _selected;
    return selected == null || selected.isUp ? const [] : [selected.path];
  }

  /// The paths marked, in the order of the table.
  List<String> get _markedPaths => [
    for (final e in _entries)
      if (_marked.contains(e.path)) e.path,
  ];

  /// Whether [path] is the root of the tree or holds it, which stays
  /// where it is.
  bool _holdsRoot(String path) => _root == path || _isWithin(_root, path);

  /// Where F5 and F6 put them: in the other pane's directory.
  String get _target => _treeActive ? _directory : _treeDirectory;

  /// Shows [directory] in the table, [select] selected there, or the first
  /// entry.
  void _open(String directory, {String? select}) {
    setState(() {
      _directory = directory;
      _marked.clear();
      _list();
    });
    _table.selectedKey = select ?? _first;
  }

  void _up() {
    final parent = _parent(_directory);
    if (parent != null) {
      _open(parent, select: _directory);
    }
  }

  void _activate(_Entry entry) {
    if (entry.isUp) {
      _up();
    } else if (entry.isDirectory) {
      _open(entry.path);
    }
  }

  /// Marks the entry selected, or unmarks it, and selects the next.
  void _mark() {
    final selected = _selected;
    if (selected == null) {
      return;
    }
    if (!selected.isUp) {
      setState(() {
        if (!_marked.remove(selected.path)) {
          _marked.add(selected.path);
        }
      });
    }
    final next = _entries.indexOf(selected) + 1;
    if (next < _entries.length) {
      _table.selectedKey = _entries[next].key;
    }
  }

  /// Lists again what may have changed on the file system: the panes'
  /// directories, or the nearest above them that are there.
  void _refresh() {
    final at = _entries.indexWhere((e) => e.key == _table.selectedKey);
    setState(() {
      _subdirectories.clear();
      while (!FileSystemEntity.isDirectorySync(_directory)) {
        _directory = _parent(_directory) ?? _root;
      }
      _list();
    });
    var selected = _treeDirectory;
    while (selected != _root && !FileSystemEntity.isDirectorySync(selected)) {
      selected = _parent(selected) ?? _root;
    }
    _tree.selectedKey = selected;
    if (_selected == null) {
      // the row that took its place
      _table.selectedKey = at < 0 || _entries.isEmpty
          ? _first
          : _entries[min(at, _entries.length - 1)].key;
    }
  }

  void _setSettings(Settings settings) {
    setState(() {
      _settings = settings;
      _list();
    });
    if (_selected == null) {
      _table.selectedKey = _first;
    }
  }

  void _toggleHidden() =>
      _setSettings(_settings.copyWith(showHidden: !_settings.showHidden));

  void _sortBy(SortBy by) => _setSettings(_settings.copyWith(sortBy: by));

  void _quit() => AppBinding.of(context).quit();

  void _copy() => unawaited(_transfer(_sources, _target, .copy));

  void _move() => unawaited(_transfer(_sources, _target, .move));

  void _rename() => unawaited(_renameSelected());

  void _makeDirectory() => unawaited(_makeDirectoryIn());

  void _openSettings() => unawaited(_editSettings());

  /// Copies or moves [sources] into [target] as [operation] says, asking
  /// first where the settings say so; a drop, with [operation] null,
  /// always asks, and which.
  Future<void> _transfer(
    List<String> sources,
    String target,
    Operation? operation,
  ) async {
    if (sources.isEmpty) {
      showToast(context, 'Nothing is selected.');
      return;
    }
    var (op, to) = (operation ?? Operation.copy, target);
    if (operation == null || _settings.confirm) {
      final answer = await showDialog<(Operation, String)>(
        context,
        (_) => _TransferDialog(
          sources: sources,
          target: target,
          base: _directory,
          operation: operation,
        ),
      );
      if (answer == null || !mounted) {
        return;
      }
      (op, to) = answer;
    } else if (_refusal(sources, to) case final refusal?) {
      showToast(context, refusal);
      return;
    }
    if (op == .move && sources.any(_holdsRoot)) {
      showToast(context, _rootStays);
      return;
    }
    final Transfer transfer;
    try {
      transfer = Transfer(op, sources, to);
    } on FileSystemException catch (e) {
      showToast(context, '${op.label} failed: ${_message(e)}');
      return;
    }
    final error = await showDialog<String>(
      context,
      (_) => _Progress(transfer, bytesPerFrame: widget.bytesPerFrame),
      dismissible: false,
    );
    if (!mounted) {
      return;
    }
    _marked.clear();
    _refresh();
    final what = _describe(sources);
    showToast(
      context,
      error != null
          ? '${op.label} failed: $error'
          : transfer.isCancelled
          ? 'Cancelled: ${transfer.items} of ${sources.length} '
                '${op.past}.'
          : '${op.done} $what to ${_name(to)}.',
    );
  }

  /// Renames what is selected in the pane focused last.
  Future<void> _renameSelected() async {
    final selected = _selected;
    final path = _treeActive
        ? _treeDirectory
        : selected == null || selected.isUp
        ? null
        : selected.path;
    if (path == null || _holdsRoot(path)) {
      showToast(context, path == null ? 'Nothing is selected.' : _rootStays);
      return;
    }
    final directory = _parent(path)!;
    final name = await showDialog<String>(
      context,
      (_) => _NameDialog(
        title: 'Rename',
        action: 'Rename',
        directory: directory,
        initial: _name(path),
      ),
    );
    if (name == null || name == _name(path) || !mounted) {
      return;
    }
    final to = _join(directory, name);
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        Directory(path).renameSync(to);
      } else {
        File(path).renameSync(to);
      }
    } on FileSystemException catch (e) {
      showToast(context, 'Rename failed: ${_message(e)}');
      return;
    }
    if (_directory == path || _isWithin(_directory, path)) {
      _directory = to + _directory.substring(path.length);
    }
    if (_treeActive) {
      _tree.selectedKey = to;
    }
    _refresh();
    if (!_treeActive) {
      _table.selectedKey = to;
    }
  }

  /// Makes a directory in that of the pane focused last.
  Future<void> _makeDirectoryIn() async {
    final directory = _treeActive ? _treeDirectory : _directory;
    final name = await showDialog<String>(
      context,
      (_) => _NameDialog(
        title: 'New directory',
        action: 'Create',
        directory: directory,
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    final path = _join(directory, name);
    try {
      Directory(path).createSync();
    } on FileSystemException catch (e) {
      showToast(context, 'Making the directory failed: ${_message(e)}');
      return;
    }
    _refresh();
    if (_treeActive) {
      _tree
        ..expand(directory)
        ..selectedKey = path;
    } else {
      _table.selectedKey = path;
    }
  }

  Future<void> _editSettings() async {
    final settings = await Navigator.of(
      context,
    ).push(PageRoute<Settings>(builder: (_) => _SettingsScreen(_settings)));
    if (settings != null && mounted) {
      _setSettings(settings);
    }
  }

  /// Whether [paths] dropped on [directory] can go there.
  bool _accepts(_Paths paths, String directory) =>
      _refusal(paths.paths, directory) == null;

  void _drop(_Paths paths, String directory) =>
      unawaited(_transfer(paths.paths, directory, null));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CommandPalette(
      commands: [
        Command('Copy…', onSelected: _copy),
        Command('Move…', onSelected: _move),
        Command('Rename…', onSelected: _rename),
        Command('New directory…', onSelected: _makeDirectory),
        Command('Settings…', onSelected: _openSettings),
        Command(
          _settings.showHidden ? 'Hide hidden files' : 'Show hidden files',
          onSelected: _toggleHidden,
        ),
        for (final by in SortBy.values)
          Command('Sort by ${by.name}', onSelected: () => _sortBy(by)),
        Command('Refresh', onSelected: _refresh),
        Command('Quit', onSelected: _quit),
      ],
      child: KeyBindings(
        {
          'f2': _rename,
          'f5': _copy,
          'f6': _move,
          'f7': _makeDirectory,
          'f9': _openSettings,
          'ctrl+r': _refresh,
          'ctrl+q': _quit,
        },
        hints: const {
          'f2': 'rename',
          'f5': 'copy',
          'f6': 'move',
          'f7': 'mkdir',
          'f9': 'settings',
          'ctrl+q': 'quit',
        },
        child: MenuBar(
          menus: [
            Menu(
              '&File',
              items: [
                MenuItem('&Copy…', onSelected: _copy),
                MenuItem('&Move…', onSelected: _move),
                MenuItem('&Rename…', onSelected: _rename),
                MenuItem('&New directory…', onSelected: _makeDirectory),
                const MenuDivider(),
                MenuItem('&Quit', onSelected: _quit),
              ],
            ),
            Menu(
              '&View',
              items: [
                for (final by in SortBy.values)
                  MenuItem(
                    'Sort by &${by.name}',
                    checked: _settings.sortBy == by,
                    onSelected: () => _sortBy(by),
                  ),
                const MenuDivider(),
                MenuItem(
                  'Show &hidden files',
                  checked: _settings.showHidden,
                  onSelected: _toggleHidden,
                ),
                MenuItem('R&efresh', onSelected: _refresh),
              ],
            ),
            Menu(
              '&Options',
              items: [MenuItem('&Settings…', onSelected: _openSettings)],
            ),
          ],
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Expanded(
                child: SplitView(
                  controller: _split,
                  shareEdges: true,
                  panes: [
                    SplitPane(
                      minSize: 12,
                      collapsible: true,
                      child: _TreePane(
                        root: _root,
                        directories: _directories,
                        controller: _tree,
                        focusNode: _treeNode,
                        showGuides: _settings.showGuides,
                        active: _treeActive,
                        onOpen: _open,
                        drops: _drops,
                      ),
                    ),
                    SplitPane(
                      minSize: 30,
                      child: _TablePane(
                        directory: _directory,
                        entries: _entries,
                        marked: _marked,
                        markedPaths: _markedPaths,
                        controller: _table,
                        focusNode: _tableNode,
                        active: !_treeActive,
                        onMark: _mark,
                        onUp: _up,
                        onActivated: _activate,
                        drops: _drops,
                      ),
                    ),
                  ],
                ),
              ),
              // the counts keep their room, the paths are cut short
              StatusBar(
                left: Text(
                  _error != null ? ' $_error' : ' to $_target',
                  style: _error != null ? theme.error : theme.muted,
                  wrap: .none,
                  overflow: .ellipsis,
                ),
                right: Text('${_summary()} '),
              ),
              const KeyHintsBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// How many entries the table has, and those marked.
  String _summary() {
    final count = _entries.where((e) => !e.isUp).length;
    final marked = _entries.where((e) => _marked.contains(e.path));
    final bytes = marked.fold(
      0,
      (sum, e) => sum + (e.isDirectory ? 0 : e.size),
    );
    return [
      _count(count, 'entry', 'entries'),
      if (marked.isNotEmpty) '${marked.length} marked',
      if (bytes > 0) _size(bytes),
    ].join(', ');
  }
}

/// Where dragged paths may go, and what dropping them there does.
final class _Drops {
  const _Drops({required this.accepts, required this.drop});

  /// Whether the paths dragged can go to the directory.
  final bool Function(_Paths paths, String directory) accepts;

  /// Copies or moves the paths dropped to the directory.
  final void Function(_Paths paths, String directory) drop;
}

/// A border of a pane: the theme's primary color while [active].
Border _border(ThemeData theme, {required bool active}) =>
    Border.all(style: active ? theme.primary : theme.border, merge: true);

/// The style of what dragged paths would drop on.
Style _dropStyle(ThemeData theme) =>
    theme.primary.merge(const Style(attrs: Attr.reverse));

/// What [builder] builds, which takes the paths [drops] lets go to
/// [directory]; `hovered` while some are dragged over it.
final class _DropTarget extends StatelessWidget {
  const _DropTarget({
    required this.directory,
    required this.drops,
    required this.builder,
  });

  final String directory;
  final _Drops drops;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  Widget build(BuildContext context) => DragTarget<_Paths>(
    onWillAccept: (details) => drops.accepts(details.data, directory),
    onAccept: (details) => drops.drop(details.data, directory),
    builder: (context, candidate, _) => builder(context, candidate != null),
  );
}

/// What follows the mouse while [paths] are dragged.
final class _DragFeedback extends StatelessWidget {
  const _DragFeedback(this.paths);

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      ' ${_describe(paths)} ',
      style: theme.selection.merge(theme.text),
    );
  }
}

/// The tree of the directories under [root], each of which drags itself
/// and takes what is dropped on it; its border primary while [active].
final class _TreePane extends StatelessWidget {
  const _TreePane({
    required this.root,
    required this.directories,
    required this.controller,
    required this.focusNode,
    required this.showGuides,
    required this.active,
    required this.onOpen,
    required this.drops,
  });

  final String root;
  final List<String> Function(String path) directories;
  final TreeController controller;
  final FocusNode focusNode;
  final bool showGuides;
  final bool active;
  final void Function(String directory) onOpen;
  final _Drops drops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Box(
      border: _border(theme, active: active),
      titles: [BorderTitle(' Tree ', style: theme.text)],
      child: TreeView<String>(
        roots: [root],
        children: directories,
        controller: controller,
        focusNode: focusNode,
        showGuides: showGuides,
        onActivated: onOpen,
        label: (context, entry) {
          final path = entry.node;
          return _DropTarget(
            directory: path,
            drops: drops,
            builder: (context, hovered) => Draggable<_Paths>(
              data: _Paths([path]),
              feedback: _DragFeedback([path]),
              child: Text(
                '${_name(path)}$_separator',
                style: hovered ? _dropStyle(theme) : const Style(),
                wrap: .none,
                overflow: .ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The [entries] of [directory] in a table, which takes what is dropped
/// on it; its border primary while [active] or while something is dragged
/// over it. Space and Insert call [onMark], Backspace [onUp].
final class _TablePane extends StatelessWidget {
  const _TablePane({
    required this.directory,
    required this.entries,
    required this.marked,
    required this.markedPaths,
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.onMark,
    required this.onUp,
    required this.onActivated,
    required this.drops,
  });

  final String directory;
  final List<_Entry> entries;

  /// The paths marked, and what dragging one of them drags.
  final Set<String> marked;
  final List<String> markedPaths;

  final TableController controller;
  final FocusNode focusNode;
  final bool active;
  final VoidCallback onMark;
  final VoidCallback onUp;
  final void Function(_Entry entry) onActivated;
  final _Drops drops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DropTarget(
      directory: directory,
      drops: drops,
      builder: (context, hovered) => Box(
        border: _border(theme, active: hovered || active),
        titles: [BorderTitle(' $directory ', style: theme.text)],
        child: KeyBindings(
          {'space': onMark, 'insert': onMark, 'backspace': onUp},
          hints: const {'space': 'mark', 'backspace': 'up'},
          child: Table<_Entry>(
            rows: entries,
            columns: [
              TableColumn(
                title: 'Name',
                width: const .fr(1),
                cell: (e) => TableCell.widget(
                  _NameCell(
                    entry: e,
                    marked: marked.contains(e.path),
                    dragged: marked.contains(e.path) ? markedPaths : [e.path],
                    drops: drops,
                  ),
                ),
              ),
              TableColumn(
                title: 'Size',
                align: .right,
                cell: (e) => TableCell(
                  e.isUp
                      ? 'up'
                      : e.isDirectory
                      ? 'dir'
                      // a link to nothing
                      : e.size < 0
                      ? '?'
                      : _size(e.size),
                ),
              ),
              TableColumn(
                title: 'Modified',
                cell: (e) => TableCell(_time(e.modified)),
              ),
            ],
            rowKey: (e) => e.key,
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            onActivated: onActivated,
          ),
        ),
      ),
    );
  }
}

/// The name of [entry] in the table, which drags [dragged] (it, or the
/// files marked with it, as [marked] says); a directory takes what is
/// dropped on it.
final class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.entry,
    required this.marked,
    required this.dragged,
    required this.drops,
  });

  final _Entry entry;
  final bool marked;
  final List<String> dragged;
  final _Drops drops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var style = entry.isDirectory
        ? const Style(attrs: Attr.bold)
        : const Style();
    if (marked) {
      style = style.merge(theme.warning);
    }
    Widget name(Style over) {
      final text = Text(
        entry.isDirectory ? '${entry.name}$_separator' : entry.name,
        style: style.merge(over),
        wrap: .none,
        overflow: .ellipsis,
      );
      return entry.isUp
          ? text
          : Draggable<_Paths>(
              data: _Paths(dragged),
              feedback: _DragFeedback(dragged),
              child: text,
            );
    }

    if (!entry.isDirectory) {
      return name(const Style());
    }
    return _DropTarget(
      directory: entry.path,
      drops: drops,
      builder: (context, hovered) =>
          name(hovered ? _dropStyle(theme) : const Style()),
    );
  }
}

/// Asks where to copy or move [sources], [target] in a field, which a
/// path relative to [base] may name; [operation] null asks which too. It
/// closes with what to do and the directory.
final class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    required this.sources,
    required this.target,
    required this.base,
    this.operation,
  });

  final List<String> sources;
  final String target;
  final String base;
  final Operation? operation;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

final class _TransferDialogState extends State<_TransferDialog> {
  final _form = GlobalKey<FormState>();
  late Operation _chosen = widget.operation ?? .copy;
  late String _typed = widget.target;
  var _to = '';

  /// The directory [text] names, its links resolved; null for none.
  String? _directory(String text) {
    final path = File(text).isAbsolute ? text : _join(widget.base, text);
    return text.trim().isNotEmpty && FileSystemEntity.isDirectorySync(path)
        ? Directory(path).resolveSymbolicLinksSync()
        : null;
  }

  String? _validate(String? text) {
    if (text!.trim().isEmpty) {
      return 'Where to?';
    }
    final directory = _directory(text);
    return directory == null
        ? 'No such directory.'
        : _refusal(widget.sources, directory);
  }

  /// What the sources replace in the directory typed: those of them with
  /// the name of an entry there.
  String? _replacing() {
    final directory = _directory(_typed);
    final sources = widget.sources;
    if (directory == null || _refusal(sources, directory) != null) {
      return null;
    }
    final there = sources.where(
      (s) =>
          FileSystemEntity.typeSync(
            _join(directory, _name(s)),
            followLinks: false,
          ) !=
          .notFound,
    );
    return switch (there.length) {
      0 => null,
      _ when sources.length == 1 =>
        '${_name(sources.single)} is there already: it is replaced.',
      1 => '1 of them is there already: it is replaced.',
      final n => '$n of them are there already: they are replaced.',
    };
  }

  void _submit(Operation operation) {
    _chosen = operation;
    _form.currentState!.submit();
  }

  @override
  Widget build(BuildContext context) {
    final operation = widget.operation;
    final what = _describe(widget.sources);
    return Dialog(
      title: operation?.label ?? 'Copy or move',
      child: SizedBox(
        width: 56,
        child: Form(
          key: _form,
          onSubmitted: () => closeDialog(context, (_chosen, _to)),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text('${operation?.label ?? 'Copy or move'} $what to'),
              TextFormField(
                initialValue: widget.target,
                semanticsLabel: 'Destination',
                validator: _validate,
                onSaved: (text) => _to = _directory(text!)!,
                onChanged: (text) => setState(() => _typed = text),
                autofocus: true,
              ),
              if (_replacing() case final replacing?)
                Text(replacing, style: Theme.of(context).warning),
              Row(
                mainAxisSize: .min,
                gap: 2,
                children: [
                  for (final op
                      in operation == null ? Operation.values : [operation])
                    Button(op.label, onPressed: () => _submit(op)),
                  Button('Cancel', onPressed: () => closeDialog(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies or moves with [transfer], [bytesPerFrame] bytes of it a frame,
/// its progress in a bar; closes once it is done, or cancelled, or with
/// the message of the error that stopped it.
final class _Progress extends StatefulWidget {
  const _Progress(this.transfer, {required this.bytesPerFrame});

  final Transfer transfer;
  final int bytesPerFrame;

  @override
  State<_Progress> createState() => _ProgressState();
}

final class _ProgressState extends State<_Progress>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _step());

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    widget.transfer.cancel();
    super.dispose();
  }

  void _step() {
    final transfer = widget.transfer;
    String? error;
    try {
      if (transfer.step(widget.bytesPerFrame)) {
        setState(() {});
        return;
      }
    } on FileSystemException catch (e) {
      error = _message(e);
      transfer.cancel();
    }
    _ticker.stop();
    closeDialog(context, error);
  }

  void _cancel() {
    widget.transfer.cancel();
    _ticker.stop();
    closeDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transfer;
    final percent = (t.progress * 100).floor();
    return KeyBindings(
      {'escape': _cancel},
      hints: const {'escape': 'cancel'},
      child: Dialog(
        title: t.operation.doing,
        child: SizedBox(
          width: 48,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text(_name(t.current), wrap: .none, overflow: .ellipsis),
              Row(
                gap: 1,
                children: [
                  Expanded(child: ProgressBar(value: t.progress)),
                  SizedBox(width: 4, child: Text('$percent%', align: .right)),
                ],
              ),
              Text(
                '${t.items} of ${t.sources.length} done'
                '${t.totalBytes == 0 ? '' : ', ${_size(t.bytes)} of '
                          '${_size(t.totalBytes)}'}',
              ),
              const SizedBox(height: 1),
              Button('Cancel', autofocus: true, onPressed: _cancel),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a name for an entry of [directory], [initial] at first; it
/// closes with the name, once it is one no other entry there has.
final class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.action,
    required this.directory,
    this.initial = '',
  });

  final String title;

  /// What the button that takes the name says.
  final String action;

  final String directory;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

final class _NameDialogState extends State<_NameDialog> {
  final _form = GlobalKey<FormState>();
  var _name = '';

  String? _validate(String? text) {
    final name = text!;
    if (name.isEmpty) {
      return 'A name, please.';
    }
    if (name.contains('/') || name.contains(_separator)) {
      return 'A name has no $_separator.';
    }
    if (name == '.' || name == '..') {
      return 'That is no name for an entry.';
    }
    if (name != widget.initial &&
        FileSystemEntity.typeSync(
              _join(widget.directory, name),
              followLinks: false,
            ) !=
            .notFound) {
      return '$name is there already.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => Dialog(
    title: widget.title,
    child: SizedBox(
      width: 40,
      child: Form(
        key: _form,
        onSubmitted: () => closeDialog(context, _name),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            TextFormField(
              initialValue: widget.initial,
              placeholder: 'name',
              validator: _validate,
              onSaved: (text) => _name = text!,
              autofocus: true,
            ),
            Row(
              mainAxisSize: .min,
              gap: 2,
              children: [
                Button(
                  widget.action,
                  onPressed: () => _form.currentState!.submit(),
                ),
                Button('Cancel', onPressed: () => closeDialog(context)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// The settings, on a screen of their own: saved, they are what the
/// route pops with.
final class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen(this.settings);

  final Settings settings;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

final class _SettingsScreenState extends State<_SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late Settings _edited = widget.settings;

  void _save() => _form.currentState!.submit();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.settings;
    return KeyBindings(
      {'ctrl+s': _save},
      hints: const {'ctrl+s': 'save'},
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: Box(
              border: .all(type: .rounded, style: theme.border),
              titles: [BorderTitle(' Settings ', style: theme.text)],
              padding: const .x(1),
              child: Form(
                key: _form,
                onSubmitted: () => Navigator.of(context).pop(_edited),
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    FormField<bool>(
                      initialValue: s.showHidden,
                      onSaved: (v) => _edited = _edited.copyWith(showHidden: v),
                      builder: (field) => Checkbox(
                        value: field.value!,
                        label: 'show hidden files',
                        onChanged: field.didChange,
                        autofocus: true,
                      ),
                    ),
                    FormField<bool>(
                      initialValue: s.showGuides,
                      onSaved: (v) => _edited = _edited.copyWith(showGuides: v),
                      builder: (field) => Checkbox(
                        value: field.value!,
                        label: 'show the lines of the tree',
                        onChanged: field.didChange,
                      ),
                    ),
                    FormField<bool>(
                      initialValue: s.confirm,
                      onSaved: (v) => _edited = _edited.copyWith(confirm: v),
                      builder: (field) => Switch(
                        value: field.value!,
                        label: 'ask before copying and moving',
                        onChanged: field.didChange,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text('Sort the files by'),
                    FormField<SortBy>(
                      initialValue: s.sortBy,
                      onSaved: (v) => _edited = _edited.copyWith(sortBy: v),
                      builder: (field) => RadioGroup<SortBy>(
                        choices: [
                          for (final by in SortBy.values) Choice(by, by.name),
                        ],
                        value: field.value,
                        direction: .horizontal,
                        onChanged: field.didChange,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: .min,
                      gap: 2,
                      children: [
                        Button('Save', onPressed: _save),
                        Button(
                          'Cancel',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const KeyHintsBar(),
        ],
      ),
    );
  }
}

const _rootStays = 'The root of the tree stays where it is.';

/// Why [sources] cannot be copied or moved into [directory]; null when
/// they can.
String? _refusal(List<String> sources, String directory) {
  for (final source in sources) {
    if (_parent(source) == directory) {
      return '${_name(source)} is there already.';
    }
    if (directory == source || _isWithin(directory, source)) {
      return '${_name(source)} cannot go into itself.';
    }
  }
  return null;
}

/// `notes.txt`, or `3 entries`.
String _describe(List<String> paths) =>
    paths.length == 1 ? _name(paths.single) : '${paths.length} entries';

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String _message(FileSystemException e) =>
    '${e.osError?.message ?? e.message}: ${e.path}';

int _byName(String a, String b) {
  final byCase = _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
  return byCase != 0 ? byCase : a.compareTo(b);
}

/// `\` on Windows, `/` elsewhere: between the names of a path, and after
/// a directory's.
final String _separator = Platform.pathSeparator;

/// The index of the last separator in [path]: `/`, and on Windows `\`
/// too; -1 for none.
int _lastSeparator(String path) => Platform.isWindows
    ? max(path.lastIndexOf('/'), path.lastIndexOf(r'\'))
    : path.lastIndexOf('/');

/// The last part of [path]; a root's is the root (`/`, `C:\`).
String _name(String path) {
  final i = _lastSeparator(path);
  return i < 0 || i == path.length - 1 ? path : path.substring(i + 1);
}

/// The directory [path] is in; null for a root.
String? _parent(String path) {
  final parent = FileSystemEntity.parentOf(path);
  return parent == path ? null : parent;
}

String _join(String directory, String name) => directory.endsWith(_separator)
    ? '$directory$name'
    : '$directory$_separator$name';

/// Whether [path] is below [directory].
bool _isWithin(String path, String directory) => path.startsWith(
  directory.endsWith(_separator) ? directory : '$directory$_separator',
);

/// [bytes] as `512`, `2.9K`, `14M`.
String _size(int bytes) {
  if (bytes < 1024) {
    return '$bytes';
  }
  var n = bytes / 1024;
  for (final unit in ['K', 'M', 'G']) {
    if (n < 1024) {
      return '${n < 10 ? n.toStringAsFixed(1) : n.round()}$unit';
    }
    n /= 1024;
  }
  return '${n < 10 ? n.toStringAsFixed(1) : n.round()}T';
}

String _time(DateTime? t) {
  if (t == null) {
    return '';
  }
  String two(int n) => '$n'.padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
