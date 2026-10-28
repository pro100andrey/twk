/// A question answered yes or no: [ConfirmInput].
library;

import 'package:twk_core/twk_core.dart' show Attr, MainAxisSize, TextWrap;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'pressable.dart';

/// A yes-or-no question: [prompt], then the answers [yes] and [no] to
/// press, which call [onConfirmed].
///
/// Each answer has a blank on either side: `Delete 3 files?  Yes   No `.
/// One of them is highlighted, [defaultValue]'s at first. While it has the
/// focus, `y` answers yes and `n` no, either case, Enter the one
/// highlighted, Left and Right highlight yes and no; `y` and `n` hinted.
/// An answer clicked is given too. Each answer calls [onConfirmed] with
/// true for yes, false for no, and highlights it. Disabled with no
/// [onConfirmed]: then it takes neither the focus, which Tab passes by,
/// nor the mouse.
///
/// A question whose answer is no unless the user says yes:
///
/// ```dart
/// ConfirmInput(
///   'Delete 3 files?',
///   defaultValue: false,
///   autofocus: true,
///   onConfirmed: (yes) => print(yes ? 'deleting' : 'kept'),
/// )
/// ```
///
/// One row, as wide as its text within its constraints. The answers are
/// chips, as a `Button` is, that flash when they are given. The styles,
/// each merged over those before it: the theme's text and [style] for the
/// row; [answerStyle] for the answer not highlighted, [ThemeData.muted] on
/// a chip of [ThemeData.surface] when null; [highlightedStyle] for the
/// one highlighted, [ThemeData.primary] in bold on the chip when null,
/// and [focusedStyle] over it while the input has the focus, the chip
/// filled with [ThemeData.primary] and the text [ThemeData.onPrimary] when
/// null; [disabledStyle] for the row while it is disabled,
/// [ThemeData.muted] when null, both answers in [answerStyle] over it, or
/// on a fainter chip while [answerStyle] is null.
///
/// A plain look, the answers without chips, the one highlighted in the
/// primary color and reversed while focused: `answerStyle: const
/// Style()`, `highlightedStyle: theme.primary.merge(const Style(attrs:
/// Attr.bold))` and `focusedStyle: const Style(attrs: Attr.reverse)`.
///
/// See also:
///
///  * `Button`, one action to press.
final class ConfirmInput extends StatefulWidget {
  /// Asks [prompt], the answer given to [onConfirmed]; disabled when that
  /// is null.
  const ConfirmInput(
    this.prompt, {
    required this.onConfirmed,
    super.key,
    this.defaultValue = true,
    this.yes = 'Yes',
    this.no = 'No',
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.answerStyle,
    this.highlightedStyle,
    this.focusedStyle,
    this.disabledStyle,
  });

  /// The question; nothing before the answers when empty.
  final String prompt;

  /// Called with the answer: true for yes; null for a disabled input.
  final void Function(bool value)? onConfirmed;

  /// The answer highlighted at first, which Enter gives.
  final bool defaultValue;

  /// The label of yes.
  final String yes;

  /// The label of no.
  final String no;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The row, the theme's text under it.
  final Style? style;

  /// The answer not highlighted, over the row; [ThemeData.muted] on
  /// [ThemeData.surface] when null.
  final Style? answerStyle;

  /// The answer highlighted, over the row; [ThemeData.primary] in bold on
  /// [ThemeData.surface] when null.
  final Style? highlightedStyle;

  /// The answer highlighted while it has the focus, over
  /// [highlightedStyle]; a fill of [ThemeData.primary] with the text
  /// [ThemeData.onPrimary] in bold when null.
  final Style? focusedStyle;

  /// The row while it is disabled, over [style]; [ThemeData.muted] when
  /// null.
  final Style? disabledStyle;

  @override
  State<ConfirmInput> createState() => _ConfirmInputState();
}

final class _ConfirmInputState extends State<ConfirmInput> {
  late bool _highlighted = widget.defaultValue;

  // the times each answer was given, for its chip to flash
  var _yeses = 0;
  var _nos = 0;

  void _answer(bool value) {
    setState(() {
      _highlighted = value;
      if (value) {
        _yeses++;
      } else {
        _nos++;
      }
    });
    widget.onConfirmed?.call(value);
  }

  void _yes() => _answer(true);

  void _no() => _answer(false);

  void _enter() => _answer(_highlighted);

  void _highlight(bool value) => setState(() => _highlighted = value);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirmed != null;
    return Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: {
        'y': _yes,
        'Y': _yes,
        'n': _no,
        'N': _no,
        'enter': _enter,
        'left': () => _highlight(true),
        'right': () => _highlight(false),
      },
      hints: const {'y': 'yes', 'n': 'no'},
      builder: (context, focused) {
        final theme = Theme.of(context);
        final row = rowStyle(
          theme,
          style: widget.style,
          focused: false,
          focusedStyle: const Style(),
          enabled: enabled,
          disabledStyle: widget.disabledStyle,
        );
        final answerStyle = widget.answerStyle;
        final Style other;
        final Style highlighted;
        if (!enabled) {
          other = highlighted = answerStyle == null
              ? row.merge(
                  Style(
                    bg: buttonDisabledStyle(theme).bg,
                    attrsOff: Attr.bold,
                  ),
                )
              : row.merge(answerStyle);
        } else {
          other = row.merge(
            answerStyle ??
                theme.surface.merge(
                  theme.muted.merge(const Style(attrsOff: Attr.bold)),
                ),
          );
          final rest = row.merge(
            widget.highlightedStyle ?? buttonStyle(theme),
          );
          highlighted = focused
              ? rest.merge(
                  widget.focusedStyle ?? buttonFocusedStyle(theme, rest),
                )
              : rest;
        }
        Widget answer(String label, bool value) => GestureDetector(
          onTap: enabled ? (_) => _answer(value) : null,
          child: PressChip(
            ' $label ',
            style: value == _highlighted ? highlighted : other,
            presses: value ? _yeses : _nos,
            enabled: enabled,
          ),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: [
            if (widget.prompt.isNotEmpty)
              Text(widget.prompt, style: row, wrap: TextWrap.none, maxLines: 1),
            answer(widget.yes, true),
            answer(widget.no, false),
          ],
        );
      },
    );
  }
}
