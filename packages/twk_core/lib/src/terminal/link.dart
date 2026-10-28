/// What a `Terminal` reads from and writes to: a [TerminalLink]. The
/// process's own terminal (`StdioLink`), one a `twk shell` serves over a
/// local socket (`SocketLink`), or a link a program brings to
/// `Terminal.overLink`: an SSH channel, a terminal in a browser. Nothing
/// here needs dart:io.
library;

import '../graphics.dart';
import 'sequences.dart';

// Examples can assume:
// import 'dart:async';

/// Thrown when there is no usable terminal (`Terminal.open`,
/// [TerminalLink.enterRaw]); what a link's input ends with when its far
/// end goes away (the shell serving the terminal), which `Terminal.events`
/// get.
final class TerminalException implements Exception {
  /// An exception that says [message].
  const TerminalException(this.message);

  /// What went wrong: 'not a terminal', say.
  final String message;

  /// `TerminalException: ` and the [message].
  @override
  String toString() => 'TerminalException: $message';
}

/// A terminal's input, output, size, environment and console modes: what
/// a `Terminal` runs over.
///
/// The core has the links of the process's own terminal and of a
/// `twk shell`'s; a program that serves terminals elsewhere (an SSH
/// server, a terminal in a browser) implements one and opens a `Terminal`
/// over it with `Terminal.overLink`. A link over a pair of byte streams,
/// whose far end keeps its own modes and tells its size:
///
/// ```dart
/// final class StreamLink implements TerminalLink {
///   StreamLink(this.input, this.output, this.columns, this.lines);
///
///   @override
///   final Stream<List<int>> input;
///   final StreamSink<List<int>> output;
///   @override
///   int columns;
///   @override
///   int lines;
///
///   @override
///   Map<String, String> get environment => const {'TERM': 'xterm-256color'};
///   @override
///   bool get windows => false;
///   @override
///   int? get eraseChar => 0x7F;
///   @override
///   Stream<void> get resizes => const Stream.empty();
///   @override
///   void enterRaw() {}
///   @override
///   void restore() {}
///   @override
///   void restoreWith(List<int> bytes) {}
///   @override
///   void add(List<int> bytes) => output.add(bytes);
///   @override
///   Future<void> flush() async {}
///   @override
///   Future<void> close() => output.close();
/// }
/// ```
abstract interface class TerminalLink {
  /// The environment the terminal's program sees (`TERM`, `COLORTERM`,
  /// `TERM_PROGRAM`, ...), which tells what the terminal is; over a link
  /// to a terminal elsewhere, what its end told (an SSH client's `pty-req`
  /// and `env`).
  Map<String, String> get environment;

  /// Whether the terminal is a Windows console.
  bool get windows;

  /// The number of columns the terminal has now.
  int get columns;

  /// The number of rows the terminal has now.
  int get lines;

  /// The byte the Backspace key sends as the tty sets it (0x7F, or 0x08 on
  /// some setups), known once [enterRaw] ran; null where it can't be read.
  int? get eraseChar;

  /// Raw input: no echo, no line editing and, where termios can be reached
  /// (Linux, macOS), no terminal-generated signals or flow control, so
  /// Ctrl+C, Ctrl+\, Ctrl+Z, Ctrl+S and Ctrl+Q are keys; on Windows VT
  /// input and output. Again after [restore], as found by then. Throws
  /// [TerminalException] when that can't be done. Nothing where the far
  /// end sets its modes itself (an SSH client).
  void enterRaw();

  /// Puts back what [enterRaw] changed. Must run before the subscription
  /// to [input] is cancelled: that closes stdin, whose modes can then no
  /// longer be set.
  void restore();

  /// The terminal's input; listened to once. Ends with a
  /// [TerminalException] when the far end goes away.
  Stream<List<int>> get input;

  /// Writes [bytes], which are kept until a [flush] completes. Dropped once
  /// the far end went away.
  void add(List<int> bytes);

  /// Completes when everything added so far reached the terminal's OS
  /// side, at once when the far end went away. Not called again before it
  /// completes.
  Future<void> flush();

  /// An event whenever the size may have changed: SIGWINCH, a poll every
  /// 100 ms on Windows, the shell's report, an SSH `window-change`.
  Stream<void> get resizes;

  /// [bytes] put the terminal back as it was if this process goes away
  /// without restoring it: a `twk shell` writes them then. A link that
  /// ends with this process can do nothing about that and ignores them.
  void restoreWith(List<int> bytes);

  /// Ends the link, once the input subscription is cancelled: the last
  /// thing `Terminal.close` does.
  Future<void> close();
}

/// What a terminal says it does, in place of what twk would guess from its
/// name: a terminal that is none of those twk knows (an editor's terminal,
/// an emulator in a test) declares it rather than pretending to be one
/// with a `TERM_PROGRAM` that says more than meant.
///
/// Each capability is declared or not: null leaves it to the guess by the
/// environment (`notificationProtocolFor`, `progressReportsFor`,
/// `pointerShapesFor`, the known terminals of REP, `graphicsProtocolFor`),
/// as for a real terminal, which declares nothing. Declared, it is what
/// `TerminalInfo` says, whatever the environment names. A `twk shell`'s
/// terminal declares in its welcome (`declares`, see `socket.dart`).
final class TerminalDeclaration {
  /// A declaration of what is given, the rest left to the guess.
  const TerminalDeclaration({
    this.notifications,
    this.progressReports,
    this.pointerShapes,
    this.repeatChar,
    this.graphics,
  });

  /// What the JSON object [json] declares, as a welcome carries it
  /// ([toJson]): each field of the right type and value taken, any other
  /// left undeclared, and nothing for what is no JSON object.
  factory TerminalDeclaration.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return const TerminalDeclaration();
    }
    T? named<T extends Enum>(List<T> values, Object? name) {
      for (final v in values) {
        if (v.name == name) {
          return v;
        }
      }
      return null;
    }

    bool? flag(Object? value) => value is bool ? value : null;
    return TerminalDeclaration(
      notifications: named(NotificationProtocol.values, json['notifications']),
      progressReports: flag(json['progressReports']),
      pointerShapes: flag(json['pointerShapes']),
      repeatChar: flag(json['repeatChar']),
      graphics: named(GraphicsProtocol.values, json['graphics']),
    );
  }

  /// How desktop notifications are shown (`TerminalInfo.notifications`).
  final NotificationProtocol? notifications;

  /// Whether a program's progress is shown, OSC 9;4
  /// (`TerminalInfo.progressReports`).
  final bool? progressReports;

  /// Whether the mouse pointer takes the shapes OSC 22 sets
  /// (`TerminalInfo.pointerShapes`).
  final bool? pointerShapes;

  /// Whether REP, `CSI n b`, repeats the character before it
  /// (`TerminalCaps.repeatChar`).
  final bool? repeatChar;

  /// How images are shown (`TerminalCaps.graphics`), under what the app
  /// asks for itself (`TerminalOptions.graphics`).
  final GraphicsProtocol? graphics;

  /// Whether it declares nothing.
  bool get isEmpty => toJson().isEmpty;

  /// What it declares as JSON, in this order: `notifications`,
  /// `progressReports`, `pointerShapes`, `repeatChar`, `graphics`, each
  /// only where declared, the protocols by name.
  Map<String, Object> toJson() => {
    'notifications': ?notifications?.name,
    'progressReports': ?progressReports,
    'pointerShapes': ?pointerShapes,
    'repeatChar': ?repeatChar,
    'graphics': ?graphics?.name,
  };

  @override
  bool operator ==(Object other) =>
      other is TerminalDeclaration &&
      other.notifications == notifications &&
      other.progressReports == progressReports &&
      other.pointerShapes == pointerShapes &&
      other.repeatChar == repeatChar &&
      other.graphics == graphics;

  @override
  int get hashCode => Object.hash(
    notifications,
    progressReports,
    pointerShapes,
    repeatChar,
    graphics,
  );

  @override
  String toString() => 'TerminalDeclaration(${toJson()})';
}

/// A [TerminalLink] whose terminal declares what it does
/// ([TerminalDeclaration]), which `Terminal` takes over its guess: the link
/// to a `twk shell` (`SocketLink`, the welcome's `declares`), and the
/// terminal a shell serves (`TerminalShell` passes it on in its welcome).
abstract interface class DeclaringLink implements TerminalLink {
  /// What the terminal declares; empty where it declares nothing.
  TerminalDeclaration get declaration;
}
