/// Widgets for terminal UIs on top of the twk_core rendering core.
///
/// Each topic is a library of its own, `src/<topic>/<topic>.dart`; this
/// library exports all of them, and the declarations of twk_core an app
/// names, so that it imports nothing else: those a public signature here
/// takes, returns or extends, those a widget with a render object of its
/// own lays out, paints, hit tests and measures text with, and a terminal
/// in memory for tests with what its constructor takes. The rest of the
/// core stays behind `package:twk_core`: the render objects the widgets
/// here create and the parent data they put on them (the widgets are
/// final: no app names those), the frame loop (`TwkApp`, `PipelineOwner`)
/// and the terminal's machinery (presenter, surface, screen, parser,
/// sequences).
///
/// No name is both twk's and the core's: a key of the keyboard is a
/// `KeyCode`, a `Key` tells widgets apart. `log` is also a function of
/// dart:math and dart:developer, which an app that calls it imports with a
/// prefix.
library;

// styles, geometry, layout and text
export 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Attr,
        Axis,
        BorderType,
        BoxConstraints,
        Color,
        CrossAxisAlignment,
        EdgeInsets,
        FlexFit,
        GridTrack,
        GridTrackKind,
        MainAxisAlignment,
        MainAxisSize,
        Pen,
        StackFit,
        TextAlign,
        TextOrder,
        TextOverflow,
        TextWrap;
// what an InputListener gets
export 'package:twk_core/twk_core.dart'
    show
        Brightness,
        ColorReport,
        ColorSchemeReport,
        CursorReport,
        DeviceAttributes,
        FocusEvent,
        InputEvent,
        KeyCode,
        KeyEvent,
        KeyKind,
        KeyboardFlagsReport,
        Mod,
        ModeReport,
        MouseEvent,
        MouseKind,
        PasteEvent,
        ResizeEvent,
        UnknownSequence;
// what an app runs on and logs to
export 'package:twk_core/twk_core.dart'
    show
        BidiReordering,
        LogLevel,
        LogRecord,
        LogSink,
        TerminalBackend,
        Viewport,
        log;
// render objects of an app's own, and how they describe themselves
export 'package:twk_core/twk_core.dart'
    show
        Canvas,
        ClusterScan,
        ContainerParentDataMixin,
        ContainerRenderObjectMixin,
        CursorShape,
        DiagnosticPropertiesBuilder,
        DiagnosticsFlag,
        DiagnosticsNode,
        DiagnosticsProperty,
        GlyphRun,
        HitTestBehavior,
        HitTestResult,
        PaintContext,
        ParentData,
        RenderObject,
        RenderObjectWithChildMixin,
        StyleTable,
        TextMode,
        TextSegmenter,
        describeAlignment,
        describeColor,
        describeConstraints,
        describeInsets,
        describePen,
        describeText,
        describeValue,
        stringWidth;
// tests: a terminal in memory, and what it is made with
export 'package:twk_core/twk_core.dart'
    show
        ColorMode,
        GraphicsProtocol,
        HeadlessTerminal,
        Multiplexer,
        NotificationProtocol,
        PointerNames,
        TerminalCaps,
        TerminalOptions,
        renderToString;

export 'src/animation/animation.dart';
export 'src/ansi/ansi.dart';
export 'src/binding/binding.dart';
export 'src/controls/controls.dart';
export 'src/data/data.dart';
export 'src/debug/debug.dart';
export 'src/editing/editing.dart';
export 'src/focus/focus.dart';
export 'src/foundation/foundation.dart';
export 'src/framework/framework.dart';
export 'src/gestures/gestures.dart';
export 'src/layout/layout.dart';
export 'src/navigation/navigation.dart';
export 'src/overlay/overlay.dart';
export 'src/scroll/scroll.dart';
export 'src/semantics/semantics.dart';
export 'src/style/style.dart';
export 'src/text/text.dart';
