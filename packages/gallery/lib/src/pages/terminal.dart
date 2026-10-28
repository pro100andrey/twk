// The Terminal group of the gallery.
import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_term/twk_term.dart';

import '../../scripted_shell.dart';
import '../motion.dart';
import '../page.dart';

/// The pages of the Terminal group that draw.
final terminalPages = <GalleryPage>[_terminalView];

/// The view's width at most: a terminal of 80 columns inside its border.
const _boxWidth = 82;

/// The view's size in [room]: all of it, a terminal of at most 80 × 24
/// inside its border; 82 × 26 before the stage was laid out, as the
/// design's.
(int, int) _boxSize(StageRoom room) => room == StageRoom.unbounded
    ? (_boxWidth, 26)
    : (_clamp(room.width, 24, _boxWidth), _clamp(room.height, 6, 26));

int _clamp(int v, int low, int high) => math.max(low, math.min(high, v));

/// Keys the gallery keeps: Tab and Esc move the focus, Ctrl+P searches.
const _ignored = ['tab', 'shift+tab', 'escape', 'ctrl+p'];

/// The Code's line on [_ignored].
const _ignoredComment =
    "        // the gallery's own: Tab and Esc move the focus, Ctrl+P "
    'searches';

final _terminalView = GalleryPage(
  group: 'Terminal',
  title: 'TerminalView',
  about:
      "A program's terminal in a view: keys, pastes, the mouse and resizes "
      'sent to it, its scrollback scrolled; here a scripted shell, not a '
      'program in a pseudo-terminal.',
  options: const [
    // the lines a turn of the wheel scrolls the scrollback: 3, the
    // default, as most terminals do
    ChoiceOption('wheel', 'wheel lines', values: [1, 3, 10], initial: 3),
  ],
  // its terminal's 80 columns: the options go under the stage where the
  // inspector beside it would leave fewer (120x36), not cut htop's bar
  minWidth: _boxWidth,
  build: (context, o) => LayoutBuilder(
    builder: (context, c) {
      const most = 1 << 20;
      final (w, h) = _boxSize(
        StageRoom(
          c.maxW < BoxConstraints.unbounded ? c.maxW : most,
          c.maxH < BoxConstraints.unbounded ? c.maxH : most,
        ),
      );
      return _Shell(width: w, height: h, wheelLines: o.choice<int>('wheel'));
    },
  ),
  heightIn: (o, room) => _boxSize(room).$2,
  codeIn: (o, room) {
    final (w, h) = _boxSize(room);
    final wheel = o.choice<int>('wheel');
    return [
      "// ScriptedShell is the gallery's own: a fake bash at the other end of",
      '// a byte link, which writes what bash would and answers the keys it',
      '// is sent (ls, git log, dart test, htop, clear, help), typing its',
      '// script until a key takes it over. A real shell is',
      "// TerminalSession.start('bash', const []).",
      "import 'scripted_shell.dart';",
      '',
      'late var _session = _start();',
      "final _focus = FocusNode(debugLabel: 'shell');",
      "var _title = '';",
      'Timer? _restart;',
      '',
      'TerminalSession _start() {',
      '  final shell = ScriptedShell(autoplay: true);',
      '  final session = TerminalSession(',
      '    output: shell.output,',
      '    input: shell.input,',
      '    onResize: shell.resize,',
      '  );',
      "  // when it exits: 'ended' for 700 ms, then another shell",
      '  session.exitCode.then((_) {',
      '    if (!mounted) return;',
      "    setState(() => _title = 'ended');",
      '    _restart = Timer(const Duration(milliseconds: 700), () {',
      '      final ended = _session;',
      '      setState(() {',
      '        _session = _start();',
      "        _title = '';",
      '      });',
      '      ended.dispose();',
      '    });',
      '  });',
      '  return session;',
      '}',
      '',
      '@override',
      'void initState() {',
      '  super.initState();',
      '  _focus.addListener(() => setState(() {}));',
      '}',
      '',
      '@override',
      'void dispose() {',
      '  _restart?.cancel();',
      '  _session.dispose();',
      '  _focus.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  final theme = Theme.of(context);',
      '  final focused = _focus.hasFocus;',
      '  return SizedBox(',
      '    width: $w,',
      '    height: $h,',
      '    child: Box(',
      '      border: .all(',
      '        type: .rounded,',
      '        style: focused ? theme.primary : theme.border,',
      '      ),',
      '      titles: [',
      '        BorderTitle(',
      r"          ' ${_title.isEmpty ? 'shell' : _title} ',",
      '          style: focused ? theme.text : theme.muted,',
      '        ),',
      '      ],',
      '      child: TerminalView(',
      '        session: _session,',
      '        focusNode: _focus,',
      _ignoredComment,
      "        ignoredKeys: const ['tab', 'shift+tab', 'escape', 'ctrl+p'],",
      if (wheel != 3) '        wheelLines: $wheel,',
      '        onTitleChanged: (title) => setState(() => _title = title),',
      '      ),',
      '    ),',
      '  );',
      '}',
    ].join('\n');
  },
);

/// The Code's view of a ScriptedShell, on the gallery's clock: the shell
/// is run to the clock's time at each build, so that a route's `t=` shows
/// that moment. The script plays again every [ScriptedShell.cycle] ms in
/// a new shell, as the design's does, until a key takes it over; a shell
/// that exited shows `ended` for 700 ms, then another starts.
final class _Shell extends StatefulWidget {
  const _Shell({
    required this.width,
    required this.height,
    required this.wheelLines,
  });

  final int width;
  final int height;

  /// The lines a turn of the wheel scrolls, as [TerminalView.wheelLines].
  final int wheelLines;

  @override
  State<_Shell> createState() => _ShellState();
}

final class _ShellState extends State<_Shell> {
  late final _motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });
  final _focus = FocusNode(debugLabel: 'shell');

  ScriptedShell? _shell;
  TerminalSession? _session;

  /// The sessions replaced, disposed once the view has let them go.
  final _retired = <TerminalSession>[];

  /// The size of the terminal of the shell.
  (int, int)? _size;

  /// Whether the script plays: until a key takes the shell over.
  var _auto = true;

  /// The clock's time the script started playing at.
  var _autoStart = 0;

  /// The clock's time the shell's time 0 is at.
  var _base = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _motion.dispose();
    _session?.dispose();
    for (final s in _retired) {
      s.dispose();
    }
    _shell?.close();
    _focus.dispose();
    super.dispose();
  }

  int _clockNow() => Clock.of(context).now(context).inMilliseconds;

  /// A new shell from [base] on, its script played where [auto].
  void _start(int base, {required bool auto}) {
    final (cols, rows) = _size!;
    _shell?.close();
    final shell = _shell =
        ScriptedShell(autoplay: auto, width: cols, height: rows, manual: true)
          ..clock = (() => _clockNow() - _base)
          ..onChange = () {
            if (mounted) {
              setState(() {});
            }
          };
    if (_session case final old?) {
      _retired.add(old);
    }
    _session = TerminalSession(
      output: shell.output,
      input: shell.input,
      onResize: shell.resize,
      width: cols,
      height: rows,
    );
    _base = base;
  }

  /// The shell run to [ms] on the clock; asks for a build at the next
  /// thing it does.
  void _advance(int ms) {
    final size = (widget.width - 2, widget.height - 2);
    final cycle = ScriptedShell.cycle;
    if (_size != size || _shell == null) {
      _size = size;
      _auto = true;
      _autoStart = 0;
      _start(ms - (ms - _autoStart) % cycle, auto: true);
    }
    var shell = _shell!;
    if (_auto && !shell.autoplay) {
      // a key took it over
      _auto = false;
    }
    if (_auto) {
      final base = _autoStart + (ms - _autoStart) ~/ cycle * cycle;
      if (base != _base) {
        _start(base, auto: true);
        shell = _shell!;
      }
    }
    final rel = math.max(0, ms - _base);
    shell.runTo(rel);
    // a shell that ended: another, as the Code's exitCode.then does
    if (shell.endedAt case final ended?) {
      if (rel >= ended + 700) {
        _auto = true;
        _autoStart = ms;
        _start(ms, auto: true);
        _shell!.runTo(0);
      } else {
        _motion.wakeAt(Duration(milliseconds: _base + ended + 700));
      }
    }
    if (_shell!.next case final next?) {
      _motion.wakeAt(Duration(milliseconds: _base + next));
    }
    if (_auto) {
      _motion.wakeAt(Duration(milliseconds: _base + cycle));
    }
  }

  @override
  Widget build(BuildContext context) {
    _motion.begin(context);
    for (final s in _retired) {
      s.dispose();
    }
    _retired.clear();
    _advance(_motion.now.inMilliseconds);
    _motion.end();
    final theme = Theme.of(context);
    final focused = _focus.hasFocus;
    final session = _session!;
    final title = _shell!.endedAt != null
        ? 'ended'
        : session.title.isEmpty
        ? 'shell'
        : session.title;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Box(
        border: Border.all(
          type: BorderType.rounded,
          style: focused ? theme.primary : theme.border,
        ),
        titles: [
          BorderTitle(' $title ', style: focused ? theme.text : theme.muted),
        ],
        // the design's hints of what the shell does
        child: PageHints(
          hints: _shell!.endedAt != null
              ? const []
              : _auto
              ? const [('type', 'take over'), ('wheel', 'scroll back')]
              : switch (_shell!.running) {
                  'htop' => const [
                    ('q', 'quit htop'),
                    ('↑↓', 'select'),
                    ('wheel', '↑↓'),
                  ],
                  null => const [
                    ('help', 'commands'),
                    ('↑↓', 'history'),
                    ('wheel', 'scroll back'),
                  ],
                  _ => const [('ctrl+c', 'stop')],
                },
          child: TerminalView(
            session: session,
            focusNode: _focus,
            ignoredKeys: _ignored,
            wheelLines: widget.wheelLines,
            onTitleChanged: (_) => setState(() {}),
          ),
        ),
      ),
    );
  }
}
