/// What a program asks of the terminal beyond its screen: handed to the
/// host, which decides what to do (nothing is executed here).
library;

import 'package:twk_core/twk_core.dart' show CursorShape;

import 'modes.dart';

/// Something the program asked for, in the order it was asked.
sealed class TerminalEvent {
  const TerminalEvent();
}

/// OSC 0 or 2 set the window title (OSC 0 the icon name too).
final class TitleChanged extends TerminalEvent {
  /// The window title set to [title].
  const TitleChanged(this.title);

  /// The title the program set.
  final String title;

  @override
  String toString() => 'TitleChanged($title)';
}

/// OSC 0 or 1 set the icon name (a tab's title in some terminals).
final class IconNameChanged extends TerminalEvent {
  /// The icon name set to [name].
  const IconNameChanged(this.name);

  /// The icon name the program set.
  final String name;

  @override
  String toString() => 'IconNameChanged($name)';
}

/// BEL outside a string.
final class BellRang extends TerminalEvent {
  /// The bell rang.
  const BellRang();

  @override
  String toString() => 'BellRang()';
}

/// OSC 52: put [text] on the clipboard. [selection] is what the program
/// named: `c` the clipboard, `p` the primary selection, `s`, `0`..`7`
/// others; several letters for several of them.
final class ClipboardWrite extends TerminalEvent {
  /// [text] to put on the [selection]s.
  const ClipboardWrite(this.selection, this.text);

  /// The selections to put [text] on, as the program named them; `c`
  /// where it named none.
  final String selection;

  /// The text, decoded from the program's base64.
  final String text;

  @override
  String toString() => 'ClipboardWrite($selection, ${text.length} chars)';
}

/// OSC 52 with `?`: the program wants to read the clipboard; the host
/// answers with `TerminalEmulator.answerClipboard`, or not at all.
final class ClipboardRead extends TerminalEvent {
  /// A read of [selection].
  const ClipboardRead(this.selection);

  /// The selection to read, as the program named it (see
  /// [ClipboardWrite.selection]).
  final String selection;

  @override
  String toString() => 'ClipboardRead($selection)';
}

/// A mode changed: those that change what the host sends ([TerminalMode]
/// cursorKeys, keypad, the mouse modes, focus, bracketedPaste, newLine),
/// what it shows (alternateScreen, cursorVisible, cursorBlink,
/// reverseVideo) and when (synchronizedOutput) among them.
final class ModeChanged extends TerminalEvent {
  /// [mode] set, where [enabled], or reset.
  const ModeChanged(this.mode, {required this.enabled});

  /// The mode that changed.
  final TerminalMode mode;

  /// Whether [mode] is set now that it changed.
  final bool enabled;

  @override
  String toString() => 'ModeChanged(${mode.name}, $enabled)';
}

/// DECSCUSR set the cursor's shape.
final class CursorShapeChanged extends TerminalEvent {
  /// The cursor's shape set to [shape].
  const CursorShapeChanged(this.shape);

  /// The shape the program set.
  final CursorShape shape;

  @override
  String toString() => 'CursorShapeChanged(${shape.name})';
}

/// OSC 7: the program's working directory, a `file://host/path` URI.
final class WorkingDirectoryChanged extends TerminalEvent {
  /// The working directory told as [uri].
  const WorkingDirectoryChanged(this.uri);

  /// The working directory, as a `file:` URI.
  final Uri uri;

  @override
  String toString() => 'WorkingDirectoryChanged($uri)';
}

/// A desktop notification (OSC 9 with a message, OSC 777 `notify`).
final class NotificationRequested extends TerminalEvent {
  /// A notification of [title] and [body].
  const NotificationRequested(this.title, this.body);

  /// The notification's title; empty for OSC 9, which has only a body,
  /// and an OSC 777 without one.
  final String title;

  /// The notification's text.
  final String body;

  @override
  String toString() => 'NotificationRequested($title, $body)';
}

/// OSC 9;4: progress for a tab or taskbar. [state] 0 none, 1 [percent]
/// done, 2 error, 3 indeterminate, 4 paused.
final class ProgressChanged extends TerminalEvent {
  /// Progress in [state], [percent] done.
  const ProgressChanged(this.state, this.percent);

  /// What the progress is, as the program sent it: 0 none, 1 under way,
  /// 2 error, 3 indeterminate, 4 paused.
  final int state;

  /// How much is done, from 0 to 100.
  final int percent;

  @override
  String toString() => 'ProgressChanged($state, $percent)';
}

/// Where a shell's prompt, command and output start (OSC 133).
enum PromptMark {
  /// `A`: the prompt starts.
  promptStart,

  /// `B`: the command line starts (the prompt ended).
  commandStart,

  /// `C`: the command runs, its output starts.
  outputStart,

  /// `D`: the command finished (with an exit status, maybe).
  commandEnd,
}

/// OSC 133 marked the row the cursor is on.
final class PromptMarked extends TerminalEvent {
  /// [mark] on [row], with the [exitCode] a command ended with.
  const PromptMarked(this.mark, this.row, {this.exitCode});

  /// Which part of the prompt and command starts at the mark.
  final PromptMark mark;

  /// The cursor's row on the screen.
  final int row;

  /// With [PromptMark.commandEnd], the status the program gave.
  final int? exitCode;

  @override
  String toString() => 'PromptMarked(${mark.name}, $row, $exitCode)';
}

/// A palette entry or a default color was set or reset (OSC 4, 10, 11, 12,
/// 104, 110, 111, 112): cells keep palette indices, a host that draws them
/// in RGB reads the new colors.
final class ColorsChanged extends TerminalEvent {
  /// Some colors changed.
  const ColorsChanged();

  @override
  String toString() => 'ColorsChanged()';
}

/// XTWINOPS 8: the program asks for a screen of [width] x [height] cells.
final class ResizeRequested extends TerminalEvent {
  /// A request for [width] x [height] cells.
  const ResizeRequested(this.width, this.height);

  /// The columns the program asked for.
  final int width;

  /// The rows the program asked for.
  final int height;

  @override
  String toString() => 'ResizeRequested($width, $height)';
}

/// OSC 22: the mouse pointer's shape (a CSS cursor name, such as `text`
/// or `pointer`).
final class PointerShapeChanged extends TerminalEvent {
  /// The pointer's shape set to [shape].
  const PointerShapeChanged(this.shape);

  /// The CSS cursor name, as the program sent it.
  final String shape;

  @override
  String toString() => 'PointerShapeChanged($shape)';
}
