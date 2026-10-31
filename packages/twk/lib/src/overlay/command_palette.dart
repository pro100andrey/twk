/// Command palettes: a [CommandPalette] lists what can be done from the
/// focused widget, the [Command]s it is given and the keys bound there, to
/// find by typing and run; a [CommandPaletteController] opens it from the
/// app.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart'
    show Alignment, CrossAxisAlignment, EdgeInsets, MainAxisSize;

import '../editing/text_editing.dart';
import '../editing/text_field.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../foundation/controller_host.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../layout/shadow.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'dialog.dart';
import 'fuzzy.dart';
import 'key_path.dart';
import 'layer.dart';
import 'options.dart';
import 'panel.dart';

// Examples can assume:
// void save() {}
// void quit() {}
// void openFile(String file) {}
// Iterable<String> filesMatching(String query) => const [];
// late Widget editor;
// final class SaveIntent extends Intent {
//   const SaveIntent();
// }

/// What a [CommandPalette] lists besides the keys bound where the focus
/// is: [label], and what it does once chosen, as a `MenuItem` does: calls
/// [onSelected], or does [intent] as a key that `Shortcuts` binds to it
/// would, from the node the keys went to first as the palette opened; with a
/// [detail] to show on its right where no key is bound to it.
///
/// A command that calls back, and one that does what a key bound to
/// `SaveIntent` does where the focus is:
///
/// ```dart
/// final commands = [
///   Command('Quit', onSelected: quit),
///   Command('Save', intent: const SaveIntent()),
/// ];
/// ```
@immutable
final class Command {
  /// A command of [label] that calls [onSelected] or does [intent], not
  /// both: it asserts so. With neither, it does nothing.
  const Command(this.label, {this.onSelected, this.intent, this.detail})
    : assert(
        onSelected == null || intent == null,
        'onSelected or intent, not both',
      );

  /// What the palette shows and matches what is typed with.
  final String label;

  /// Called when it is chosen.
  final VoidCallback? onSelected;

  /// Done when it is chosen.
  final Intent? intent;

  /// What the palette shows on its right, in the theme's dim text, where
  /// no key is bound to the command; null for nothing.
  final String? detail;
}

/// Opens and closes the palette of the [CommandPalette] it is given to
/// (`controller:`), and says whether it is open and what is typed in it,
/// telling its listeners when either changes: as it opens (by [open] or
/// the palette's key), as what is typed changes and as it closes (by
/// [close], by Escape, by a click outside or by a command run).
///
/// It is given to one palette at a time; given to one built in place of
/// its palette (a key changed), that one goes on with the palette open.
/// Its palette gone from the tree with none built in its place, the
/// palette closes after the build.
///
/// A palette that a button of the app opens, with `>` typed in it:
///
/// ```dart
/// final palette = CommandPaletteController();
/// final app = CommandPalette(
///   controller: palette,
///   commands: [Command('Quit', onSelected: quit)],
///   child: Button('Commands', onPressed: () => palette.open(query: '>')),
/// );
/// ```
final class CommandPaletteController extends ChangeNotifier {
  final _hosts = ControllerHost<_CommandPaletteState>();

  /// Whether the palette is open.
  bool get isOpen => _hosts.host?._at != null;

  /// What is typed in the palette while it is open; closed, what was typed
  /// as it closed, '' before it first opened.
  String get query => _hosts.host?._query ?? '';

  /// Opens the palette, as its key does, with [query] typed in it, the
  /// caret at its end; open, sets what is typed to [query]. A
  /// [StateError] when it is given to no [CommandPalette].
  void open({String query = ''}) {
    final palette = _hosts.host;
    if (palette == null) {
      throw StateError(
        'CommandPaletteController.open: given to no CommandPalette: give '
        'it to one as CommandPalette(controller: …)',
      );
    }
    palette._openWith(query);
  }

  /// Closes the palette, running nothing, the focus going back where it
  /// was; nothing when it is closed.
  void close() => _hosts.host?._close();

  void _changed() {
    if (!_hosts.isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _hosts.dispose();
    super.dispose();
  }
}

/// [child], with a palette of what can be done that [openKey] opens
/// wherever the focus is in [child] (`ctrl+p commands` in a `KeyHintsBar`):
/// a dialog at the top of the [Overlay] above ([showDialog]), a field to
/// type in over the commands that match what is typed.
///
/// It lists what can be done from the node the keys went to first as it
/// opened (the focused one, [FocusManager.keyPath]): each of [commands]
/// that calls its [Command.onSelected], or whose [Command.intent] an
/// enabled [Action] there does; then each key that
/// [FocusManagerKeys.activeKeys] lists there with a hint, what a
/// `KeyHintsBar` shows, its hint for its label, unless it is bound to what
/// a command does. Each shows on its right the first of those keys bound
/// to the same callback or to an equal intent, a sequence whole
/// ([ActiveKey.label]), named by [keyLabel] (`ctrl+s` by default,
/// [KeyCombo.toString]).
///
/// What is typed filters them by their labels and ranks them
/// ([fuzzyMatch]), the characters it found standing out: the best match
/// first; of those that match alike, the one run last first, then in the
/// order above. With nothing typed, those run before come first, the one
/// run last first. Up and Down highlight the one before and after, Enter
/// runs the highlighted one (`enter run`), Escape (`escape close`) and a
/// click outside close the palette.
///
/// What it runs, it runs once the palette is closed and the focus back
/// where it was: the command's callback, or its intent from that node, as
/// a key bound to it would.
///
/// [commandsFor] is asked for more as the palette opens, with what is
/// typed ('' at first, or the query [CommandPaletteController.open] typed),
/// and each time what is typed changes: the commands it gives, at once or
/// in a future, are listed after those above that match, in its order,
/// whether they match what is typed or not, the characters of it found in
/// their labels standing out; one whose [Command.intent] nothing does
/// where the keys went is left out. Run before, they do not move up: it
/// orders them. Those it gave last show until it answers anew; an answer
/// that comes after what is typed changed again, or after the palette
/// closed, does not show.
///
/// At most [rows] commands show, in a box [width] columns wide, or as wide
/// as the overlay is: a raised panel ([look]) a row from the top, with the
/// theme's panel shadow and no barrier, fading in over 140 ms; the field
/// after ` >`, the count of what matches at its right (`3 of 12`, in the
/// theme's dim text); the commands that match under it, the highlighted
/// one in the theme's selection. The mouse moved onto a command highlights
/// it, a click runs it, the wheel moves the highlight. [prompt] stands before
/// the field, [placeholder] in it while nothing is typed, [rule] draws a line
/// under it, [bar] and [thumb] mark the highlighted command and the place of
/// the list in what matches, [barrierAlpha] dims what is under the palette
/// and [hintedKeys] leaves the keys hinted where the focus is out of it,
/// those of [commands] and [commandsFor] only. With [look]
/// [PanelLook.bordered]: a bordered box, no count, no shadow, shown at
/// once. Without an [Overlay] above it the
/// build fails with a [StateError] that says where to place one. A screen
/// reader reads the field as a textbox named `Command`, what is typed its
/// value (`textbox Command: sa`).
///
/// A [controller] opens it from the app, with a query typed, and closes
/// it ([CommandPaletteController]). Taken out of the tree while its
/// palette is open, it closes the palette after the build, unless one
/// built in its place with its controller goes on with it.
///
/// An editor whose palette lists its own commands, the keys bound where
/// the focus is, and the files that match what is typed:
///
/// ```dart
/// CommandPalette(
///   commands: [
///     Command('Save', onSelected: save),
///     Command('Quit', onSelected: quit),
///   ],
///   commandsFor: (query) => [
///     for (final file in filesMatching(query))
///       Command('Open $file', onSelected: () => openFile(file)),
///   ],
///   child: editor,
/// )
/// ```
final class CommandPalette extends StatefulWidget {
  /// [child], with a palette of [commands] and the keys bound where the
  /// focus is, opened by [openKey], Ctrl+P by default.
  const CommandPalette({
    required this.child,
    super.key,
    this.commands = const [],
    this.commandsFor,
    this.controller,
    this.openKey = 'ctrl+p',
    this.keyLabel,
    this.rows = 10,
    this.width = 60,
    this.look = PanelLook.raised,
    this.prompt = ' >',
    this.placeholder,
    this.rule = false,
    this.bar = false,
    this.thumb = false,
    this.barrierAlpha = 0,
    this.hintedKeys = true,
  }) : assert(rows > 0, 'rows below 1'),
       assert(
         barrierAlpha == null || (barrierAlpha >= 0 && barrierAlpha <= 255),
         'barrierAlpha out of 0..255',
       );

  /// What the palette is over, and lists what can be done in.
  final Widget child;

  /// The commands listed before the keys bound where the focus is: none by
  /// default.
  final List<Command> commands;

  /// The commands that go with what is typed, listed after [commands]; null
  /// for none.
  final FutureOr<Iterable<Command>> Function(String query)? commandsFor;

  /// What opens and closes it from the app; null for none.
  final CommandPaletteController? controller;

  /// The key that opens the palette, named as [KeyBindings] names keys:
  /// `ctrl+p` by default.
  final String openKey;

  /// How a key is named, those of a sequence one by one; null for
  /// [KeyCombo.toString].
  final String Function(KeyCombo combo)? keyLabel;

  /// The most commands shown at once: 10 by default; asserted to be 1 or
  /// more.
  final int rows;

  /// The columns the palette takes, the overlay's width at most: 60 by
  /// default.
  final int width;

  /// A raised panel, or a bordered box.
  final PanelLook look;

  /// What stands before the field: ` >` by default; nothing, and no gap
  /// after it, where empty.
  final String prompt;

  /// What the field shows, in the theme's dim text, while nothing is typed;
  /// null for nothing.
  final String? placeholder;

  /// Whether a line is drawn between the field and the commands: not by
  /// default.
  final bool rule;

  /// Whether the highlighted command has a `▎` in its first column: not by
  /// default.
  final bool bar;

  /// Whether a thumb at the right shows where the commands shown are in
  /// those that match, when they are more than [rows]: not by default.
  final bool thumb;

  /// How much of the theme's shade ([ThemeData.shade]) the palette blends
  /// over what is under it, from 0 to 255: 0 by default; null for the
  /// theme's own, [ThemeData.shadeAlpha], as a dialog has. Asserted to be
  /// in range.
  final int? barrierAlpha;

  /// Whether the keys hinted where the focus is are listed after the
  /// commands: they are by default.
  final bool hintedKeys;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

/// What a palette lists: [label], what is done ([binding], a callback or
/// an intent) and the first key bound to it there.
@immutable
final class _Entry {
  const _Entry(this.label, this.binding, this.key, [this.detail]);

  final String label;
  final Object binding;
  final ActiveKey? key;

  /// What a command says of itself, shown where no key is bound to it.
  final String? detail;
}

final class _CommandPaletteState extends State<CommandPalette> {
  // the labels of what was run, the last first
  final _recent = <String>[];

  // the number of the palette open; null while none is
  int? _at;
  var _opened = 0;

  // what is typed in it, or was as it closed
  var _query = '';

  // the palette open, once built
  _PaletteState? _shown;

  // the first key bound to each callback and intent where the keys went as
  // the palette opened
  var _first = const <Object, ActiveKey>{};

  // the palette built in this one's place with its controller, which took
  // the palette open over
  _CommandPaletteState? _successor;

  /// The palette that has this one's palette open now: this one, or the
  /// last built in its place with its controller.
  _CommandPaletteState get _current {
    var state = this;
    for (var next = _successor; next != null; next = next._successor) {
      state = next;
    }
    return state;
  }

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
    }
  }

  @override
  void dispose() {
    widget.controller?._hosts.detach(this);
    if (_at != null) {
      // gone with its palette open: closed after the build, its controller
      // told, unless one built in its place took the palette over
      scheduleMicrotask(() {
        if (_successor == null) {
          _close();
        }
      });
    }
    super.dispose();
  }

  /// Serves [controller]: built in place of the palette that did, goes on
  /// with what that one has open and has run.
  void _attach(CommandPaletteController? controller) {
    if (controller == null) {
      return;
    }
    if (controller._hosts.attach(this) case final old?) {
      _at = old._at;
      _opened = old._opened;
      _query = old._query;
      _shown = old._shown;
      _first = old._first;
      _recent
        ..clear()
        ..addAll(old._recent);
      old._successor = this;
    } else if (_at != null) {
      // given to an open palette: its listeners learn it is open
      controller._hosts.afterBuild(controller._changed);
    }
  }

  /// Lets go of [controller]: where no palette takes it over and this one
  /// is open, its listeners learn it is not, after the build.
  void _detach(CommandPaletteController? controller) {
    if (controller == null) {
      return;
    }
    final open = _at != null;
    controller._hosts.detach(this, open ? controller._changed : null);
  }

  void _told() => widget.controller?._changed();

  void _open() => _openWith('');

  /// Opens the palette with [query] typed, or sets what is typed in the
  /// open one.
  void _openWith(String query) {
    if (_at != null) {
      if (_shown case final shown?) {
        shown._type(query);
      } else if (query != _query) {
        // not built yet: built with it
        _query = query;
        _told();
      }
      return;
    }
    final at = _at = ++_opened;
    _query = query;
    _shown = null;
    _told();
    final target = keyTarget(context);
    // as the keys are before the palette takes them
    final entries = _entries(target);
    unawaited(
      showDialog<_Entry>(
        context,
        (_) => _Palette(
          entries,
          owner: this,
          at: at,
          target: target,
          recent: List.of(_recent),
          keyLabel: widget.keyLabel,
          rows: widget.rows,
          width: widget.width,
          look: widget.look,
          prompt: widget.prompt,
          placeholder: widget.placeholder,
          rule: widget.rule,
          bar: widget.bar,
          thumb: widget.thumb,
        ),
        alignment: Alignment.topCenter,
        barrierAlpha: widget.barrierAlpha,
        fadeIn: widget.look == PanelLook.raised
            ? const Duration(milliseconds: 140)
            : Duration.zero,
      ).then((entry) {
        final current = _current.._closed(at);
        if (entry != null && current.mounted) {
          current._run(entry, target);
        }
      }),
    );
  }

  /// Closes the open palette, running nothing.
  void _close() {
    final shown = _shown;
    final at = _at;
    if (at != null) {
      _closed(at);
      if (shown != null && shown.mounted) {
        closeDialog(shown.context);
      }
    }
  }

  /// Marks the palette numbered [at] closed, where it is the one open.
  void _closed(int at) {
    if (_at == at) {
      _at = null;
      _shown = null;
      _told();
    }
  }

  /// Tells of what is typed in the palette numbered [at].
  void _typed(int at, String query) {
    if (_at == at && query != _query) {
      _query = query;
      _told();
    }
  }

  /// The [commands] that can be done from [target], as entries.
  List<_Entry> _commandEntries(
    BuildContext target,
    Iterable<Command> commands,
    Map<Object, ActiveKey> first,
    Set<Object> done,
  ) => [
    for (final command in commands)
      if (command.onSelected ?? command.intent case final binding?)
        if (binding is! Intent || Actions.maybeFind(target, binding) != null)
          if (done.add(binding))
            _Entry(command.label, binding, first[binding], command.detail),
  ];

  /// What can be done from [target], as [CommandPalette] lists it.
  List<_Entry> _entries(BuildContext target) {
    final keys = activeKeysAt(target);
    final first = _first = firstKeys(keys);
    // what is listed already, and the palette's own key
    final done = <Object>{_open};
    return [
      ..._commandEntries(target, widget.commands, first, done),
      if (widget.hintedKeys)
        for (final key in keys)
          if (key.hint case final hint?)
            if (done.add(key.binding)) _Entry(hint, key.binding, key),
    ];
  }

  /// The [commands] that [CommandPalette.commandsFor] gave that can be
  /// done from [target], as entries.
  List<_Entry> _givenEntries(BuildContext target, Iterable<Command> commands) =>
      _commandEntries(target, commands, _first, <Object>{_open});

  void _run(_Entry entry, BuildContext target) {
    _recent
      ..remove(entry.label)
      ..insert(0, entry.label);
    switch (entry.binding) {
      case final Intent intent:
        if (target.mounted) {
          Actions.maybeInvoke(target, intent);
        }
      case final VoidCallback callback:
        callback();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Overlay.maybeOf(context) == null) {
      throw StateError(
        'CommandPalette: no Overlay above it: place an Overlay above it, as '
        'App does around the whole app: App(child: …)',
      );
    }
    final key = widget.openKey;
    return KeyBindings(
      {key: _open},
      hints: {key: 'commands'},
      debugLabel: 'command palette',
      child: widget.child,
    );
  }
}

/// The palette open: a field over the [entries] that match what is typed
/// in it.
final class _Palette extends StatefulWidget {
  const _Palette(
    this.entries, {
    required this.owner,
    required this.at,
    required this.target,
    required this.recent,
    required this.keyLabel,
    required this.rows,
    required this.width,
    required this.look,
    required this.prompt,
    required this.placeholder,
    required this.rule,
    required this.bar,
    required this.thumb,
  });

  final List<_Entry> entries;

  /// The palette it is of, and its number there.
  final _CommandPaletteState owner;
  final int at;

  /// Where the keys went as it opened.
  final BuildContext target;

  /// The labels of what was run, the last first.
  final List<String> recent;

  final String Function(KeyCombo combo)? keyLabel;
  final int rows;
  final int width;
  final PanelLook look;
  final String prompt;
  final String? placeholder;
  final bool rule;
  final bool bar;
  final bool thumb;

  @override
  State<_Palette> createState() => _PaletteState();
}

final class _PaletteState extends State<_Palette> {
  late final _query = TextEditingController(text: _typed);
  // what the controller set last, or '' when closed before it was built
  late String _typed = widget.owner._query;

  /// The palette this one is of now.
  _CommandPaletteState get _owner => widget.owner._current;

  // whether it was closed before it was built
  var _gone = false;
  var _ranked = const <(_Entry, List<int>)>[];
  var _highlighted = 0;

  // what commandsFor gave last
  var _given = const <_Entry>[];

  // the number of the query asked for last
  var _asked = 0;

  @override
  void initState() {
    super.initState();
    final owner = _owner;
    if (owner._at == widget.at) {
      owner._shown = this;
    } else {
      // closed by the controller before it was built
      _gone = true;
      scheduleMicrotask(() {
        if (mounted) {
          closeDialog(context);
        }
      });
      return;
    }
    _ask();
    _rank();
    _query.addListener(_changed);
  }

  @override
  void dispose() {
    final owner = _owner;
    if (identical(owner._shown, this)) {
      owner._shown = null;
    }
    _query.dispose();
    super.dispose();
  }

  /// Sets what is typed to [query], the caret at its end.
  void _type(String query) => _query.text = query;

  void _changed() {
    final typed = _query.text;
    if (typed != _typed) {
      setState(() {
        _typed = typed;
        _highlighted = 0;
        _ask();
        _rank();
      });
      _owner._typed(widget.at, typed);
    }
  }

  /// Asks [CommandPalette.commandsFor] for the commands that go with what
  /// is typed.
  void _ask() {
    final commandsFor = _owner.widget.commandsFor;
    if (commandsFor == null) {
      return;
    }
    final asked = ++_asked;
    final answer = commandsFor(_typed);
    if (answer is Future<Iterable<Command>>) {
      unawaited(
        answer.then((commands) {
          if (mounted && asked == _asked) {
            setState(() => _give(commands));
          }
        }),
      );
    } else {
      _give(answer);
    }
  }

  /// Lists [commands], as [CommandPalette.commandsFor] gave them.
  void _give(Iterable<Command> commands) {
    final target = widget.target;
    _given = target.mounted ? _owner._givenEntries(target, commands) : const [];
    _rank();
    final n = _ranked.length;
    if (_highlighted >= n) {
      _highlighted = n == 0 ? 0 : n - 1;
    }
  }

  /// The entries that match what is typed, as [CommandPalette] ranks them.
  void _rank() {
    final recent = widget.recent;
    int lastRun(_Entry entry) {
      final i = recent.indexOf(entry.label);
      return i < 0 ? recent.length : i;
    }

    final matched =
        [
          for (final (i, entry) in widget.entries.indexed)
            if (fuzzyMatch(_typed, entry.label) case final match?)
              (entry, match, lastRun(entry), i),
        ]..sort((a, b) {
          final byScore = b.$2.score.compareTo(a.$2.score);
          if (byScore != 0) {
            return byScore;
          }
          final byRun = a.$3.compareTo(b.$3);
          return byRun != 0 ? byRun : a.$4.compareTo(b.$4);
        });
    _ranked = [
      for (final (entry, match, _, _) in matched) (entry, match.positions),
      for (final entry in _given)
        (entry, fuzzyMatch(_typed, entry.label)?.positions ?? const <int>[]),
    ];
  }

  void _move(int step) {
    final n = _ranked.length;
    if (n > 0) {
      setState(() => _highlighted = (_highlighted + step) % n);
    }
  }

  void _choose() {
    if (_ranked.isNotEmpty) {
      _close(_ranked[_highlighted].$1);
    }
  }

  /// Closes the palette, to run [entry] where not null.
  void _close([_Entry? entry]) {
    _owner._closed(widget.at);
    closeDialog(context, entry);
  }

  String? _detailOf(_Entry entry) =>
      entry.key?.label(widget.keyLabel) ?? entry.detail;

  void _highlight(int index) => setState(() => _highlighted = index);

  void _run(int index) {
    if (index < _ranked.length) {
      _close(_ranked[index].$1);
    }
  }

  Widget _field() => KeyBindings(
    {
      'up': () => _move(-1),
      'down': () => _move(1),
      'enter': _choose,
      'escape': _close,
    },
    hints: const {'enter': 'run', 'escape': 'close'},
    debugLabel: 'command palette',
    // the palette's hints alone
    child: TextField(
      controller: _query,
      semanticsLabel: 'Command',
      placeholder: widget.placeholder,
      autofocus: true,
      keyHints: false,
    ),
  );

  Widget _list(BuildContext context, {required bool raised}) {
    final ranked = _ranked;
    if (ranked.isEmpty) {
      return Text(' no command matches', style: Theme.of(context).muted);
    }
    return OptionList(
      options: [
        for (final (entry, match) in ranked)
          Option(entry.label, marks: match, detail: _detailOf(entry)),
      ],
      highlighted: _highlighted,
      rows: widget.rows,
      bar: widget.bar,
      thumb: widget.thumb,
      onHighlight: raised ? _highlight : null,
      onSelected: raised ? _run : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) {
      return const SizedBox.shrink();
    }
    if (widget.look == PanelLook.raised) {
      final theme = Theme.of(context);
      final count =
          '${_ranked.length} of ${widget.entries.length + _given.length}';
      // two columns at the left for the two of the shadow at the right,
      // so that the panel is centred
      return Padding(
        padding: const EdgeInsets.only(left: 2, top: 1),
        child: Shadow(
          shadow: Panel.shadowOf(theme),
          child: SizedBox(
            width: widget.width,
            child: Semantics(
              role: SemanticsRole.dialog,
              child: Panel(
                shadow: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      gap: 1,
                      children: [
                        if (widget.prompt.isNotEmpty) Text(widget.prompt),
                        Expanded(child: _field()),
                        Padding(
                          padding: const EdgeInsets.x(1),
                          child: Text(count, style: theme.dim, maxLines: 1),
                        ),
                      ],
                    ),
                    if (widget.rule) Divider(style: theme.dim),
                    _list(context, raised: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: SizedBox(
        width: widget.width,
        child: Dialog(
          look: PanelLook.bordered,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                gap: 1,
                children: [
                  if (widget.prompt.isNotEmpty) Text(widget.prompt),
                  Expanded(child: _field()),
                ],
              ),
              if (widget.rule) Divider(style: Theme.of(context).dim),
              _list(context, raised: false),
            ],
          ),
        ),
      ),
    );
  }
}
