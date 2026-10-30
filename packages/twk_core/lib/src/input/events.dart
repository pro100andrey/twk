/// What a terminal sends a program, decoded by [InputParser]: the
/// [InputEvent]s, among them [KeyEvent] with its [KeyCode] and [Mod]
/// bits, [MouseEvent], [PasteEvent], [FocusEvent], [ResizeEvent], and the
/// replies to queries; [KittyKeyboardFlags], the keyboard protocol's
/// enhancements.
library;

import 'parser.dart' show InputParser;

/// The bits of [KeyEvent.modifiers] and [MouseEvent.modifiers], one per
/// modifier key held: the values xterm and the kitty keyboard protocol
/// encode as their modifier parameter less one.
///
/// A key typed with the kitty keyboard protocol may carry bits beyond
/// these that the terminal reports too (16 Hyper, 32 Meta); Caps Lock and
/// Num Lock are left out. A mouse report carries [shift], [alt] and
/// [ctrl] only.
///
/// ```dart
/// bool isSave(KeyEvent key) =>
///     key.code == KeyCode.char &&
///     key.char == 's' &&
///     key.modifiers == Mod.ctrl;
/// ```
abstract final class Mod {
  /// Shift.
  static const shift = 1;

  /// Alt (Option on macOS): terminals send it as an ESC before the key's
  /// own bytes.
  static const alt = 2;

  /// Ctrl: also a control character typed (`^A` is Ctrl+A).
  static const ctrl = 4;

  /// Super (Windows, Command): reported with the kitty keyboard protocol
  /// only.
  static const superKey = 8;
}

/// The key a [KeyEvent] is for: [char] for a key that types a character,
/// the rest for keys without one.
///
/// Ctrl with a letter is that letter with [Mod.ctrl] (`^A` is `a`), Ctrl
/// with Space a space; Shift+Tab is [tab] with [Mod.shift]. A keypad key
/// is the key or the character it stands for.
enum KeyCode {
  /// A key that types a character: [KeyEvent.char] holds it.
  char,

  /// Enter (Return): CR or LF.
  enter,

  /// Tab.
  tab,

  /// Backspace; with [Mod.ctrl] where the terminal sends the other of
  /// DEL and `^H` than for Backspace alone.
  backspace,

  /// Escape: a lone ESC once nothing follows it in a short while, or its
  /// own sequence with the kitty keyboard protocol.
  escape,

  /// The up arrow.
  up,

  /// The down arrow.
  down,

  /// The left arrow.
  left,

  /// The right arrow.
  right,

  /// Home.
  home,

  /// End.
  end,

  /// Page Up.
  pageUp,

  /// Page Down.
  pageDown,

  /// Insert.
  insert,

  /// Delete (Del), not Backspace.
  delete,

  /// The function key F1.
  f1,

  /// The function key F2.
  f2,

  /// The function key F3: also what a cursor position report looks like,
  /// which [InputParser.expectCursorReport] tells apart.
  f3,

  /// The function key F4.
  f4,

  /// The function key F5.
  f5,

  /// The function key F6.
  f6,

  /// The function key F7.
  f7,

  /// The function key F8.
  f8,

  /// The function key F9.
  f9,

  /// The function key F10.
  f10,

  /// The function key F11.
  f11,

  /// The function key F12.
  f12,
}

/// One thing a terminal sent: what the user did ([KeyEvent],
/// [MouseEvent], [PasteEvent], [FocusEvent]), the terminal's new size
/// ([ResizeEvent]), a reply to a query, or a sequence nothing here maps
/// ([UnknownSequence]).
///
/// The class is sealed, so a `switch` over an event names every kind or
/// has a `default`. A program reads them from `Terminal.events`, or is
/// handed each one by `TwkApp.run`; the replies the terminal answers its
/// own queries with go to it, and the rest to the program:
///
/// ```dart
/// final terminal = await Terminal.open();
/// await for (final event in terminal.events) {
///   switch (event) {
///     case KeyEvent(code: KeyCode.char, char: 'q'):
///       await terminal.close();
///     case MouseEvent(kind: MouseKind.down, :final x, :final y):
///       terminal.setTitle('pressed at $x, $y');
///     case ResizeEvent(:final width, :final height):
///       terminal.setTitle('$width x $height');
///     default:
///   }
/// }
/// ```
sealed class InputEvent {
  /// An event; for the subclasses.
  const InputEvent();
}

/// What happened to the key of a [KeyEvent].
///
/// Terminals report presses only, a key held down as more presses, unless
/// the kitty keyboard protocol's [KittyKeyboardFlags.eventTypes] is on.
enum KeyKind {
  /// The key went down.
  press,

  /// The key is held down and repeats.
  repeat,

  /// The key came up.
  release,
}

/// A key typed: which one ([code], with [char] the character it types),
/// the modifiers held ([modifiers]) and, with the kitty keyboard
/// protocol's [KittyKeyboardFlags.eventTypes], whether it went down,
/// repeats or came up ([kind]).
///
/// Text typed comes as one event per grapheme cluster; a key that types
/// text with Shift (no other modifier) is the text it types, `A`, without
/// [Mod.shift]. Two events are equal when every field is.
///
/// ```dart
/// const ctrlC = KeyEvent(KeyCode.char, char: 'c', modifiers: Mod.ctrl);
///
/// void onKey(KeyEvent key) {
///   if (key == ctrlC) {
///     // Ctrl+C
///   } else if (key.code == KeyCode.up && key.shift) {
///     // Shift+Up
///   }
/// }
/// ```
///
/// See also:
///
///  * [PasteEvent], for text pasted, which comes as one event and not as
///    keys.
final class KeyEvent extends InputEvent {
  /// A key [code]: [char] for [KeyCode.char] ('' for the other keys),
  /// [modifiers] the [Mod] bits held (none by default), [kind] a press
  /// by default.
  const KeyEvent(
    this.code, {
    this.char = '',
    this.modifiers = 0,
    this.kind = KeyKind.press,
  });

  /// The key.
  final KeyCode code;

  /// The text for [KeyCode.char] (one grapheme or code point); '' for the
  /// other keys.
  final String char;

  /// The [Mod] bits of the modifier keys held, 0 for none.
  final int modifiers;

  /// Whether the key went down, repeats or came up; [KeyKind.press] where
  /// the terminal doesn't tell.
  final KeyKind kind;

  /// Whether Ctrl is held ([Mod.ctrl]).
  bool get ctrl => modifiers & Mod.ctrl != 0;

  /// Whether Alt is held ([Mod.alt]).
  bool get alt => modifiers & Mod.alt != 0;

  /// Whether Shift is held ([Mod.shift]).
  bool get shift => modifiers & Mod.shift != 0;

  @override
  bool operator ==(Object other) =>
      other is KeyEvent &&
      other.code == code &&
      other.char == char &&
      other.modifiers == modifiers &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(code, char, modifiers, kind);

  @override
  String toString() {
    final name = code == KeyCode.char ? '"$char"' : code.name;
    final mod = modifiers != 0 ? ' mod=$modifiers' : '';
    final k = kind != KeyKind.press ? ' ${kind.name}' : '';
    return 'Key($name$mod$k)';
  }
}

/// What the mouse did in a [MouseEvent].
enum MouseKind {
  /// A button was pressed.
  down,

  /// A button was released.
  up,

  /// The pointer moved with no button held: reported only while the
  /// terminal tracks all motion (`MouseTracking.motion`).
  move,

  /// The pointer moved with a button held.
  drag,

  /// The wheel turned up, away from the user.
  wheelUp,

  /// The wheel turned down, towards the user.
  wheelDown,

  /// The wheel tilted left.
  wheelLeft,

  /// The wheel tilted right.
  wheelRight,
}

/// What the mouse did ([kind]), in which cell ([x], [y]), with which
/// [button] and [modifiers].
///
/// Terminals report the mouse only while it is tracked: `Terminal` tracks
/// presses, releases, drags and the wheel by default on the alternate
/// screen (`TerminalOptions.mouse`), all motion when asked
/// (`TerminalOptions.mouseMotion`). Of motions with no button held that
/// arrive in one read, only the last is delivered. Two events are equal
/// when every field is.
///
/// ```dart
/// void onMouse(MouseEvent e) {
///   if (e.kind == MouseKind.down && e.button == 0) {
///     // a left click in the cell at e.x, e.y
///   } else if (e.kind == MouseKind.wheelDown) {
///     // scroll down
///   }
/// }
/// ```
final class MouseEvent extends InputEvent {
  /// An event of [kind] in the cell at [x], [y], with [button] (0, the
  /// left one, by default) and the [Mod] bits [modifiers] (none by
  /// default).
  const MouseEvent(
    this.kind,
    this.x,
    this.y, {
    this.button = 0,
    this.modifiers = 0,
  });

  /// What the mouse did.
  final MouseKind kind;

  /// The cell's column, 0 the leftmost.
  final int x;

  /// The cell's row, 0 the top one.
  final int y;

  /// The button pressed, released or held for [MouseKind.down],
  /// [MouseKind.up] and [MouseKind.drag]: 0 left, 1 middle, 2 right, 8
  /// back, 9 forward, 10 and 11 further side buttons. 0 for a move and the
  /// wheel.
  final int button;

  /// The [Mod] bits held: [Mod.shift], [Mod.alt] and [Mod.ctrl] only, as
  /// far as the terminal reports them rather than acting on them itself
  /// (many take Shift with the mouse for their own selection).
  final int modifiers;

  @override
  bool operator ==(Object other) =>
      other is MouseEvent &&
      other.kind == kind &&
      other.x == x &&
      other.y == y &&
      other.button == button &&
      other.modifiers == modifiers;

  @override
  int get hashCode => Object.hash(kind, x, y, button, modifiers);

  @override
  String toString() => 'Mouse(${kind.name} $x,$y b$button m$modifiers)';
}

/// Text pasted into the terminal, all in one event: what bracketed paste
/// mode (`TerminalOptions.bracketedPaste`) brackets, so keys in it (an
/// Enter, a Ctrl+C) are text and act on nothing. A paste longer than
/// [InputParser.pasteLimit] comes in several, one after another, each
/// but the last with [more] set: a field inserts each as it comes, and
/// what takes a paste as one thing (a message to send) joins them.
///
/// Line breaks are LF (`\n`) whatever the terminal sent (CR LF, CR);
/// bytes that are no UTF-8 are U+FFFD. Without bracketed paste a paste
/// comes as [KeyEvent]s, as if typed. Two events are equal when their
/// text and [more] are.
final class PasteEvent extends InputEvent {
  /// A paste of [text]; with [more], a piece of one that goes on in the
  /// next.
  const PasteEvent(this.text, {this.more = false});

  /// What was pasted, with LF line breaks.
  final String text;

  /// Whether the paste goes on in the next [PasteEvent]: one longer than
  /// [InputParser.pasteLimit], in pieces.
  final bool more;

  @override
  bool operator ==(Object other) =>
      other is PasteEvent && other.text == text && other.more == more;
  @override
  int get hashCode => Object.hash(text, more);
  @override
  String toString() => 'Paste(${text.length} chars${more ? ', more' : ''})';
}

/// The terminal window gained or lost the input focus: reported where the
/// terminal has focus reports (DEC mode 1004) and
/// `TerminalOptions.focusEvents` is on, the default.
final class FocusEvent extends InputEvent {
  /// The window gained the focus where [focused], lost it otherwise.
  const FocusEvent(this.focused);

  /// Whether the window has the focus now.
  final bool focused;
  @override
  bool operator ==(Object other) =>
      other is FocusEvent && other.focused == focused;
  @override
  int get hashCode => focused.hashCode;
}

/// The terminal's new size in cells: decoded from an in-band resize report
/// (DEC mode 2048, `CSI 48 ; rows ; cols ; ... t`), or delivered by
/// `Terminal` when the size it watches changes.
///
/// Two events are equal when both sizes are.
final class ResizeEvent extends InputEvent {
  /// A size of [width] columns and [height] rows.
  const ResizeEvent(this.width, this.height);

  /// The number of columns.
  final int width;

  /// The number of rows.
  final int height;
  @override
  bool operator ==(Object other) =>
      other is ResizeEvent && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
}

/// DECRPM reply to a DECRQM query: `CSI ? mode ; value $ y`
/// (value 1 set, 2 reset, 3 permanently set, 4 permanently reset, 0 unknown).
///
/// `Terminal` asks about the modes it may use while it opens, and keeps
/// the reports to itself.
final class ModeReport extends InputEvent {
  /// The terminal's [value] for the DEC private [mode].
  const ModeReport(this.mode, this.value);

  /// The DEC private mode the report is about (2026 synchronized output,
  /// say).
  final int mode;

  /// The mode's state: 1 set, 2 reset, 3 permanently set, 4 permanently
  /// reset, 0 not known to the terminal.
  final int value;

  /// Whether the mode can be used: set, reset (can be set) or permanently
  /// set. A permanently reset mode is known but can't be turned on.
  bool get supported => value >= 1 && value <= 3;

  @override
  bool operator ==(Object other) =>
      other is ModeReport && other.mode == mode && other.value == value;
  @override
  int get hashCode => Object.hash(mode, value);
}

/// The progressive enhancements of kitty's keyboard protocol
/// (sw.kovidgoyal.net/kitty/keyboard-protocol), bits of the flags a
/// program pushes (`CSI > flags u`, `TerminalOptions.kittyKeyboardFlags`)
/// and a terminal reports ([KeyboardFlagsReport.flags]). Each makes the
/// terminal report more of the keyboard. [InputParser] decodes what each
/// sends, but the base layout key of [alternateKeys]; a key that types
/// text (no modifier but Shift) is the text it types, Shift not among its
/// modifiers, as typed text is without the flags.
abstract final class KittyKeyboardFlags {
  /// Keys whose legacy bytes are ambiguous come as `CSI code ; mods u`:
  /// Escape (`CSI 27 u`, so a lone ESC byte is no key), Alt, Ctrl and
  /// Super with a key, the keypad's keys. Text typed without them, and
  /// Enter, Tab and Backspace alone, keep their legacy bytes.
  static const disambiguate = 1;

  /// Repeats and releases are reported too, after the modifiers
  /// (`CSI 97 ; 1:3 u`, `CSI 1 ; 1:3 A`; `:1` a press, `:2` a repeat, `:3`
  /// a release): [KeyEvent.kind]. A key that types text, unless
  /// [allKeysAsEscapes], repeats as its text again, as a press does; Enter,
  /// Tab and Backspace are released unreported unless [allKeysAsEscapes].
  static const eventTypes = 2;

  /// A key's code comes with the key Shift makes of it and the key in the
  /// same place on a US layout (`CSI 97:65 ; 2 u`, `CSI 1089::99 ; 5 u`).
  /// The shifted key is what a key that types text types where nothing
  /// else tells it ([associatedText]); the base layout key is not decoded.
  static const alternateKeys = 4;

  /// Every key comes as an escape sequence: text typed (`CSI 97 u`, its
  /// code the unshifted key's), Enter, Tab and Backspace, and modifier
  /// keys alone (no [KeyEvent] for those). The text a key types with Shift
  /// or Caps Lock is in its sequence only with [associatedText] (with
  /// Shift, [alternateKeys] tells it too): without, Shift+A is `a` with
  /// Shift.
  static const allKeysAsEscapes = 8;

  /// With [allKeysAsEscapes], the text a key types follows its modifiers
  /// as code points (`CSI 97 ; 2 ; 65 u`). Undefined without
  /// [allKeysAsEscapes].
  static const associatedText = 16;
}

/// Reply to the kitty keyboard protocol query (`CSI ? flags u`): the
/// terminal implements the protocol; [flags] are the ones currently active
/// ([KittyKeyboardFlags]).
final class KeyboardFlagsReport extends InputEvent {
  /// A report of [flags].
  const KeyboardFlagsReport(this.flags);

  /// The [KittyKeyboardFlags] bits the terminal has on.
  final int flags;
  @override
  bool operator ==(Object other) =>
      other is KeyboardFlagsReport && other.flags == flags;
  @override
  int get hashCode => flags.hashCode;
}

/// The reply to the primary device attributes query (DA1, `CSI c`):
/// `CSI ? params c`.
///
/// Every terminal answers it, and answers queries in the order they came,
/// so a query sent last tells that the replies to those before it are in.
final class DeviceAttributes extends InputEvent {
  /// A reply of [params].
  const DeviceAttributes(this.params);

  /// The reply's parameters: the terminal's conformance level first, then
  /// the features it has (4 sixel graphics, say).
  final List<int> params;
}

/// Reply to OSC 10/11 (foreground/background color query) or OSC 4 (a
/// palette entry: [which] 4, the entry's [index]).
///
/// Each channel is scaled to 8 bits from the 1 to 4 hex digits the
/// terminal answers with (`rgb:ffff/8080/0000`).
final class ColorReport extends InputEvent {
  /// The color [rgb] of [which], [index] the palette entry for OSC 4.
  const ColorReport(this.which, this.rgb, {this.index = 0});

  /// The color the reply is about, as its OSC number: 10 the default
  /// foreground, 11 the default background, 4 a palette entry.
  final int which;

  /// The color, 0xRRGGBB.
  final int rgb;

  /// The palette entry (0..255) an OSC 4 reply is about; 0 for the others.
  final int index;
}

/// Whether colors are dark or light: a terminal's background, its color
/// scheme ([ColorSchemeReport]).
enum Brightness {
  /// Dark: light text on a dark background.
  dark,

  /// Light: dark text on a light background.
  light;

  /// That of [rgb] (0xRRGGBB): light when its luma (Rec. 601) is at least
  /// half that of white.
  static Brightness ofRgb(int rgb) {
    final luma =
        299 * ((rgb >> 16) & 0xFF) +
        587 * ((rgb >> 8) & 0xFF) +
        114 * (rgb & 0xFF);
    return luma * 2 >= 255000 ? light : dark;
  }
}

/// The terminal's color scheme turned dark or light (DEC mode 2031):
/// `CSI ? 997 ; 1 n` dark, `CSI ? 997 ; 2 n` light. `Terminal` turns the
/// reports on where the terminal has them, and asks for its default colors
/// again after each one: their [ColorReport]s follow.
final class ColorSchemeReport extends InputEvent {
  /// A report that the scheme turned [brightness].
  const ColorSchemeReport(this.brightness);

  /// Whether the scheme is dark or light now.
  final Brightness brightness;
  @override
  bool operator ==(Object other) =>
      other is ColorSchemeReport && other.brightness == brightness;
  @override
  int get hashCode => brightness.hashCode;
  @override
  String toString() => 'ColorScheme(${brightness.name})';
}

/// The reply to a cursor position query (CPR, `CSI 6 n`):
/// `CSI row ; col R`.
///
/// It reads as F3 with modifiers, so [InputParser] decodes it only while
/// [InputParser.expectCursorReport] is set; `Terminal` keeps the replies
/// to its own queries to itself.
final class CursorReport extends InputEvent {
  /// The cursor in column [x], row [y].
  const CursorReport(this.x, this.y);

  /// The cursor's column, 0 the leftmost.
  final int x;

  /// The cursor's row, 0 the top one.
  final int y;
}

/// An escape sequence the parser recognised as one but doesn't map to an
/// event: a key it has no [KeyCode] for, a reply to a query it doesn't
/// decode, a sequence cut off or aborted by the next ESC.
///
/// It is delivered rather than dropped, so that its bytes never come as
/// text typed.
final class UnknownSequence extends InputEvent {
  /// The sequence [bytes].
  const UnknownSequence(this.bytes);

  /// The sequence's bytes, from its ESC on.
  final List<int> bytes;

  /// `Unknown(...)` with the bytes as text, ESC spelled out.
  @override
  String toString() =>
      'Unknown(${String.fromCharCodes(bytes).replaceAll('\x1b', 'ESC')})';
}
