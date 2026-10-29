/// The terminal without the render tree and the app: for a logger, a
/// prompt or a command-line tool that writes lines and reads keys rather
/// than drawing frames. [Terminal] opens the process's terminal (or one
/// over a [TerminalLink], or plain output where it takes no sequences) and
/// says what it is ([TerminalInfo], [TerminalCaps]); [colorModeFor],
/// [plainAsked] and [runsInCi] say what the environment asks for;
/// [StyleTable] interns styles of [Color]s and [Attr]s, which a
/// [LineEncoder] writes as lines of text with their SGR sequences;
/// [InputParser] decodes the bytes read into [InputEvent]s ([KeyEvent],
/// [MouseEvent], [PasteEvent], …); [stringWidth], [TextSegmenter] and
/// [fitText] measure and cut text in cells; the terminal's own sequences
/// (a title, progress, a notification, the clipboard) are strings to
/// write; and [LogSink] keeps what [log] records.
///
/// Import it in place of `package:twk_core/twk_core.dart` where nothing
/// is painted on a screen of cells: it compiles in about two thirds of the
/// time, the render tree and the frame loop left out. Every name it
/// exports is the same declaration as `twk_core.dart`'s, so a program may
/// import both.
///
/// A question on the line the cursor is on, answered with one key, in a
/// program whose one import is `package:twk_core/terminal.dart`:
///
/// ```dart
/// Future<void> main() async {
///   final terminal = await Terminal.open(
///     const TerminalOptions(alternateScreen: false, mouse: false),
///   );
///   final styles = StyleTable(colorMode: terminal.info.colorMode);
///   final ask = styles.style(fg: Color.yellow, attrs: Attr.bold);
///   final line = LineEncoder(styles, ansi: !terminal.info.plain)
///     ..text(ask, 'Continue?')
///     ..text(0, ' [y/n] ')
///     ..end();
///   terminal.write(line.out.view);
///   final key = await terminal.events.firstWhere((e) => e is KeyEvent);
///   await terminal.close();
///   print(key == const KeyEvent(KeyCode.char, char: 'y') ? 'yes' : 'no');
/// }
/// ```
///
/// See also:
///
///  * `package:twk_core/twk_core.dart`, the whole core: the screen of
///    cells, the presenter, the render tree and the app that runs it.
///
/// @docImport 'src/input/events.dart';
/// @docImport 'src/input/parser.dart';
/// @docImport 'src/line_encoder.dart';
/// @docImport 'src/log.dart';
/// @docImport 'src/presenter.dart';
/// @docImport 'src/style.dart';
/// @docImport 'src/terminal/link.dart';
/// @docImport 'src/terminal/plain.dart';
/// @docImport 'src/terminal/terminal.dart';
/// @docImport 'src/unicode/unicode.dart';
library;

export 'src/byte_sink.dart' show ByteSink;
export 'src/graphics.dart' show GraphicsProtocol;
export 'src/input/events.dart';
export 'src/input/parser.dart' show InputParser;
export 'src/line_encoder.dart' show LineEncoder;
export 'src/log.dart' show LogLevel, LogRecord, LogSink, log;
export 'src/platform/platform.dart' show LocalAddress;
export 'src/presenter.dart' show TerminalCaps;
export 'src/style.dart' show Attr, Color, ColorMode, Pen, StyleTable;
export 'src/terminal/link.dart' show TerminalException, TerminalLink;
export 'src/terminal/plain.dart' show plainAsked, runsInCi;
export 'src/terminal/sequences.dart'
    show
        BidiReordering,
        MouseTracking,
        Multiplexer,
        NotificationProtocol,
        PointerShape,
        ProgressState,
        clipboardSequence,
        mouseTrackingSequence,
        notifySequence,
        passthroughSequence,
        pointerShapeSequence,
        popTitleSequence,
        progressSequence,
        pushTitleSequence,
        titleSequence;
export 'src/terminal/terminal.dart'
    show
        MouseTrackingBackend,
        SuspendableBackend,
        Terminal,
        TerminalBackend,
        TerminalInfo,
        TerminalOptions,
        TerminalStateBackend,
        WindowBackend,
        colorModeFor,
        styledUnderlinesFor;
export 'src/unicode/unicode.dart'
    show
        ClusterScan,
        TextMode,
        TextSegmenter,
        fitText,
        graphemeBoundaries,
        stringWidth,
        unicodeVersion;
