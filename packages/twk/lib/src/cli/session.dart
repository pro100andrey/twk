/// The inline twk app a [Cli] holds in the interactive mode: [CliSession],
/// which shows what is live ([CliSession.mount]) in its region and commits
/// finished output above it ([CliSession.commit]).
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import '../../log.dart';
import '../../twk.dart';

import 'lines.dart';
import 'terminal.dart';

/// One inline twk app on a [CliTerminal] for the life of a [Cli]: stdin is
/// single-subscription, so the interactive mode opens it the first time
/// something needs it and keeps it until [close].
///
/// The app's root is a host that mounts what is live ([mount]: a prompt, a
/// progress) in the inline region, one below another, those mounted as
/// `last` (progress) below the others, and commits finished
/// output ([commit]) to the terminal's history above it (`Static`). With
/// nothing live the region is empty. A Ctrl+C that nothing live takes ends
/// the app, the terminal restored, and the session calls its
/// `onInterrupt`.
///
/// This is the seam the prompts and progress of the package build on, and
/// a program reaches it by [Cli.session] (in the interactive mode only:
/// check [Cli.mode]) to show a live widget below the lines it logs. A
/// program that has no need of it talks to its [Cli]: [Cli.show],
/// [Cli.tasks] and [Cli.progress] work in every mode.
///
/// Several widgets may be mounted at once, one below another. A session
/// that [isOpen] no more, closed by the program or ended by a Ctrl+C,
/// takes nothing: [mount] returns a [CliLive] that is not [CliLive.isMounted]
/// and [commit] completes at once, both without an error; [Cli.session]
/// opens a new one for the next asking. Once the [Cli] is closed
/// ([Cli.close], which [Cli.run] calls) its session ends with it and
/// [Cli.session] throws a [StateError]. Unlike [Cli.tasks] and
/// [Cli.progress], mounting writes no progress report to the terminal
/// (OSC 9;4).
final class CliSession {
  CliSession._(
    this._binding,
    this._theme,
    this._strings,
    this._onInterrupt,
    this._onWarning,
  );

  /// Opens the session on [terminal]'s inline terminal
  /// ([CliTerminal.openInline]), the app's frames timed by its clock;
  /// widgets are shown under [theme] where there is one, else under the
  /// terminal's colors, and in the words [strings]. [onInterrupt] is
  /// called once the app has ended on a Ctrl+C nothing live took.
  /// [onWarning] gets what the session warns
  /// of (a list committed with items and no rows); without one it goes to
  /// `log` as a warning.
  static Future<CliSession> open(
    CliTerminal terminal, {
    ThemeData? theme,
    TwkStrings strings = const TwkStrings(),
    void Function()? onInterrupt,
    void Function(String message)? onWarning,
  }) async {
    final clock = terminal.clock;
    final backend = await clock.run(terminal.openInline);
    final binding = clock.run(
      () => AppBinding(
        backend,
        clearInlineOnExit: true,
        clock: clock.stopwatch(),
      ),
    );
    final session = CliSession._(
      binding,
      theme,
      strings,
      onInterrupt,
      onWarning,
    );
    session._running = clock.run(() => binding.run(_Host(session)));
    unawaited(session._watch());
    return session;
  }

  final AppBinding _binding;
  final ThemeData? _theme;
  final TwkStrings _strings;
  final void Function()? _onInterrupt;
  final void Function(String message)? _onWarning;
  late final Future<void> _running;

  final _changes = _Changes();

  // what is committed, by index for the Static; a commit written is null
  final _commits = <_Commit?>[];
  final _pending = <_Commit>{};

  // what is live, in the order it was mounted
  final _live = <CliLive>[];
  var _nextLive = 0;

  var _closing = false;
  var _ended = false;
  final _done = Completer<void>();

  /// Whether the app still runs: neither [close]d nor ended by Ctrl+C or
  /// an error.
  bool get isOpen => !_ended;

  /// Whether the terminal shows the underline styles, as the session's
  /// probe of it found ([TerminalCaps.styledUnderlines]): what it
  /// declares, its environment, and its secondary device attributes,
  /// which tell Terminal.app over ssh too.
  bool get styledUnderlines =>
      _binding.twkApp.terminal.info.caps.styledUnderlines;

  /// Completes once the app has ended and the terminal is restored, with
  /// the error that ended it where one did.
  Future<void> get done => _done.future;

  /// The binding of the app, for what reaches it from outside a widget.
  AppBinding get binding => _binding;

  /// Commits [widget] to the terminal's history above the region: laid out
  /// at the terminal's width, as tall as it is there, written by the next
  /// frame. Completes once its rows are written; at once once the session
  /// has ended.
  Future<void> commit(Widget widget) {
    if (_ended) {
      return Future.value();
    }
    final commit = _Commit(_commits.length, widget);
    _commits.add(commit);
    _pending.add(commit);
    _changed();
    return commit.written.future;
  }

  /// Mounts [widget] in the region below what is live already, until
  /// [CliLive.remove]; what is committed meanwhile goes above it.
  ///
  /// With [last] it is kept at the bottom of the region: what is mounted
  /// later without it goes above it, as a prompt asked while a progress
  /// runs does.
  CliLive mount(Widget widget, {bool last = false}) {
    final live = CliLive._(this, _nextLive++, widget, last: last);
    if (!_ended) {
      _live.add(live);
      _changed();
    }
    return live;
  }

  void _warn(String message) {
    if (_onWarning case final onWarning?) {
      onWarning(message);
    } else {
      log(message, level: LogLevel.warning);
    }
  }

  void _changed() {
    if (!_ended) {
      _changes.changed();
    }
  }

  void _written(_Commit commit) {
    _commits[commit.index] = null;
    if (_pending.remove(commit)) {
      commit.written.complete();
    }
  }

  /// Hands the terminal to another program while [run] runs and takes it
  /// back after (`TwkApp.suspend`): the region stays on the screen with the
  /// cursor on the line below it, raw mode off and input paused, the frames
  /// waiting, until [run] completes; then the region is drawn again below
  /// what the other program printed. Returns what [run] returns, or throws
  /// what it throws, once the terminal is back. Once the session has ended,
  /// [run] just runs.
  Future<T> suspend<T>(Future<T> Function() run) =>
      _ended ? run() : _binding.twkApp.suspend(run);

  /// Ends the app once what is committed is written: the region is
  /// cleared and the terminal restored. Completes once it is, with the
  /// error that ended the app where one did; calling it again waits for
  /// the same.
  Future<void> close() async {
    if (!_ended && !_closing) {
      _closing = true;
      // the frames that build what is committed come first
      while (_pending.isNotEmpty && !_ended) {
        await Future.any([
          Future.wait([for (final c in _pending) c.written.future]),
          done,
        ]);
      }
      _binding.quit();
    }
    return done;
  }

  Future<void> _watch() async {
    Object? error;
    StackTrace? stack;
    try {
      await _running;
    } on Object catch (e, s) {
      error = e;
      stack = s;
    }
    _ended = true;
    _live.clear();
    for (final commit in [..._pending]) {
      commit.written.complete();
    }
    _pending.clear();
    if (error != null) {
      _done.completeError(error, stack);
    } else {
      _done.complete();
    }
    if (error == null && !_closing) {
      // Ctrl+C that nothing took ended the app: the binding's own
      _onInterrupt?.call();
    }
  }
}

/// A widget mounted in the region of a [CliSession] ([CliSession.mount]).
final class CliLive {
  CliLive._(this._session, this._id, this._widget, {required this._last});

  final CliSession _session;
  final int _id;
  final bool _last;
  Widget _widget;
  var _removed = false;

  /// Whether it is still in the region.
  bool get isMounted => !_removed && _session._live.contains(this);

  /// Shows [widget] in its place from the next frame on: one of the same
  /// type keeps its state.
  void update(Widget widget) {
    if (_removed) {
      return;
    }
    _widget = widget;
    _session._changed();
  }

  /// Takes it out of the region; what it showed is gone with it.
  void remove() {
    if (_removed) {
      return;
    }
    _removed = true;
    if (_session._live.remove(this)) {
      _session._changed();
    }
  }
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

final class _Commit {
  _Commit(this.index, this.widget);

  final int index;
  final Widget widget;
  final written = Completer<void>();
}

/// The root of the session's app: the commits in a Static, what is live
/// below it.
final class _Host extends StatelessWidget {
  const _Host(this.session);

  final CliSession session;

  @override
  Widget build(BuildContext context) {
    final host = ListenableBuilder(
      listenable: session._changes,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Static<_Commit?>(
            items: session._commits,
            builder: (context, commit) =>
                commit == null ? const SizedBox() : _Written(commit, session),
          ),
          for (final live in session._live)
            if (!live._last) _Live(live._widget, key: ValueKey(live._id)),
          for (final live in session._live)
            if (live._last) _Live(live._widget, key: ValueKey(live._id)),
        ],
      ),
    );
    // the Overlay a Tooltip, a Popover or a menu in what is shown needs, as
    // App places one around an app
    final overlay = Overlay(child: host);
    final theme = session._theme;
    return Localizations(
      strings: session._strings,
      child: theme == null ? overlay : Theme(data: theme, child: overlay),
    );
  }
}

final class _Live extends StatelessWidget {
  const _Live(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A commit, which is written once the Static unmounts it.
final class _Written extends StatefulWidget {
  const _Written(this.commit, this.session);

  final _Commit commit;
  final CliSession session;

  @override
  State<_Written> createState() => _WrittenState();
}

final class _WrittenState extends State<_Written> {
  @override
  void dispose() {
    widget.session._written(widget.commit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _WarnOfNoRows(
    onNoRows: () => widget.session._warn(noRowsWarning),
    child: widget.commit.widget,
  );
}

/// [child], as big as it is, which says once when a list of items in it was
/// laid out with no rows (a commit is as tall as its max intrinsic height,
/// which a list answers 0 to).
final class _WarnOfNoRows extends SingleChildRenderObjectWidget {
  const _WarnOfNoRows({required this.onNoRows, super.child});

  final void Function() onNoRows;

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  _RenderWarnOfNoRows createRenderObject(BuildContext context) =>
      _RenderWarnOfNoRows(onNoRows);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWarnOfNoRows renderObject,
  ) => renderObject.onNoRows = onNoRows;
}

final class _RenderWarnOfNoRows extends RenderObject
    with RenderObjectWithChildMixin {
  _RenderWarnOfNoRows(this.onNoRows);

  void Function() onNoRows;
  var _told = false;

  @override
  void performLayout(BoxConstraints c) {
    final child = this.child;
    if (child == null) {
      width = c.minW;
      height = c.minH;
      return;
    }
    child.layout(c, parentUsesSize: true);
    width = child.width;
    height = child.height;
    if (!_told && hasListWithoutRows(child)) {
      _told = true;
      onNoRows();
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) =>
      child?.getMinIntrinsicWidth(height) ?? 0;

  @override
  int computeMaxIntrinsicWidth(int height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  int computeMinIntrinsicHeight(int width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  int computeMaxIntrinsicHeight(int width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void paint(PaintContext ctx) {
    final child = this.child;
    if (child != null) {
      paintChild(ctx, child);
    }
  }
}
