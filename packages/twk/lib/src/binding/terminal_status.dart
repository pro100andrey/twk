/// What an app shows of itself on the terminal outside its cells: the
/// shape of the mouse pointer over it ([MouseRegion.cursor]), its progress
/// in the terminal's tab or taskbar ([TerminalProgress]) and the title of
/// its window or tab ([WindowTitle]).
library;

import 'package:meta/meta.dart' show internal;
import 'package:twk_core/twk_core.dart'
    show
        PointerShape,
        ProgressState,
        TerminalBackend,
        TerminalStateBackend,
        WindowBackend,
        pointerShapeSequence,
        progressSequence;

import '../framework/framework.dart';
import '../gestures/mouse.dart' show MouseRegion;
import 'app_binding.dart';

export 'package:twk_core/twk_core.dart' show ProgressState;

// Examples can assume:
// late BuildContext context;
// late int copied;
// late int total;

/// The pointer's shape and the progress an app shows on its [terminal]
/// ([of]), each written when it changes and only where the terminal is
/// known to show it (`TerminalInfo.pointerShapes`,
/// `TerminalInfo.progressReports`). The terminal keeps what puts each
/// back as it was and writes it when it is closed, whatever ends the app,
/// or handed to another program ([TerminalStateBackend]); on a backend
/// that isn't one nothing is written. And the title of the terminal's
/// window or tab ([title]), which the user's own title takes back from
/// when the terminal is closed (`Terminal.setTitle`).
///
/// An app sets the pointer's shape through the status of its terminal:
///
/// ```dart
/// TerminalStatus.of(context)?.pointerShape = PointerShape.wait;
/// ```
///
/// See also:
///
///  * [TerminalProgress] and [WindowTitle], the widgets that show the
///    progress and the title.
final class TerminalStatus {
  /// The status shown on [terminal]; [of] gives that of an app's.
  TerminalStatus(this.terminal);

  /// The status of the app [binding] runs.
  @internal
  factory TerminalStatus.ofBinding(AppBinding binding) =>
      _ofApp[binding] ??= TerminalStatus(binding.twkApp.terminal);

  /// What the status is shown on.
  final TerminalBackend terminal;

  static final _ofApp = Expando<TerminalStatus>();

  /// The status of the app [context] is in; null outside an app.
  static TerminalStatus? of(BuildContext context) {
    final binding = AppBinding.maybeOf(context);
    return binding == null ? null : TerminalStatus.ofBinding(binding);
  }

  TerminalStateBackend? get _backend => switch (terminal) {
    final TerminalStateBackend backend => backend,
    _ => null,
  };

  /// Whether the pointer's shape is shown: a [MouseRegion] with a cursor
  /// has the terminal report the mouse's motion only then.
  bool get showsPointerShape => terminal.info.pointerShapes && _backend != null;

  /// The pointer's shape over the app: null for the [defaultPointerShape].
  /// Once a [MouseRegion] has been mounted, the regions set it after each
  /// frame and as the mouse moves ([MouseRegion.cursor]), over a shape set
  /// here: an app shows a shape of its own with a MouseRegion around it.
  PointerShape? get pointerShape => _pointerShape;
  PointerShape? _pointerShape;

  set pointerShape(PointerShape? shape) {
    if (shape == _pointerShape || !showsPointerShape) {
      return;
    }
    _pointerShape = shape;
    showPointer();
  }

  /// The pointer's shape where neither a [MouseRegion] nor [pointerShape]
  /// sets one: in the fullscreen mode the arrow, as over a window, every
  /// cell being the app's (`TerminalInfo.alternateScreen`); inline the
  /// terminal's own (null), the lines around the app's being the shell's.
  PointerShape? get defaultPointerShape =>
      terminal.info.alternateScreen ? PointerShape.arrow : null;

  // the shape written last; null for the terminal's own
  PointerShape? _shown;

  /// Writes the shape of the pointer, [pointerShape] or else the
  /// [defaultPointerShape], unless it is the one written last: the binding
  /// does after each frame, the first one showing the default.
  @internal
  void showPointer() {
    final backend = _backend;
    final shape = _pointerShape ?? defaultPointerShape;
    if (shape == _shown || backend == null || !terminal.info.pointerShapes) {
      return;
    }
    _shown = shape;
    if (shape == null) {
      backend.restoreTerminalState(_pointerKey);
    } else {
      backend.setTerminalState(
        _pointerKey,
        pointerShapeSequence(shape, terminal.info.pointerNames),
        pointerShapeSequence(null),
      );
    }
  }

  /// How often a progress that doesn't change is written again: within
  /// the 15 s after which Ghostty takes one away (kitty: 60 s).
  static const progressRefresh = Duration(seconds: 10);

  // the progresses mounted, the last one shown
  final _progresses = <_TerminalProgressState>[];

  // what shows the progress written last; null for none
  String? _progress;

  /// Writes the progress of the last [TerminalProgress] mounted, unless it
  /// is the one written last.
  void _showProgress() {
    final backend = _backend;
    if (backend == null || !terminal.info.progressReports) {
      return;
    }
    final widget = _progresses.isEmpty ? null : _progresses.last.widget;
    final value = widget?.value;
    final state = switch (widget?.state ?? ProgressState.none) {
      ProgressState.normal when value == null => ProgressState.indeterminate,
      final state => state,
    };
    final progress = state == ProgressState.none
        ? null
        : progressSequence(
            state,
            percent: value == null
                ? null
                : value >= 1
                ? 100
                : value > 0
                ? (value * 100).round()
                : 0,
          );
    if (progress == _progress) {
      return;
    }
    _progress = progress;
    if (progress == null) {
      backend.restoreTerminalState(_progressKey);
    } else {
      backend.setTerminalState(
        _progressKey,
        progress,
        progressSequence(ProgressState.none),
        refresh: progressRefresh,
      );
    }
  }

  static const _pointerKey = #pointerShape;
  static const _progressKey = #progress;

  // the titles mounted, the last one shown
  final _titles = <_WindowTitleState>[];

  /// The title of the terminal's window or tab the app set: that of the
  /// [WindowTitle] mounted last, or, once none is, of the last one
  /// removed; null before one was mounted.
  String? get title => _title;
  String? _title;

  /// Sets the title of the last [WindowTitle] mounted, unless it is the
  /// one set last, through [WindowBackend.setTitle] (`Terminal.setTitle`,
  /// which gives the user's title back as it closes; on a
  /// `HeadlessTerminal`, the sequence that sets it written to its frames).
  /// Nothing on a backend that is no [WindowBackend].
  void _showTitle() {
    if (_titles.isEmpty) {
      return;
    }
    final title = _titles.last.widget.title;
    if (title == _title) {
      return;
    }
    _title = title;
    if (terminal case final WindowBackend terminal) {
      terminal.setTitle(title);
    }
  }
}

/// Shows the program's progress in the terminal's tab or taskbar (OSC
/// 9;4) while it is in the tree, where the terminal is known to show one
/// ([TerminalStatus]): as far as [value] says, as [state] says. Of
/// several, the one mounted last is shown; once none is, the progress is
/// taken away, as it is when the app ends or hands the terminal to another
/// program. Written when what is shown changes (a state, a value of
/// another whole percent), and every [TerminalStatus.progressRefresh]
/// while it doesn't. [child] is laid out as without it.
///
/// A copy whose progress shows in the tab while it runs:
///
/// ```dart
/// TerminalProgress(
///   value: copied / total,
///   child: Text('Copying… ${(copied / total * 100).round()} %'),
/// )
/// ```
final class TerminalProgress extends StatefulWidget {
  /// Shows [value] in [state], [ProgressState.normal] by default, while
  /// [child] is in the tree.
  const TerminalProgress({
    required this.child,
    super.key,
    this.state = ProgressState.normal,
    this.value,
  });

  /// How the progress is shown; [ProgressState.none] shows none.
  final ProgressState state;

  /// How much is done, from 0 to 1, a value beyond them counting as the
  /// nearest and one that is not a number as 0; null while not known,
  /// which the normal state shows as [ProgressState.indeterminate].
  final double? value;

  /// What is shown in the app's cells.
  final Widget child;

  @override
  State<TerminalProgress> createState() => _TerminalProgressState();
}

final class _TerminalProgressState extends State<TerminalProgress> {
  TerminalStatus? _status;

  @override
  void initState() {
    super.initState();
    _status = TerminalStatus.of(context)
      ?.._progresses.add(this)
      .._showProgress();
  }

  @override
  void didUpdateWidget(TerminalProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    _status?._showProgress();
  }

  @override
  void dispose() {
    _status
      ?.._progresses.remove(this)
      .._showProgress();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Sets the title of the terminal's window or tab to [title] while it is
/// in the tree, as Flutter's `Title` does the app's in the system, and
/// again whenever [title] changes ([TerminalStatus.title]): through the
/// backend's `WindowBackend.setTitle` (`Terminal.setTitle` saves the
/// user's title the first time and gives it back when the app ends), and
/// not at all on a backend that is none. Of several, the one mounted last
/// sets it, so of nested ones the innermost; once that one is removed,
/// the one mounted before it sets its own again. Once none is, the title
/// stays as the last one set it until the app ends. [child] is laid out
/// as without it.
///
/// ```dart
/// WindowTitle(title: 'notes.txt — editor', child: Text('…'))
/// ```
final class WindowTitle extends StatefulWidget {
  /// Sets the title to [title] while [child] is in the tree.
  const WindowTitle({required this.title, required this.child, super.key});

  /// What the terminal shows as its window's or tab's title; the control
  /// characters in it are left out (`titleSequence`).
  final String title;

  /// What is shown in the app's cells.
  final Widget child;

  @override
  State<WindowTitle> createState() => _WindowTitleState();
}

final class _WindowTitleState extends State<WindowTitle> {
  TerminalStatus? _status;

  @override
  void initState() {
    super.initState();
    _status = TerminalStatus.of(context)
      ?.._titles.add(this)
      .._showTitle();
  }

  @override
  void didUpdateWidget(WindowTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _status?._showTitle();
  }

  @override
  void dispose() {
    _status
      ?.._titles.remove(this)
      .._showTitle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
