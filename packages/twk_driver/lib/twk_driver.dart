/// Drives a twk app as a real process in a pseudo-terminal: `Session`
/// starts it, presses keys, types, pastes, resizes, taps a widget a finder
/// names, and returns once the app has drawn the frame that took each
/// input in. The screen is read through terminal emulators, the widget
/// tree through the app's VM service.
///
/// What a session is made of are four ports (`TerminalPort`, `ScreenPort`,
/// `AppServicePort`, `ProcessPort`), each with an adapter (`PtyProcessPort`,
/// `EmulatorScreen`, `VmAppClient`) that `Session` uses by default.
/// `compiledProgram` compiles a program to a kernel once for the runs
/// after.
library;

export 'src/app_client.dart'
    show AppClient, AppError, Json, VmAppClient, VmQueries, watchExtensions;
export 'src/byte_log.dart' show ByteLog;
export 'src/clock_control.dart' show ClockControl, ClockStatus, TimerInfo;
export 'src/emulator_screen.dart' show EmulatorScreen;
export 'src/errors.dart' show AppEnded, DriverError, ExitResult;
export 'src/found.dart' show Cells, Found, foundOf;
export 'src/ports.dart'
    show
        AppEvent,
        AppServicePort,
        Launched,
        ProcessPort,
        ProcessSpec,
        ScreenPort,
        ScreenView,
        TerminalPort;
export 'src/program.dart' show compiledProgram;
export 'src/pty_terminal.dart' show PtyCommandPort, PtyProcessPort;
export 'src/session.dart' show CloseReport, Seen, Session, SessionPorts, Step;
