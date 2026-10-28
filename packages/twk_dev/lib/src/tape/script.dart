/// The language of a tape, `twk tape`'s script: VHS's, a statement a
/// line, for a program run in a pseudo-terminal.
library;

import 'package:twk_core/twk_core.dart' show KeyCode, KeyEvent, Mod;

import 'svg.dart';
import 'theme.dart';

/// A tape: what it writes ([outputs]), how its terminal is set up
/// ([settings], [environment], [command]) and what it does ([steps]).
///
/// ```text
/// # a comment, on a line of its own
/// Output build/demo.cast          # asciicast v2; .svg: an animated SVG
/// Set Width 60                    # cells; Height, FontSize, Padding,
/// Set Theme dark                  # FontFamily, Framerate, Theme, and
/// Set TypingSpeed 80ms            # TypingSpeed and WaitTimeout anywhere
/// Env NAME "value"
/// Run dart example/tally.dart     # the program; sh by default
/// Wait /q quit/                   # Wait+Line, Wait@5s, Wait "text"
/// Type "+"                        # Type@200ms
/// Down 2                          # Enter, Tab, Space, Ctrl+C, Alt+x, ...
/// Sleep 1.5s                      # 500ms, 2 (seconds), 1m
/// Hide                            # Show
/// Screenshot build/counted.svg
/// ```
final class Tape {
  Tape._(
    this.name,
    this.outputs,
    this.settings,
    this.environment,
    this.command,
    this.steps,
  );

  /// The tape in [source]; [name] is what its errors start with (its
  /// path). A [FormatException] that says on which line what is wrong.
  factory Tape.parse(String source, {String name = 'tape'}) =>
      _Parser(name).parse(source);

  /// What the tape's errors start with: its path.
  final String name;

  /// The files written once the tape ran: `.cast` asciicast v2, `.svg`
  /// an animated SVG; in order.
  final List<String> outputs;

  /// The terminal's size, its colours and how its SVG is drawn, as the
  /// `Set`s before the first step set them.
  final TapeSettings settings;

  /// What `Env` added to the program's environment.
  final Map<String, String> environment;

  /// The program and its arguments, null for none (`sh`).
  final List<String>? command;

  /// What the tape does, in order.
  final List<TapeStep> steps;
}

/// What the `Set`s before the first step set: the terminal's size, its
/// colours and how its SVG is drawn.
final class TapeSettings {
  /// The settings of a tape that sets none but those given: a dark
  /// terminal of 80 × 24 cells, its SVG at 16 pixels a cell's height and
  /// 50 frames a second.
  const TapeSettings({
    this.width = 80,
    this.height = 24,
    this.theme = TapeTheme.dark,
    this.fontSize = 16,
    this.fontFamily = SvgLook.defaultFontFamily,
    this.padding,
    this.framerate = 50,
  });

  /// The terminal's width, in cells.
  final int width;

  /// The terminal's height, in cells.
  final int height;

  /// The terminal's colours (`Set Theme`).
  final TapeTheme theme;

  /// The SVG's font size, in pixels.
  final double fontSize;

  /// The SVG's font, a CSS `font-family`.
  final String fontFamily;

  /// The SVG's padding around the screen, in pixels; the font size when
  /// null.
  final double? padding;

  /// The most frames a second the animated SVG takes.
  final int framerate;
}

/// A statement of a tape that does something, from its [line] (from 1).
sealed class TapeStep {
  /// A step of [line].
  const TapeStep(this.line);

  /// The line of the tape the statement is on, from 1.
  final int line;
}

/// Types [text], a character each [delay] (the typing speed when null).
final class TypeStep extends TapeStep {
  /// `Type "text"`, `Type@delay "text"`.
  const TypeStep(super.line, this.text, {this.delay});

  /// What is typed.
  final String text;

  /// The time before each character; null for the typing speed.
  final Duration? delay;
}

/// Presses [key] [count] times, each after [delay] (the typing speed when
/// null); [name] is how the tape wrote it.
final class KeyStep extends TapeStep {
  /// `Down`, `Ctrl+C`, `Enter@200ms 3`.
  const KeyStep(super.line, this.name, this.key, {this.count = 1, this.delay});

  /// The key as the tape wrote it: `Ctrl+C`.
  final String name;

  /// The key pressed, sent as a terminal sends it.
  final KeyEvent key;

  /// How many times it is pressed.
  final int count;

  /// The time before each press; null for the typing speed.
  final Duration? delay;
}

/// Waits [duration].
final class SleepStep extends TapeStep {
  /// `Sleep 1.5s`.
  const SleepStep(super.line, this.duration);

  /// How long it waits.
  final Duration duration;
}

/// Where a [WaitStep] looks: the whole screen or the cursor's row.
enum WaitScope {
  /// Every row of the screen, as one text, a line each (`Wait`).
  screen,

  /// The row the cursor is on (`Wait+Line`).
  line,
}

/// Waits until [pattern] matches the screen's text ([scope]), at most
/// [timeout] (the tape's `WaitTimeout` when null); [source] is how the
/// tape wrote the pattern.
final class WaitStep extends TapeStep {
  /// `Wait /pattern/`, `Wait+Line@5s "text"`.
  const WaitStep(
    super.line,
    this.pattern,
    this.source, {
    this.scope = WaitScope.screen,
    this.timeout,
  });

  /// What is waited for: a regular expression, or the text of a quoted
  /// string matched as it is.
  final RegExp pattern;

  /// The pattern as the tape wrote it: `/q quit/`, `"Done"`.
  final String source;

  /// Where it is looked for.
  final WaitScope scope;

  /// The longest wait; null for the tape's `WaitTimeout`.
  final Duration? timeout;
}

/// Stops recording ([hide]) or records again: the time between is cut,
/// what the program wrote meanwhile shows at once.
final class HideStep extends TapeStep {
  /// `Hide` when [hide], else `Show`.
  const HideStep(super.line, {required this.hide});

  /// Whether recording stops (`Hide`) rather than goes on again (`Show`).
  final bool hide;
}

/// Writes the screen as it is to [path], a still SVG.
final class ScreenshotStep extends TapeStep {
  /// `Screenshot path.svg`.
  const ScreenshotStep(super.line, this.path);

  /// Where the SVG is written, from the directory the tape runs in.
  final String path;
}

/// `Set TypingSpeed` and `Set WaitTimeout`, which may come anywhere: the
/// [delay] of the keys typed from here on, or the [timeout] of the waits.
final class DelayStep extends TapeStep {
  /// `Set TypingSpeed` with [delay], `Set WaitTimeout` with [timeout].
  const DelayStep(super.line, {this.delay, this.timeout});

  /// The typing speed from here on; null leaves it as it is.
  final Duration? delay;

  /// The waits' timeout from here on; null leaves it as it is.
  final Duration? timeout;
}

/// A [Duration] as a tape writes it: a number of seconds, or of `ms`,
/// `s` or `m`; null for none.
Duration? parseDuration(String text) {
  final m = RegExp(r'^(\d+(?:\.\d*)?|\.\d+)(ms|s|m)?$').firstMatch(text);
  if (m == null) {
    return null;
  }
  final unit = switch (m[2]) {
    'ms' => 1e3,
    'm' => 60e6,
    _ => 1e6,
  };
  return Duration(microseconds: (double.parse(m[1]!) * unit).round());
}

/// The keys a tape presses by name.
const Map<String, KeyCode> _keys = {
  'Enter': KeyCode.enter,
  'Tab': KeyCode.tab,
  'Backspace': KeyCode.backspace,
  'Escape': KeyCode.escape,
  'Up': KeyCode.up,
  'Down': KeyCode.down,
  'Left': KeyCode.left,
  'Right': KeyCode.right,
  'Home': KeyCode.home,
  'End': KeyCode.end,
  'PageUp': KeyCode.pageUp,
  'PageDown': KeyCode.pageDown,
  'Insert': KeyCode.insert,
  'Delete': KeyCode.delete,
  'F1': KeyCode.f1,
  'F2': KeyCode.f2,
  'F3': KeyCode.f3,
  'F4': KeyCode.f4,
  'F5': KeyCode.f5,
  'F6': KeyCode.f6,
  'F7': KeyCode.f7,
  'F8': KeyCode.f8,
  'F9': KeyCode.f9,
  'F10': KeyCode.f10,
  'F11': KeyCode.f11,
  'F12': KeyCode.f12,
};

const Map<String, int> _modifiers = {
  'Ctrl': Mod.ctrl,
  'Alt': Mod.alt,
  'Shift': Mod.shift,
};

/// The statements that take `@<duration>`: the typing speed or the
/// timeout (and the keys).
const _timed = {'Type', 'Wait', 'Wait+Screen', 'Wait+Line'};

/// The statements other than keys.
const Set<String> _statements = {
  ..._timed,
  'Output',
  'Set',
  'Env',
  'Run',
  'Sleep',
  'Hide',
  'Show',
  'Screenshot',
};

/// [line] without its comment: from a `#` that starts a word, not in a
/// quoted word or a Wait's regular expression, to the end.
String _uncommented(String line) {
  final waits = line.trimLeft().startsWith('Wait');
  var start = true;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c.trim().isEmpty) {
      start = true;
      continue;
    }
    if (start && c == '#') {
      return line.substring(0, i);
    }
    if (start && (c == '"' || c == "'" || c == '`' || waits && c == '/')) {
      var end = i + 1;
      while (end < line.length && line[end] != c) {
        end += c == '/' && line[end] == r'\' ? 2 : 1;
      }
      i = end;
    }
    start = false;
  }
  return line;
}

/// A word of a statement: its text, quoted or a `/regular expression/`.
typedef _Word = ({String text, bool quoted, bool regex});

final class _Parser {
  _Parser(this.name);

  final String name;

  final _outputs = <String>[];
  final _environment = <String, String>{};
  List<String>? _command;
  final _steps = <TapeStep>[];
  var _settings = const TapeSettings();

  var _line = 0;

  Tape parse(String source) {
    final lines = source.split(RegExp(r'\r?\n'));
    for (var i = 0; i < lines.length; i++) {
      _line = i + 1;
      final text = _uncommented(lines[i]).trim();
      if (text.isEmpty) {
        continue;
      }
      final space = text.indexOf(RegExp(r'\s'));
      final head = space < 0 ? text : text.substring(0, space);
      final rest = space < 0 ? '' : text.substring(space).trimLeft();
      _statement(head, rest);
    }
    return Tape._(
      name,
      List.unmodifiable(_outputs),
      _settings,
      Map.unmodifiable(_environment),
      _command,
      List.unmodifiable(_steps),
    );
  }

  Never _error(String message) =>
      throw FormatException('$name:$_line: $message');

  void _statement(String head, String rest) {
    final at = head.indexOf('@');
    final word = at < 0 ? head : head.substring(0, at);
    final Duration? delay;
    if (at < 0) {
      delay = null;
    } else {
      delay = parseDuration(head.substring(at + 1));
      if (delay == null) {
        _error('"${head.substring(at + 1)}" after @ is no duration');
      }
      if (!_timed.contains(word) && _key(word) == null) {
        _error(
          _statements.contains(word)
              ? '$word takes no @<duration>'
              : 'no statement "$word"',
        );
      }
    }
    switch (word) {
      case 'Output':
        final path = _one(rest, 'Output', 'a file');
        if (!path.endsWith('.cast') && !path.endsWith('.svg')) {
          _error('Output writes a .cast or an .svg file, not $path');
        }
        _outputs.add(path);
      case 'Set':
        _set(rest);
      case 'Env':
        _beforeSteps('Env');
        final words = _words(rest);
        if (words.length != 2) {
          _error('Env takes a name and a value');
        }
        _environment[words[0].text] = words[1].text;
      case 'Run':
        _beforeSteps('Run');
        if (_command != null) {
          _error('a tape runs one program');
        }
        final words = _words(rest);
        if (words.isEmpty) {
          _error('Run takes a program and its arguments');
        }
        _command = [for (final w in words) w.text];
      case 'Type':
        final words = _words(rest);
        if (words.isEmpty || words.any((w) => !w.quoted)) {
          _error('Type takes quoted text: Type "text"');
        }
        _steps.add(
          TypeStep(_line, words.map((w) => w.text).join(), delay: delay),
        );
      case 'Sleep':
        final text = _one(rest, 'Sleep', 'a duration');
        final duration = parseDuration(text);
        if (duration == null) {
          _error('"$text" is no duration: 500ms, 1.5s, 2, 1m');
        }
        _steps.add(SleepStep(_line, duration));
      case 'Hide' || 'Show':
        _none(rest, word);
        _steps.add(HideStep(_line, hide: word == 'Hide'));
      case 'Screenshot':
        final path = _one(rest, 'Screenshot', 'a file');
        if (!path.endsWith('.svg')) {
          _error('Screenshot writes an .svg file, not $path');
        }
        _steps.add(ScreenshotStep(_line, path));
      case 'Wait' || 'Wait+Screen' || 'Wait+Line':
        _wait(word, rest, delay);
      default:
        final key = _key(word);
        if (key == null) {
          _error('no statement "$word"');
        }
        final words = _words(rest);
        var count = 1;
        if (words.length > 1 || words.any((w) => w.quoted || w.regex)) {
          _error('$word takes how many times, if anything');
        } else if (words.length == 1) {
          final n = int.tryParse(words.single.text);
          if (n == null || n < 1) {
            _error('"${words.single.text}" is no count of presses');
          }
          count = n;
        }
        _steps.add(KeyStep(_line, word, key, count: count, delay: delay));
    }
  }

  void _wait(String word, String rest, Duration? timeout) {
    final words = _words(rest, regex: true);
    if (words.length != 1 || !words.single.quoted && !words.single.regex) {
      _error('$word takes a /regular expression/ or "text"');
    }
    final w = words.single;
    final RegExp pattern;
    try {
      pattern = RegExp(
        w.regex ? w.text : RegExp.escape(w.text),
        multiLine: true,
      );
    } on FormatException catch (e) {
      _error('/${w.text}/ is no regular expression: ${e.message}');
    }
    _steps.add(
      WaitStep(
        _line,
        pattern,
        w.regex ? '/${w.text}/' : '"${w.text}"',
        scope: word == 'Wait+Line' ? WaitScope.line : WaitScope.screen,
        timeout: timeout,
      ),
    );
  }

  void _set(String rest) {
    final space = rest.indexOf(RegExp(r'\s'));
    final setting = space < 0 ? rest : rest.substring(0, space);
    final value = space < 0 ? '' : rest.substring(space).trim();
    if (value.isEmpty) {
      _error('Set $setting takes a value');
    }
    // the theme's JSON is the rest of the line
    final text = setting == 'Theme' && value.startsWith('{')
        ? value
        : _one(value, 'Set $setting', 'a value');
    Duration duration() =>
        parseDuration(text) ?? _error('"$text" is no duration: 50ms, 0.1s');
    switch (setting) {
      case 'TypingSpeed':
        _steps.add(DelayStep(_line, delay: duration()));
        return;
      case 'WaitTimeout':
        _steps.add(DelayStep(_line, timeout: duration()));
        return;
    }
    _beforeSteps('Set $setting');
    int cells(int max) {
      final n = int.tryParse(text);
      if (n == null || n < 1 || n > max) {
        _error('Set $setting takes a number of cells from 1 to $max');
      }
      return n;
    }

    double pixels() {
      final n = double.tryParse(text);
      if (n == null ||
          n < 0 ||
          !n.isFinite ||
          setting == 'FontSize' && n == 0) {
        _error('Set $setting takes a number of pixels');
      }
      return n;
    }

    final s = _settings;
    _settings = switch (setting) {
      'Width' => _with(s, width: cells(1000)),
      'Height' => _with(s, height: cells(1000)),
      'FontSize' => _with(s, fontSize: pixels()),
      'Padding' => _with(s, padding: pixels()),
      'FontFamily' => _with(s, fontFamily: text),
      'Framerate' => _with(s, framerate: cells(240)),
      'Theme' => _with(s, theme: _theme(text)),
      _ => _error(
        'no setting "$setting"; there are Width, Height, Theme, FontSize, '
        'FontFamily, Padding, Framerate, TypingSpeed and WaitTimeout',
      ),
    };
  }

  TapeTheme _theme(String text) {
    try {
      return TapeTheme.parse(text);
    } on FormatException catch (e) {
      _error(e.message);
    }
  }

  static TapeSettings _with(
    TapeSettings s, {
    int? width,
    int? height,
    TapeTheme? theme,
    double? fontSize,
    String? fontFamily,
    double? padding,
    int? framerate,
  }) => TapeSettings(
    width: width ?? s.width,
    height: height ?? s.height,
    theme: theme ?? s.theme,
    fontSize: fontSize ?? s.fontSize,
    fontFamily: fontFamily ?? s.fontFamily,
    padding: padding ?? s.padding,
    framerate: framerate ?? s.framerate,
  );

  void _beforeSteps(String what) {
    if (_steps.any((s) => s is! DelayStep)) {
      _error(
        '$what comes before the first Type, key, Sleep, Wait, Hide, '
        'Show or Screenshot',
      );
    }
  }

  /// The key [word] names, with its modifiers: `Enter`, `Ctrl+C`,
  /// `Alt+Shift+Tab`, `Space`; null for none.
  static KeyEvent? _key(String word) {
    var rest = word;
    var mods = 0;
    while (true) {
      final plus = rest.indexOf('+');
      if (plus <= 0 || plus == rest.length - 1) {
        break;
      }
      final mod = _modifiers[rest.substring(0, plus)];
      if (mod == null) {
        return null;
      }
      mods |= mod;
      rest = rest.substring(plus + 1);
    }
    if (_keys[rest] case final code?) {
      return KeyEvent(code, modifiers: mods);
    }
    if (rest == 'Space') {
      return KeyEvent(KeyCode.char, char: ' ', modifiers: mods);
    }
    // a character, with a modifier: Ctrl+C is Ctrl and c
    if (mods != 0 && rest.runes.length == 1) {
      final char = mods & Mod.shift == 0 ? rest.toLowerCase() : rest;
      return KeyEvent(KeyCode.char, char: char, modifiers: mods);
    }
    return null;
  }

  String _one(String rest, String what, String takes) {
    final words = _words(rest);
    if (words.length != 1 || words.single.regex) {
      _error('$what takes $takes');
    }
    return words.single.text;
  }

  void _none(String rest, String what) {
    if (rest.isNotEmpty) {
      _error('$what takes nothing');
    }
  }

  /// The words of [text]: bare, quoted with `"`, `'` or `` ` `` (no
  /// escapes: a quote of another kind goes inside), or with [regex] a
  /// `/regular expression/` (`\/` a slash in it).
  List<_Word> _words(String text, {bool regex = false}) {
    final words = <_Word>[];
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      final start = i;
      if (c == '"' || c == "'" || c == '`') {
        final end = text.indexOf(c, i + 1);
        if (end < 0) {
          _error('a string with no closing $c');
        }
        words.add((
          text: text.substring(i + 1, end),
          quoted: true,
          regex: false,
        ));
        i = end + 1;
      } else if (regex && c == '/') {
        var end = i + 1;
        while (end < text.length && text[end] != '/') {
          end += text[end] == r'\' ? 2 : 1;
        }
        if (end >= text.length) {
          _error('a regular expression with no closing /');
        }
        words.add((
          text: text.substring(i + 1, end),
          quoted: false,
          regex: true,
        ));
        i = end + 1;
      } else {
        var end = i;
        while (end < text.length && text[end].trim().isNotEmpty) {
          end++;
        }
        words.add((text: text.substring(i, end), quoted: false, regex: false));
        i = end;
      }
      if (i < text.length && text[i].trim().isNotEmpty) {
        _error('no space after ${text.substring(start, i)}');
      }
    }
    return words;
  }
}
