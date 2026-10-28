/// An embedded terminal: a permissive VT emulator whose screen the core's
/// Canvas draws, the pseudo-terminal a program runs in, the widget that
/// shows it, and the terminal on stdin in raw mode, for a program that
/// passes the keys typed on.
library;

export 'src/emulator/buffer.dart' show TerminalLine;
export 'src/emulator/emulator.dart' show TerminalEmulator;
export 'src/emulator/events.dart';
export 'src/emulator/input.dart'
    show keySequence, kittyKeySequence, mouseSequence, pasteSequence;
export 'src/emulator/modes.dart';
export 'src/pty/pty.dart'
    if (dart.library.js_interop) 'src/pty/pty_web.dart'
    show Pty;
export 'src/pty/raw_tty.dart'
    if (dart.library.js_interop) 'src/pty/raw_tty_web.dart'
    show RawTty;
export 'src/view/terminal_view.dart';
