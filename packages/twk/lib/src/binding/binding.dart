/// The binding between the widget tree and the core's `TwkApp`: running an
/// app, scheduling frames and delivering input, what a widget whose build
/// threw shows (and the source it was thrown in, [SourceExcerpt]), output
/// written to the terminal's history, and the service extensions tools
/// inspect and hot reload an app by.
library;

import 'source_excerpt.dart';

export 'app_binding.dart';
export 'error_widget.dart';
export 'source_excerpt.dart' show SourceExcerpt;
export 'static.dart';
export 'terminal_status.dart'
    show ProgressState, TerminalProgress, TerminalStatus, WindowTitle;
