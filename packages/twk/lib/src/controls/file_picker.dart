/// Files and directories picked from the file system: a [FilePicker], which
/// [showFilePicker] shows in a dialog, and the [FileFilter]s it lists files
/// by.
library;

import 'dart:async';
import 'dart:convert' show utf8;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show Attr, CrossAxisAlignment, TextOverflow, TextWrap;

import '../editing/autocomplete.dart';
import '../editing/text_editing.dart';
import '../editing/text_field.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../overlay/dialog.dart';
import '../platform/paths.dart';
import '../platform/platform.dart' hide currentDirectory, kindOf;
import '../platform/platform.dart' as platform show currentDirectory, kindOf;
import '../scroll/list_view.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'button.dart';
import 'choice.dart';
import 'field_styles.dart';
import 'pressable.dart';
import 'select.dart';
import 'toggle.dart';

export '../platform/platform.dart' show DirectoryEntry, FileKind;

// Examples can assume:
// late BuildContext context;

/// What a [FilePicker] picks.
enum FilePickerMode {
  /// Files that are there: one, or with `multiple` any number.
  open,

  /// A file to write: one that is there, or a name in a directory that is.
  save,

  /// A directory that is there.
  directory,
}

/// A choice of which files a [FilePicker] lists: those whose names end in
/// a dot and one of [extensions], in any case.
///
/// `dart` lists `main.dart` and `OLD.DART`; with no extensions, every file
/// is listed. [label] names it in the picker's choice of filters.
///
/// ```dart
/// const filters = [
///   FileFilter('Dart', ['dart']),
///   FileFilter('Images', ['png', 'jpg']),
///   FileFilter('All files'),
/// ];
/// ```
@immutable
final class FileFilter {
  /// A filter named [label] of the files with one of [extensions]; every
  /// file without them.
  const FileFilter(this.label, [this.extensions = const []]);

  /// What the picker's choice of filters shows for it.
  final String label;

  /// The extensions, without their dots.
  final List<String> extensions;

  /// Whether the file named [name] is listed.
  bool accepts(String name) {
    if (extensions.isEmpty) {
      return true;
    }
    final lower = name.toLowerCase();
    return extensions.any((e) => lower.endsWith('.${e.toLowerCase()}'));
  }
}

/// What a [FilePicker] and a `DirectoryTree` read of a file system: the
/// working directory, the home directory, what a directory holds and what
/// is at a path; for a `DirectoryTree` also what a file holds, its size and
/// when a directory changes. The machine's is [local];
/// [PickerFileSystem.memory] is a tree of the app's own, for a test, a
/// demo or files that are elsewhere, which no disk is read for. Paths are
/// absolute, in the platform's form (`/` or on Windows a drive's or a
/// share's root first, its separator between the names).
///
/// One of an app's own extends it, as the members [read], [sizeOf] and
/// [watch] have a body that reads nothing: no file reads, no size is
/// known, and no directory says it changed.
abstract class PickerFileSystem {
  /// A file system for a subclass to build on.
  const PickerFileSystem();

  /// A tree of [paths], each absolute: a file, or a directory where it
  /// ends in a separator, and every directory above one is a directory.
  /// [currentDirectory] is where a relative path is (the root by default)
  /// and [homeDirectory] the one `~` names, none by default; neither need
  /// be in [paths]. A directory lists its entries in the order the paths
  /// first named them; one that is not there fails to list. See
  /// [InMemoryFileSystem], which this is, for the texts of its files and
  /// the changes it is told of.
  factory PickerFileSystem.memory(
    Iterable<String> paths, {
    String? currentDirectory,
    String? homeDirectory,
  }) = InMemoryFileSystem;

  /// The machine's, through dart:io: its working directory, its `HOME`
  /// (`USERPROFILE` on Windows). On the web, which has none, no directory
  /// lists, no file reads, nothing is at a path and no directory changes.
  static const PickerFileSystem local = _LocalFileSystem();

  /// Where a relative path is.
  String get currentDirectory;

  /// The directory `~` at the start of a path names; null for none, and
  /// `~` is then a name as any other.
  String? get homeDirectory;

  /// The entries of [directory], in any order, or the error listing it
  /// fails with; a link to a directory is a directory.
  Stream<DirectoryEntry> list(String directory);

  /// What is at [path], links followed.
  FileKind kindOf(String path);

  /// The text of [file], as UTF-8, or the error reading it fails with: by
  /// default an [UnsupportedError].
  Future<String> read(String file) =>
      Future.error(UnsupportedError('no file reads here'));

  /// The size of [file] in bytes; null where it is not known, as by
  /// default.
  Future<int?> sizeOf(String file) async => null;

  /// An event each time the entries of [directory] change: one is made,
  /// removed, renamed or written to. Several may come of one change, and
  /// none of a change below its entries. The stream may end, or fail,
  /// where the directory cannot be watched; by default it ends at once.
  Stream<void> watch(String directory) => const Stream.empty();
}

final class _LocalFileSystem extends PickerFileSystem {
  const _LocalFileSystem();

  @override
  String get currentDirectory => platform.currentDirectory;

  @override
  String? get homeDirectory => environment[isWindows ? 'USERPROFILE' : 'HOME'];

  @override
  Stream<DirectoryEntry> list(String directory) => listDirectory(directory);

  @override
  FileKind kindOf(String path) => platform.kindOf(path);

  @override
  Future<String> read(String file) => readFile(file);

  @override
  Future<int?> sizeOf(String file) => fileSize(file);

  @override
  Stream<void> watch(String directory) => watchDirectory(directory);
}

/// A [PickerFileSystem] kept in memory, which no disk is read for: a tree
/// of directories and files, the files' texts, and the directories that
/// fail to list. [add], [write] and [remove] change it, and tell those who
/// [watch] a directory whose entries they change.
///
/// A tree for a test, which the test then changes:
///
/// ```dart
/// final files = InMemoryFileSystem(
///   ['/app/lib/', '/app/README.md'],
///   contents: {'/app/.gitignore': 'build/\n'},
/// );
/// files
///   ..write('/app/lib/main.dart', 'void main() {}')
///   ..remove('/app/README.md');
/// ```
final class InMemoryFileSystem extends PickerFileSystem {
  /// A tree of [paths], as [PickerFileSystem.memory] makes one, with the
  /// files of [contents] holding their texts, and the directories of
  /// [unreadable], which fail to list, as a directory without the right to
  /// read it does.
  InMemoryFileSystem(
    Iterable<String> paths, {
    String? currentDirectory,
    this.homeDirectory,
    Map<String, String> contents = const {},
    Iterable<String> unreadable = const [],
  }) : currentDirectory =
           currentDirectory ?? rootOf(paths.firstOrNull ?? '') ?? _sep {
    for (final path in paths) {
      _add(path);
    }
    for (final MapEntry(key: path, value: text) in contents.entries) {
      _add(path);
      _texts[_full(path)] = text;
    }
    for (final path in unreadable) {
      _add(path.endsWith(_sep) ? path : '$path$_sep');
      _unreadable.add(_full(path));
    }
  }

  @override
  final String currentDirectory;

  @override
  final String? homeDirectory;

  // each directory's entries by name, true for a directory
  final _directories = <String, Map<String, bool>>{};
  // the texts of the files written
  final _texts = <String, String>{};
  final _unreadable = <String>{};
  final _watchers = <String, StreamController<void>>{};

  String _full(String path) => resolvePath(_sep, path, null);

  Map<String, bool> _directory(String path) =>
      _directories.putIfAbsent(path, () => {});

  /// Adds [path], a directory where it ends in a separator, and the
  /// directories above it; the directories whose entries that changed.
  List<String> _add(String path) {
    final changed = <String>[];
    final full = _full(path);
    _directory(rootOf(full) ?? _sep);
    var at = full;
    var isDirectory = isSeparator(path.codeUnitAt(path.length - 1));
    while (parentOf(at) != at) {
      final parent = parentOf(at);
      final entries = _directory(parent);
      final name = baseName(at);
      if (entries[name] != isDirectory) {
        entries[name] = isDirectory;
        changed.add(parent);
      }
      if (isDirectory) {
        _directory(at);
      }
      at = parent;
      isDirectory = true;
    }
    return changed;
  }

  void _tell(Iterable<String> directories) {
    for (final directory in directories) {
      _watchers[directory]?.add(null);
    }
  }

  /// Adds [path], a file, or a directory where it ends in a separator, as
  /// the paths of the constructor are, and the directories above it.
  void add(String path) => _tell(_add(path));

  /// Puts [text] in [file], made where it is not there, with the
  /// directories above it.
  void write(String file, String text) {
    final changed = _add(file);
    final full = _full(file);
    _texts[full] = text;
    _tell({...changed, parentOf(full)});
  }

  /// Takes [path] away, and everything below it; nothing where nothing is
  /// there. Those who watch a directory taken away see their stream end.
  void remove(String path) {
    final full = _full(path);
    final parent = parentOf(full);
    final entries = _directories[parent];
    final name = baseName(full);
    if (parent == full || entries == null || !entries.containsKey(name)) {
      return;
    }
    entries.remove(name);
    bool gone(String p) => p == full || isWithin(full, p);
    _directories.removeWhere((p, _) => gone(p));
    _texts.removeWhere((p, _) => gone(p));
    _unreadable.removeWhere(gone);
    for (final p in [..._watchers.keys.where(gone)]) {
      unawaited(_watchers.remove(p)!.close());
    }
    _tell([parent]);
  }

  @override
  Stream<DirectoryEntry> list(String directory) {
    final dir = _full(directory);
    if (_unreadable.contains(dir)) {
      return Stream.error(const _Denied());
    }
    final entries = _directories[dir];
    if (entries == null) {
      return Stream.error(const _NoDirectory());
    }
    return Stream.fromIterable([
      for (final MapEntry(key: name, value: isDirectory) in entries.entries)
        (path: joinPath(dir, name), isDirectory: isDirectory),
    ]);
  }

  @override
  FileKind kindOf(String path) {
    final full = _full(path);
    if (_directories.containsKey(full)) {
      return FileKind.directory;
    }
    return _directories[parentOf(full)]?[baseName(full)] == false
        ? FileKind.file
        : FileKind.none;
  }

  /// The text written to [file], empty for one that was only named; a
  /// path that is no file fails.
  @override
  Future<String> read(String file) async {
    if (kindOf(file) != FileKind.file) {
      throw const _NoFile();
    }
    return _texts[_full(file)] ?? '';
  }

  /// The UTF-8 length of the text of [file]; null for a path that is no
  /// file.
  @override
  Future<int?> sizeOf(String file) async => kindOf(file) == FileKind.file
      ? utf8.encode(_texts[_full(file)] ?? '').length
      : null;

  /// An event each time [add], [write] or [remove] changes the entries of
  /// [directory] or writes to a file in it; it ends once the directory is
  /// taken away.
  @override
  Stream<void> watch(String directory) =>
      (_watchers[_full(directory)] ??= StreamController<void>.broadcast())
          .stream;
}

/// What a directory of a [PickerFileSystem.memory] that is not there
/// fails to list with.
final class _NoDirectory implements Exception {
  const _NoDirectory();

  @override
  String toString() => 'no such directory';
}

/// What a directory of an [InMemoryFileSystem] that is unreadable fails to
/// list with.
final class _Denied implements Exception {
  const _Denied();

  @override
  String toString() => 'permission denied';
}

/// What a path of an [InMemoryFileSystem] that is no file fails to read
/// with.
final class _NoFile implements Exception {
  const _NoFile();

  @override
  String toString() => 'no such file';
}

/// Reads and moves what a [FilePicker] shows from outside: given to it as
/// its `controller`, the [directory] listed, the entry [highlighted] and
/// the files [selected].
///
/// [goTo] shows another directory and [refresh] lists it again. Its
/// listeners are told as any of the three changes, by the controller or
/// by the picker's keys and mouse. One picker at a time has it: given to
/// another, that one takes it over; its picker gone with none in its
/// place, it shows nothing, its listeners told after the build.
///
/// A picker that opens in the logs, and a key that lists them again:
///
/// ```dart
/// final controller = FilePickerController()..goTo('/var/log');
/// final picker = KeyBindings(
///   {'f5': controller.refresh},
///   child: FilePicker(
///     controller: controller,
///     onPicked: (paths) => print(paths.single),
///   ),
/// );
/// ```
final class FilePickerController extends ChangeNotifier {
  /// A controller that shows nothing until a picker has it.
  FilePickerController();

  final _hosts = ControllerHost<_FilePickerState>();

  _FilePickerState? get _state => _hosts.host;

  // a path gone to before a picker had it; what it shows at first
  String? _pending;

  // what the listeners were told of last
  String? _directory;
  String? _highlighted;
  var _selected = const <String>[];

  /// The absolute path of the directory shown; null while no picker has
  /// the controller.
  String? get directory => _state?._dir;

  /// The absolute path of the entry the cursor is on, the directory above
  /// for `../`; null while the directory is listed, for an empty one and
  /// while no picker has the controller.
  String? get highlighted => _state?._current?.path;

  /// The absolute paths of the files marked, with `multiple`, in the order
  /// they were; none without.
  List<String> get selected => List.unmodifiable(_state?._marked ?? const {});

  /// Shows the directory at [path], relative to the one shown (or the
  /// current one of the picker's file system), `~` at its start the home
  /// directory, as the field takes it: a file's directory with the cursor
  /// on the file. The name typed after the field's last separator is kept.
  /// A path that is no directory lists as one that cannot be. Before a
  /// picker has the controller, the directory it shows at first, in place
  /// of its `directory`.
  void goTo(String path) {
    final state = _state;
    if (state == null) {
      _pending = path;
    } else {
      state._goTo(path);
    }
  }

  /// Lists the directory shown again, the cursor kept on its entry where
  /// that is still there, the entries shown meanwhile.
  void refresh() => _state?._refresh();

  /// [state] serves the controller, in place of the picker that did.
  void _attach(_FilePickerState state) {
    _hosts.attach(state);
    _pending = null;
  }

  /// [state] lets go of the controller: where no picker takes it over,
  /// the listeners learn it shows nothing, after the build.
  void _detach(_FilePickerState state) => _hosts.detach(state, _report);

  /// Tells the listeners where what it shows changed since they were told
  /// last.
  void _report() {
    final directory = this.directory;
    final highlighted = this.highlighted;
    final marked = _state?._marked ?? const <String>{};
    final selected =
        marked.length == _selected.length &&
            marked.indexed.every((e) => _selected[e.$1] == e.$2)
        ? _selected
        : List<String>.unmodifiable(marked);
    if (directory != _directory ||
        highlighted != _highlighted ||
        !identical(selected, _selected)) {
      _directory = directory;
      _highlighted = highlighted;
      _selected = selected;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// Shows a [FilePicker] in a [Dialog], and returns a future that completes
/// with the paths picked, or with null once it is cancelled.
///
/// The dialog is titled [title], by default after the [mode] (`Open`,
/// `Save as`, `Choose a directory`), [width] × [height] cells at most, its
/// field in the theme's [ThemeData.well] on the dialog's panel. Cancel,
/// Escape and a click outside cancel it. The picker's field has the focus.
/// The other parameters are the [FilePicker]'s. See [showDialog].
///
/// From a key binding, where `context` is under the app's `Overlay`:
///
/// ```dart
/// final paths = await showFilePicker(
///   context,
///   filters: const [FileFilter('Markdown', ['md'])],
/// );
/// if (paths != null) {
///   print('open ${paths.single}');
/// }
/// ```
Future<List<String>?> showFilePicker(
  BuildContext context, {
  FilePickerMode mode = FilePickerMode.open,
  String? directory,
  PickerFileSystem fileSystem = PickerFileSystem.local,
  String name = '',
  List<FileFilter> filters = const [],
  bool showHidden = false,
  bool multiple = false,
  String? title,
  int width = 60,
  int height = 20,
}) => showDialog<List<String>>(
  context,
  (context) => SizedBox(
    width: width,
    height: height,
    child: Dialog(
      title:
          title ??
          switch (mode) {
            FilePickerMode.open => 'Open',
            FilePickerMode.save => 'Save as',
            FilePickerMode.directory => 'Choose a directory',
          },
      child: FilePicker(
        fieldStyle: Theme.of(context).well,
        onPicked: (paths) => closeDialog(context, paths),
        onCancelled: () => closeDialog(context),
        mode: mode,
        directory: directory,
        fileSystem: fileSystem,
        name: name,
        filters: filters,
        showHidden: showHidden,
        multiple: multiple,
        autofocus: true,
      ),
    ),
  ),
);

/// A file browser: a directory's entries to pick from, under a field that
/// names a path, which calls [onPicked] with the paths picked.
///
/// The field names the directory, with a separator after it, and [name]
/// at first. A picker of the Dart files under the working directory,
/// beside a picker of a directory for the output:
///
/// ```dart
/// Row(
///   children: [
///     Expanded(
///       child: FilePicker(
///         filters: const [FileFilter('Dart', ['dart'])],
///         onPicked: (paths) => print('open $paths'),
///       ),
///     ),
///     Expanded(
///       child: FilePicker(
///         mode: FilePickerMode.directory,
///         onPicked: (paths) => print('into ${paths.single}'),
///       ),
///     ),
///   ],
/// )
/// ```
///
/// The list shows `../` first, but in a root, then the directories, each
/// in bold with a separator after its name (a link to one is one), then
/// the files; each kind by name, in any case. The entries whose names
/// start with a dot show with [showHidden] at first, as the check of
/// `hidden` below the list and Alt+H (hinted) switch; the files, those
/// the filter chosen accepts: [filters]' first at first, another chosen
/// in a [Select] below the list where there are several. The directory
/// mode lists no files. A directory is listed in the background as it is
/// gone into: meanwhile the list shows only a row that says `listing`;
/// failed, `../` and a row in [ThemeData.error] that says why. On the web,
/// which has no file system, no directory is listed (`cannot list: no file
/// system on the web`) and nothing is found at a path taken.
///
/// A cursor is on an entry: the first below `../` as a directory shows.
/// Its row is in [cursorStyle] while the list has the focus,
/// [ThemeData.selection] when null, and in [idleStyle] while it has not,
/// [ThemeData.selectionIdle] when null; with [bar], a column before the
/// entries shows a bar `▎` on it, [ThemeData.primary] while the list has
/// the focus and [ThemeData.muted] while it has not. While the list has
/// the focus, Up and Down move it, Page Up and Page Down a window's rows,
/// Home and End to the ends; while the field has it, Up, Down, Page Up
/// and Page Down. Enter, a double click and, on a directory, Right take
/// the entry: a directory is gone into, a file picked. Left and Backspace
/// go up a directory, the cursor on the one left. A press on an entry puts
/// the cursor on it, and gives the list the focus. Going into a directory
/// keeps the name typed after the field's last separator. With
/// [multiple], in the open mode, Space (hinted) marks the file under the
/// cursor, or unmarks it, `[x]` before its name: the marks stay as the
/// directory changes, their count shows below the list, and a file taken
/// picks the files marked, in the order they were.
///
/// Enter in the field, and the button of the mode, Open, Save or Choose,
/// take the path the field names, relative to the directory shown, `~` at
/// its start the home directory: a directory is gone into, the field left
/// naming it; a file is picked, but in the directory mode; in the save
/// mode, a name not there yet, in a directory that is, is picked too. A
/// path that names no more than the directory shown takes what the list
/// would: in the directory mode the directory; else the files marked, or
/// the entry under the cursor. A path taken for none of these is refused:
/// why shows below the list in [ThemeData.error] until the text is edited.
/// The path the picker puts in the field, as it starts and as it goes to
/// a directory, is no step to undo ([TextEditingController.reset]): Ctrl+Z
/// takes back what was typed since.
///
/// As a name is typed after the field's last separator, an [Autocomplete]
/// suggests the entries of the directory before it that the list would
/// show whose names start with it, in any case, and those starting with a
/// dot once it does; none while the name is empty or one of them in full.
/// Tab puts in the start they share; Enter puts in the one highlighted,
/// and goes into it when it is a directory.
///
/// Each pick calls [onPicked] with absolute paths, `.` and `..` worked
/// out. Cancel, where [onCancelled] is given, calls it.
///
/// The field is a `TextField` in [fieldStyle] over the theme's surface,
/// and while it has the focus in [fieldFocusedStyle],
/// [ThemeData.selection] when null, its selection then a step towards
/// [ThemeData.primary]. `bar: false`, `idleStyle: theme.selection` and
/// `fieldFocusedStyle: const Style()` give a plain look: no bar, the
/// cursor's row in the selection's colour whether the list has the focus
/// or not, the field without a fill. A screen reader reads the field as
/// a textbox named `Path`, the path in it its value (`textbox Path:
/// /home/user/`).
///
/// It takes all the room it is given, which must be bounded: the field on
/// the first row; the filters, the check, what was refused and the
/// buttons on the last; the list between them. It needs an `Overlay`
/// above, as [Autocomplete] does. The path is typed as in Emacs'
/// find-file. With a [controller], the app reads what it shows, goes to a
/// directory and lists it again.
///
/// See also:
///
///  * [showFilePicker], which shows one in a dialog.
///  * [PickerFileSystem.memory], a tree of files of the app's own.
final class FilePicker extends StatefulWidget {
  /// A picker of the [fileSystem], which calls [onPicked] with what is
  /// picked.
  ///
  /// [multiple] is only for the open mode, which it asserts.
  const FilePicker({
    required this.onPicked,
    super.key,
    this.controller,
    this.onCancelled,
    this.mode = FilePickerMode.open,
    this.directory,
    this.fileSystem = PickerFileSystem.local,
    this.name = '',
    this.filters = const [],
    this.showHidden = false,
    this.multiple = false,
    this.autofocus = false,
    this.bar = true,
    this.cursorStyle,
    this.idleStyle,
    this.fieldStyle,
    this.fieldFocusedStyle,
  }) : assert(
         !multiple || mode == FilePickerMode.open,
         'multiple in a mode other than open',
       );

  /// Called with the paths picked: one, with [multiple] any number.
  final void Function(List<String> paths) onPicked;

  /// Called by Cancel; null for no Cancel.
  final VoidCallback? onCancelled;

  /// Reads what it shows and moves it from outside; null for none.
  final FilePickerController? controller;

  /// What it picks: files that are there, by default, a file to write or
  /// a directory.
  final FilePickerMode mode;

  /// The directory shown at first, relative to the current one of
  /// [fileSystem]; null for the current one.
  final String? directory;

  /// What the directories are listed from and the paths taken looked up
  /// in: the machine's by default.
  final PickerFileSystem fileSystem;

  /// The name in the field at first, after the directory.
  final String name;

  /// The filters to choose from, the first chosen at first; none lists
  /// every file.
  final List<FileFilter> filters;

  /// Whether the entries whose names start with a dot show at first.
  final bool showHidden;

  /// Whether Space marks files to pick together, in the open mode.
  final bool multiple;

  /// Whether the field takes the focus as it is first built.
  final bool autofocus;

  /// Whether a column before the entries shows a bar `▎` on the cursor's.
  final bool bar;

  /// The cursor's entry while the list has the focus;
  /// [ThemeData.selection] when null.
  final Style? cursorStyle;

  /// The cursor's entry while the list has not the focus;
  /// [ThemeData.selectionIdle] when null.
  final Style? idleStyle;

  /// The field, over the theme's surface and text.
  final Style? fieldStyle;

  /// The field while it has the focus, over [fieldStyle];
  /// [ThemeData.selection] when null.
  final Style? fieldFocusedStyle;

  @override
  State<FilePicker> createState() => _FilePickerState();
}

/// An entry of a directory, by [name] and absolute [path].
@immutable
final class _Entry {
  const _Entry(this.name, this.path, {required this.isDirectory});

  final String name;
  final String path;
  final bool isDirectory;

  bool get hidden => name.startsWith('.');

  String get label => isDirectory ? '$name$_sep' : name;
}

final class _FilePickerState extends State<FilePicker> {
  late String _dir;

  // the entries of the directory, null while it is listed, and what
  // listing it failed with; the listing asked for last
  List<_Entry>? _entries;
  Object? _error;
  _Listing? _listing;

  // the directory listed for suggestions last
  _Listing? _suggested;

  final _field = TextEditingController();
  final _fieldNode = FocusNode(debugLabel: 'file picker field');
  final _listNode = FocusNode(debugLabel: 'file picker list');
  final _list = ListController();

  late bool _hidden = widget.showHidden;
  var _filter = 0;

  // the path of the entry the cursor is on; null for the first below ../
  String? _cursor;
  final _marked = <String>{};

  // why the path of the field was not taken
  String? _refused;

  // whether the field's text is being set, which suggests nothing
  var _setting = false;

  // whether didUpdateWidget runs, which tells the controller's listeners
  // nothing
  var _updating = false;

  @override
  void initState() {
    super.initState();
    final files = widget.fileSystem;
    final controller = widget.controller;
    final pending = controller?._pending;
    _dir = resolvePath(
      files.currentDirectory,
      pending ?? widget.directory ?? '.',
      _home,
    );
    String? cursor;
    if (pending != null && files.kindOf(_dir) == FileKind.file) {
      cursor = _dir;
      _dir = parentOf(_dir);
    }
    _cursor = cursor;
    controller?._attach(this);
    _setText(joinPath(_dir, widget.name));
    _load();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_updating) {
      widget.controller?._report();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _listing?.cancel();
    _suggested?.cancel();
    _field.dispose();
    _fieldNode.dispose();
    _listNode.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FilePicker old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (old.fileSystem != widget.fileSystem) {
      _updating = true;
      try {
        _go(_dir, name: _name);
      } finally {
        _updating = false;
      }
    }
  }

  /// The directory `~` names.
  String? get _home => widget.fileSystem.homeDirectory;

  void _setText(String text) {
    _setting = true;
    try {
      _field.reset(text);
    } finally {
      _setting = false;
    }
  }

  void _load() {
    _listing?.cancel();
    final listing = _listing = _Listing(widget.fileSystem, _dir);
    // a listing cancelled does not complete
    unawaited(
      listing.entries.then(
        (entries) {
          if (mounted) {
            setState(() {
              _entries = entries;
              _error = null;
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _entries = const [];
              _error = error;
            });
          }
        },
      ),
    );
  }

  /// Shows [dir], the field naming [name] in it; the cursor on the entry
  /// at [cursor].
  void _go(String dir, {required String name, String? cursor}) {
    setState(() {
      _dir = dir;
      _entries = null;
      _error = null;
      _cursor = cursor;
      _refused = null;
    });
    _suggested?.cancel();
    _suggested = null;
    _setText(joinPath(dir, name));
    _load();
  }

  /// Goes to [path], resolved as the field's text is: a file's directory,
  /// the cursor on the file.
  void _goTo(String path) {
    final full = resolvePath(_dir, path, _home);
    if (widget.fileSystem.kindOf(full) == FileKind.file) {
      _go(parentOf(full), name: _name, cursor: full);
    } else {
      _go(full, name: _name);
    }
  }

  /// Lists the directory again, showing what it listed until then.
  void _refresh() {
    _suggested?.cancel();
    _suggested = null;
    _load();
  }

  /// The name typed after the field's last separator.
  String get _name {
    final text = _field.text;
    return text.substring(lastSeparator(text) + 1);
  }

  /// Whether the list shows [entry], those whose names start with a dot
  /// with [hidden].
  bool _lists(_Entry entry, {required bool hidden}) {
    if (!hidden && entry.hidden) {
      return false;
    }
    if (entry.isDirectory) {
      return true;
    }
    return widget.mode != FilePickerMode.directory &&
        (widget.filters.isEmpty || widget.filters[_filter].accepts(entry.name));
  }

  /// The entries the list shows, `../` first but in a root; none while
  /// the directory is listed.
  List<_Entry> _shown() {
    final entries = _entries;
    return [
      if (entries != null && rootOf(_dir) != _dir)
        _Entry('..', parentOf(_dir), isDirectory: true),
      for (final entry in entries ?? const <_Entry>[])
        if (_lists(entry, hidden: _hidden)) entry,
    ];
  }

  /// The index in [shown] of the entry the cursor is on; -1 for none.
  int _cursorIn(List<_Entry> shown) {
    final cursor = _cursor;
    if (cursor != null) {
      final at = shown.indexWhere((e) => e.path == cursor);
      if (at >= 0) {
        return at;
      }
    }
    if (shown.isEmpty) {
      return -1;
    }
    return shown.length > 1 && shown.first.name == '..' ? 1 : 0;
  }

  void _moveTo(int index) {
    final shown = _shown();
    if (shown.isEmpty) {
      return;
    }
    final at = index.clamp(0, shown.length - 1);
    setState(() => _cursor = shown[at].path);
    _list.ensureIndexVisible(at);
  }

  void _move(int rows) => _moveTo(_cursorIn(_shown()) + rows);

  int get _page {
    final rows = _list.hasClients ? _list.position.viewportExtent : 1;
    return rows > 1 ? rows : 1;
  }

  /// The entry under the cursor.
  _Entry? get _current {
    final shown = _shown();
    final at = _cursorIn(shown);
    return at < 0 ? null : shown[at];
  }

  /// Goes into [entry] when it is a directory, else picks it, or the files
  /// marked.
  void _take(_Entry entry) {
    if (entry.isDirectory) {
      _go(
        entry.path,
        name: _name,
        cursor: entry.name == '..' ? _dir : null,
      );
    } else {
      _pick(_marked.isEmpty ? [entry.path] : [..._marked]);
    }
  }

  void _takeCurrent() {
    final entry = _current;
    if (entry != null) {
      _take(entry);
    }
  }

  void _right() {
    final entry = _current;
    if (entry != null && entry.isDirectory) {
      _take(entry);
    }
  }

  void _up() {
    final parent = parentOf(_dir);
    if (parent != _dir) {
      _go(parent, name: _name, cursor: _dir);
    }
  }

  void _mark() {
    final entry = _current;
    if (entry != null && !entry.isDirectory) {
      setState(() {
        if (!_marked.remove(entry.path)) {
          _marked.add(entry.path);
        }
      });
    }
  }

  void _pick(List<String> paths) {
    if (_refused != null) {
      setState(() => _refused = null);
    }
    widget.onPicked(List.unmodifiable(paths));
  }

  void _refuse(String why) => setState(() => _refused = why);

  /// Takes the path the field names.
  void _accept() {
    final path = resolvePath(_dir, _field.text, _home);
    final named = _name.isNotEmpty;
    if (path == _dir && !named) {
      if (widget.mode == FilePickerMode.directory) {
        _pick([_dir]);
      } else if (_marked.isNotEmpty) {
        _pick([..._marked]);
      } else {
        _takeCurrent();
      }
      return;
    }
    final files = widget.fileSystem;
    final kind = files.kindOf(path);
    if (kind == FileKind.directory) {
      _go(path, name: '');
    } else if (kind != FileKind.none) {
      if (widget.mode == FilePickerMode.directory || !named) {
        _refuse('not a directory');
      } else {
        _pick([path]);
      }
    } else if (widget.mode != FilePickerMode.save || !named) {
      _refuse('not found');
    } else if (files.kindOf(parentOf(path)) == FileKind.directory) {
      _pick([path]);
    } else {
      _refuse('no such directory');
    }
  }

  FutureOr<Iterable<Suggestion>> _suggest(String query) {
    final at = lastSeparator(query);
    final name = query.substring(at + 1);
    if (_setting || name.isEmpty) {
      return const [];
    }
    final typed = query.substring(0, at + 1);
    final dir = resolvePath(_dir, typed, _home);
    final entries = dir == _dir ? _entries : null;
    if (entries != null) {
      return _suggestions(entries, typed, name);
    }
    var listing = _suggested;
    if (listing == null || listing.dir != dir) {
      listing?.cancel();
      listing = _suggested = _Listing(widget.fileSystem, dir);
    }
    return listing.entries.then(
      (entries) => _suggestions(entries, typed, name),
      onError: (Object _) => const <Suggestion>[],
    );
  }

  /// The entries of [entries] that go with [name], typed after [typed].
  Iterable<Suggestion> _suggestions(
    List<_Entry> entries,
    String typed,
    String name,
  ) {
    if (entries.any((e) => e.name == name)) {
      return const [];
    }
    final lower = name.toLowerCase();
    final hidden = _hidden || name.startsWith('.');
    return [
      for (final entry in entries)
        if (entry.name.toLowerCase().startsWith(lower) &&
            _lists(entry, hidden: hidden))
          Suggestion('$typed${entry.label}', label: entry.label),
    ];
  }

  void _picked(Suggestion suggestion) {
    if (suggestion.text.endsWith(_sep)) {
      _accept();
    }
  }

  void _edited(String _) {
    if (_refused != null) {
      setState(() => _refused = null);
    }
  }

  void _toggleHidden() => setState(() => _hidden = !_hidden);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filters = widget.filters;
    final refused = _refused;
    return KeyBindings(
      {'alt+h': _toggleHidden},
      hints: const {'alt+h': 'hidden'},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyBindings(
            {
              'up': () => _move(-1),
              'down': () => _move(1),
              'pageup': () => _move(-_page),
              'pagedown': () => _move(_page),
            },
            child: Autocomplete(
              controller: _field,
              suggestions: _suggest,
              onSelected: _picked,
              child: TextField(
                controller: _field,
                semanticsLabel: 'Path',
                focusNode: _fieldNode,
                autofocus: widget.autofocus,
                onChanged: _edited,
                onSubmitted: (_) => _accept(),
                style: fieldRest(theme)
                    .merge(widget.fieldStyle ?? const Style()),
                focusedStyle: widget.fieldFocusedStyle ?? fieldFocused(theme),
                selectionStyle: widget.fieldFocusedStyle == null
                    ? fieldSelection(theme)
                    : null,
              ),
            ),
          ),
          Expanded(child: _files(theme)),
          Row(
            gap: 1,
            children: [
              if (filters.length > 1)
                Select<int>(
                  choices: [
                    for (final (i, filter) in filters.indexed)
                      Choice(i, filter.label),
                  ],
                  value: _filter,
                  onChanged: (i) => setState(() => _filter = i),
                ),
              Checkbox(
                value: _hidden,
                label: 'hidden',
                onChanged: (on) => setState(() => _hidden = on),
              ),
              Expanded(
                child: Text(
                  refused ??
                      (_marked.isEmpty ? '' : '${_marked.length} marked'),
                  style: refused != null ? theme.error : theme.muted,
                  wrap: TextWrap.none,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onCancelled case final cancel?)
                Button('Cancel', onPressed: cancel),
              Button(switch (widget.mode) {
                FilePickerMode.open => 'Open',
                FilePickerMode.save => 'Save',
                FilePickerMode.directory => 'Choose',
              }, onPressed: _accept),
            ],
          ),
        ],
      ),
    );
  }

  Widget _files(ThemeData theme) {
    final shown = _shown();
    final cursor = _cursorIn(shown);
    final error = _error;
    final indent = widget.bar ? ' ' : '';
    final note = _entries == null
        ? Text('${indent}listing', style: theme.muted)
        : error != null
        ? Text(
            '${indent}cannot list: ${describeFileError(error)}',
            style: theme.error,
            wrap: TextWrap.none,
          )
        : null;
    return Pressable(
      focusNode: _listNode,
      bindings: {
        'up': () => _move(-1),
        'down': () => _move(1),
        'pageup': () => _move(-_page),
        'pagedown': () => _move(_page),
        'home': () => _moveTo(0),
        'end': () => _moveTo(_shown().length - 1),
        'enter': _takeCurrent,
        'right': _right,
        'left': _up,
        'backspace': _up,
        if (widget.multiple) 'space': _mark,
      },
      hints: {
        'enter': 'open',
        'left': 'parent',
        if (widget.multiple) 'space': 'mark',
      },
      builder: (context, focused) => ListView.builder(
        itemCount: shown.length + (note == null ? 0 : 1),
        itemExtent: 1,
        controller: _list,
        canRequestFocus: false,
        itemBuilder: (context, i) => i < shown.length
            ? _row(theme, shown[i], i == cursor, focused)
            : note!,
      ),
    );
  }

  Widget _row(ThemeData theme, _Entry entry, bool cursor, bool focused) {
    var style = theme.text;
    if (entry.isDirectory) {
      style = style.merge(const Style(attrs: Attr.bold));
    }
    if (cursor) {
      style = style.merge(
        focused
            ? widget.cursorStyle ?? theme.selection
            : widget.idleStyle ?? theme.selectionIdle,
      );
    }
    final mark = !widget.multiple
        ? ''
        : entry.isDirectory
        ? '    '
        : _marked.contains(entry.path)
        ? '[x] '
        : '[ ] ';
    return Listener(
      key: ValueKey<String>(entry.path),
      onDown: (event) {
        if (event.button == 0) {
          setState(() => _cursor = entry.path);
        }
      },
      child: GestureDetector(
        onDoubleTap: (_) => _take(entry),
        child: Box(
          style: style,
          child: Text.rich(
            [
              if (widget.bar && cursor)
                Span(
                  '▎',
                  (focused ? theme.primary : theme.muted).merge(
                    const Style(attrsOff: Attr.bold),
                  ),
                )
              else if (widget.bar)
                const Span(' '),
              Span('$mark${entry.label}'),
            ],
            style: style,
            wrap: TextWrap.none,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

/// [dir] being listed, until [cancel]: [entries] completes with its
/// entries, the directories first, each kind by name, or with the error
/// listing it failed with.
final class _Listing {
  _Listing(PickerFileSystem files, this.dir) {
    final entries = <_Entry>[];
    _done.future.ignore();
    _subscription = files
        .list(dir)
        .listen(
          (entry) {
            final path = entry.path;
            entries.add(
              _Entry(
                path.substring(lastSeparator(path) + 1),
                path,
                isDirectory: entry.isDirectory,
              ),
            );
          },
          onError: _done.completeError,
          onDone: () => _done.complete(entries..sort(_order)),
          cancelOnError: true,
        );
  }

  final String dir;
  final _done = Completer<List<_Entry>>();
  late final StreamSubscription<DirectoryEntry> _subscription;

  Future<List<_Entry>> get entries => _done.future;

  /// Stops listing: [entries] does not complete if it has not.
  void cancel() => unawaited(_subscription.cancel());
}

int _order(_Entry a, _Entry b) {
  if (a.isDirectory != b.isDirectory) {
    return a.isDirectory ? -1 : 1;
  }
  final order = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return order != 0 ? order : a.name.compareTo(b.name);
}

String get _sep => separator;
