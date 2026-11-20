/// The four ports of the driver core: [TerminalPort], [ScreenPort],
/// [AppServicePort] and [ProcessPort], and what they pass: [AppEvent],
/// [ProcessSpec], [Launched], [ScreenView].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show KeyEvent, MouseEvent;

import 'app_client.dart' show Json;

/// A pseudo-terminal's master as the driver sees it: the bytes the app
/// writes, in the pieces the terminal gave them, the bytes the driver
/// writes, and its size.
abstract interface class TerminalPort {
  /// What the app writes, as the terminal gave it, its line discipline
  /// done (a CR before each LF while [nlToCrNl]). Single-subscription; it
  /// ends when the terminal does.
  Stream<Uint8List> get output;

  /// Whether the terminal writes the app's LF as CR LF now; null once it
  /// cannot say.
  bool? get nlToCrNl;

  /// Hands [bytes] to the app as its input.
  ///
  /// A recorder wraps a terminal in one of its own, in the [Launched] it
  /// gives the session: its [output] passes each chunk on, noting the time
  /// its clock gave it, and its [write] notes what the driver wrote.
  /// Nothing of a recorder is in the driver.
  void write(List<int> bytes);

  /// Sets the terminal's size and tells the app (SIGWINCH).
  void resize(int width, int height);

  /// The terminal's attributes `struct termios` as the program left them
  /// at its end; null before, or where they could not be read.
  Uint8List? get modesAtEnd;
}

/// What the screens of a [ScreenPort] show, as text and cursor.
abstract interface class ScreenView {
  /// The columns and rows.
  int get width;

  /// The rows.
  int get height;

  /// The text of row [y], without the trailing blanks.
  String line(int y);

  /// Whether the cell at ([x], [y]) is the trailing half of a two-column
  /// glyph.
  bool isContinuation(int x, int y);

  /// The column of the cursor.
  int get cursorX;

  /// The row of the cursor.
  int get cursorY;

  /// Whether the cursor shows.
  bool get cursorVisible;

  /// Whether the app is on the alternate screen.
  bool get alternateScreen;

  /// Whether the app is inside a synchronized update (DEC 2026): the screen
  /// is drawn in part, and a wait on output does not look at it.
  bool get updating;

  /// The screen as text, one line to a row, the trailing blank rows kept
  /// as empty lines.
  String get text;
}

/// The two terminal emulators of a session, fed from one byte log: the
/// answering one takes every byte as it arrives, answers the app's
/// queries at once and keeps the modes by which keys, the mouse and pastes
/// are encoded; the frame one (`frame`) answers nothing and takes the bytes
/// up to
/// the boundary of a posted frame only, which is the screen an action
/// returns.
abstract interface class ScreenPort {
  /// Called with each answer the answering emulator gives the app's
  /// queries, to be written to the terminal at once.
  void answerTo(void Function(Uint8List bytes)? sink);

  /// The answering emulator takes [bytes], as a terminal does.
  void feedAnswering(List<int> bytes);

  /// The frame emulator takes [bytes].
  void feedFrame(List<int> bytes);

  /// What the frame emulator shows.
  ScreenView get frame;

  /// The bytes the answering emulator sends for [key] in the modes the app
  /// set; empty where it sends nothing.
  Uint8List encodeKey(KeyEvent key);

  /// The bytes of [text] typed.
  Uint8List encodeText(String text);

  /// The bytes of [text] pasted, bracketed when the app asked.
  Uint8List encodePaste(String text);

  /// The bytes of [event] in the mouse modes the app set; empty where it
  /// tracks no mouse.
  Uint8List encodeMouse(MouseEvent event);

  /// Whether the app asked to hear of the mouse.
  bool get mouseTracked;

  /// Sets the answering emulator's size: the terminal's, as the app has it
  /// from the moment the terminal was resized.
  void resizeAnswering(int width, int height);

  /// Sets the frame emulator's size: at the frame that was laid out at it.
  void resizeFrame(int width, int height);
}

/// An event the app posted on its VM service: `twk.frame`, `twk.input`,
/// `twk.select`, and the like.
final class AppEvent {
  /// The event [kind] with its [data] (the app's JSON).
  const AppEvent(this.kind, this.data);

  /// The extension event's kind, `twk.frame` for one.
  final String kind;

  /// What the app posted.
  final Json data;
}

/// The app's `ext.twk.*` service extensions and the events it posts.
abstract interface class AppServicePort {
  /// What `ext.twk.<method>` answers with [params]: a JSON object. Throws
  /// when it answers with an error and when the app has gone.
  Future<Json> call(String method, [Map<String, String> params]);

  /// The extension events of the app, `twk.frame` and `twk.input` among
  /// them, each of the version the client reads.
  Stream<AppEvent> get events;

  /// Completes when the service has gone.
  Future<void> get done;

  /// Lets the app go.
  Future<void> close();
}

/// How to start a program for a driver.
final class ProcessSpec {
  /// A program: a Dart file or a kernel ([program]), its [arguments], the
  /// [environment] over this process's, the terminal's [width] by
  /// [height].
  const ProcessSpec(
    this.program, {
    this.arguments = const [],
    this.workingDirectory,
    this.environment = const {},
    this.width = 80,
    this.height = 24,
  });

  /// The Dart file or kernel to run.
  final String program;

  /// The program's arguments.
  final List<String> arguments;

  /// Where it runs; null for here.
  final String? workingDirectory;

  /// Variables for the program over what this process has.
  final Map<String, String> environment;

  /// The terminal's columns.
  final int width;

  /// The terminal's rows.
  final int height;
}

/// A program a [ProcessPort] started: its terminal, its end and where its
/// VM service is.
abstract interface class Launched {
  /// The program's pseudo-terminal.
  TerminalPort get terminal;

  /// The program's exit code once it ended; null where it is not known.
  Future<int?> get exitCode;

  /// The address of its VM service, once it has written it; an error when
  /// the program ended first.
  Future<Uri> get serviceUri;

  /// Ends the program: its terminal hung up, the program killed if it does
  /// not go.
  Future<void> kill();
}

/// Starts programs in a pseudo-terminal with a VM service.
abstract interface class ProcessPort {
  /// Starts [spec].
  Future<Launched> spawn(ProcessSpec spec);
}
