/// A terminal UI core with no dependencies but `dart:*`: [TwkApp], the
/// frame loop that runs a render tree ([RenderObject]) on a [Terminal];
/// [Screen], a [Surface] of cells painted through a [Canvas] with
/// [StyleTable] pens, which a [Presenter] writes as the fewest bytes for
/// what [TerminalCaps] says the terminal has; input decoded into
/// [InputEvent]s; Unicode segmentation and widths ([TextSegmenter],
/// [stringWidth]) and bidirectional text ([BidiText]); and, for tests and
/// one-off output, [HeadlessTerminal], [renderToString] and
/// [LineEncoder], lines of text in the SGR sequences of their styles.
///
/// @docImport 'src/app.dart';
/// @docImport 'src/canvas.dart';
/// @docImport 'src/headless.dart';
/// @docImport 'src/input/events.dart';
/// @docImport 'src/line_encoder.dart';
/// @docImport 'src/presenter.dart';
/// @docImport 'src/render/render.dart';
/// @docImport 'src/screen.dart';
/// @docImport 'src/style.dart';
/// @docImport 'src/surface.dart';
/// @docImport 'src/terminal/terminal.dart';
/// @docImport 'src/unicode/bidi.dart';
/// @docImport 'src/unicode/unicode.dart';
library;

export 'src/app.dart' show FrameStats, TwkApp;
export 'src/byte_sink.dart' show ByteSink;
export 'src/canvas.dart' show Canvas, GlyphRun;
export 'src/graphics.dart' show GraphicsProtocol, ImagePlacement, TerminalImage;
export 'src/headless.dart' show HeadlessTerminal, renderToString;
export 'src/input/events.dart';
export 'src/input/parser.dart' show InputParser;
export 'src/line_encoder.dart' show LineEncoder;
export 'src/log.dart' show LogLevel, LogRecord, LogSink, log;
export 'src/platform/platform.dart'
    show LocalAddress, ShellEvent, TerminalShell;
export 'src/presenter.dart'
    show CursorShape, PresentStats, Presenter, TerminalCaps, Viewport;
export 'src/render/render.dart';
export 'src/screen.dart' show Screen;
export 'src/style.dart' show Attr, Color, ColorMode, Pen, StyleTable;
export 'src/surface.dart'
    show
        GlyphTable,
        Surface,
        kBlank,
        kCont,
        kGlyphMask,
        kSkip,
        kUncertain,
        kWide;
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
        brightnessFor,
        colorModeFor;
export 'src/terminal/trace.dart'
    show Trace, TraceDirection, TraceRecord, TraceWriter;
export 'src/unicode/bidi.dart'
    show
        BidiClass,
        BidiParagraph,
        BidiRun,
        BidiText,
        TextDirection,
        bidiClassOf,
        bidiMirror;
export 'src/unicode/unicode.dart'
    show
        ClusterScan,
        TextMode,
        TextSegmenter,
        fitText,
        graphemeBoundaries,
        stringWidth,
        unicodeVersion;
