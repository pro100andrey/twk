/// The inline twk app a [Cli] holds in the interactive mode: [CliSession],
/// which shows what is live ([CliSession.mount]) in its region and commits
/// finished output above it ([CliSession.commit]).
///
/// @docImport 'cli.dart';
library;

import 'dart:async';

import 'package:twk/twk.dart';

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
/// This is the seam the prompts and progress of the package build on; a
/// program talks to its [Cli].
final class CliSession {
  CliSession._(this._binding, this._theme, this._onInterrupt);

  /// Opens the session on [terminal]'s inline terminal
  /// ([CliTerminal.openInline]), the app's frames timed by its clock;
  /// widgets are shown under [theme] where there is one, else under the
  /// terminal's colors. [onInterrupt] is called once the app has ended on
  /// a Ctrl+C nothing live took.
  static Future<CliSession> open(
    CliTerminal terminal, {
    ThemeData? theme,
    void Function()? onInterrupt,
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
    final session = CliSession._(binding, theme, onInterrupt);
    session._running = clock.run(() => binding.run(_Host(session)));
    unawaited(session._watch());
    return session;
  }

  final AppBinding _binding;
  final ThemeData? _theme;
  final void Function()? _onInterrupt;
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
  /// declares, its environment, and whether it answered DECRQM, which
  /// tells Terminal.app over ssh too.
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
    final theme = session._theme;
    return theme == null ? host : Theme(data: theme, child: host);
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
  Widget build(BuildContext context) => widget.commit.widget;
}
