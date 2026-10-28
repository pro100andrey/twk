/// What is pressed to do something: [Button].
library;

import 'package:twk_core/twk_core.dart' show Attr, Brightness, Color, TextWrap;

import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show segmenterOf;
import '../text/widgets.dart';
import 'pressable.dart';

/// A button that calls [onPressed] when it is clicked, or when Enter or
/// Space is pressed while it has the focus.
///
/// It shows [label] with a blank on either side, and hints Enter. Disabled
/// with no [onPressed]: then it takes neither the focus, which Tab passes
/// by, nor the mouse. A press of the mouse over it gives it the focus; the
/// click is the button's release over it.
///
/// A button that saves, and one that cannot be pressed:
///
/// ```dart
/// Row(
///   children: [
///     Button('Save', onPressed: () => print('saved')),
///     const Button('Delete', onPressed: null),
///   ],
/// )
/// ```
///
/// One row, as wide as its label within its constraints. At rest a chip:
/// the theme's text and [style], by default [ThemeData.primary] in bold on
/// [ThemeData.surface]; where it sits on the surface already (the nearest
/// [Box] above it with a background has that one: a dialog, a window, a
/// raised panel), on a chip a step from it towards the theme's text, 0.08
/// of the way on a dark theme and 0.06 on a light one. Over it, each when
/// null as the design draws it: [focusedStyle] while it has the focus,
/// the chip filled with the color of its text, the text
/// [ThemeData.onPrimary]; [hoverStyle] while the mouse is over it and it
/// has not the focus, the chip a step towards its text color;
/// [disabledStyle] while it is disabled, [ThemeData.muted], and by
/// default on a fainter chip and not bold. A press, by key or
/// mouse, flashes the chip (as long as the button is held over it): its
/// background a step towards white on a dark theme, black on a light one,
/// fading in 260 ms. Without a chip there is no hover and no flash; a
/// hover that changes nothing leaves the motion of the mouse unreported.
///
/// A plain look, text without a chip, reversed while focused:
/// `style: theme.primary.merge(const Style(attrs: Attr.bold))` and
/// `focusedStyle: const Style(attrs: Attr.reverse)`.
///
/// Two more looks, a row as wide as the label and two blanks either side,
/// or as wide as its constraints make it (in an `Expanded`), the label in
/// the middle: [Button.outlined], the label between two edges (`▕` and
/// `▏`) in [ThemeData.border], the text's color under the mouse and
/// [ThemeData.primary] with the label while it has the focus; and
/// [Button.filled], a fill of [ThemeData.primary] ([ThemeData.fill]), a
/// step towards its text under the mouse, and while it has the focus a
/// fill of the theme's text color, bold. [style]'s text color is the
/// color of either, the edges' or the fill's. `tall: true` makes either
/// three rows, a box drawn around the label or a fill a row above and
/// below it, and three blanks either side: a pair of answers to a
/// question.
///
/// ```dart
/// Row(
///   children: [
///     Expanded(
///       child: Button.outlined('Cancel', tall: true, onPressed: () {}),
///     ),
///     const SizedBox(width: 2),
///     Expanded(
///       child: Button.filled('Approve', tall: true, onPressed: () {}),
///     ),
///   ],
/// )
/// ```
///
/// A screen reader reads it as a [SemanticsRole.button] of its label,
/// `disabled` while it is.
///
/// See also:
///
///  * `Link`, text that opens a URL when clicked.
///  * `ConfirmInput`, a yes-or-no question with two answers to press.
final class Button extends StatefulWidget {
  /// A button showing [label] that calls [onPressed], disabled when that
  /// is null.
  const Button(
    this.label, {
    required this.onPressed,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.focusedStyle,
    this.hoverStyle,
    this.disabledStyle,
  }) : _look = _Look.chip,
       tall = false;

  /// A button of [label] between two edges, or with [tall] in a box drawn
  /// around it: in [ThemeData.border], or [style]'s text color, at rest.
  const Button.outlined(
    this.label, {
    required this.onPressed,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.tall = false,
  }) : focusedStyle = null,
       hoverStyle = null,
       disabledStyle = null,
       _look = _Look.outlined;

  /// A button of [label] on a fill of [ThemeData.primary], or of [style]'s
  /// text color, at rest; with [tall] three rows of it.
  const Button.filled(
    this.label, {
    required this.onPressed,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.style,
    this.tall = false,
  }) : focusedStyle = null,
       hoverStyle = null,
       disabledStyle = null,
       _look = _Look.filled;

  final _Look _look;

  /// Whether a [Button.outlined] or a [Button.filled] is three rows, a box
  /// or a fill around its label; one row when false.
  final bool tall;

  /// The text it shows, with a blank on either side; what a screen reader
  /// reads.
  final String label;

  /// What a press does; null for a disabled button.
  final VoidCallback? onPressed;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  /// The button at rest; [ThemeData.primary] in bold on
  /// [ThemeData.surface] when null, or on a chip lifted from the surface
  /// where it sits on that.
  final Style? style;

  /// Over [style] while it has the focus; when null, a fill of the color
  /// of the text at rest, [ThemeData.primary] where that has none, with
  /// the text [ThemeData.onPrimary] in bold.
  final Style? focusedStyle;

  /// Over [style] while the mouse is over it and it has not the focus;
  /// when null, its background 0.18 of the way to its text color where
  /// both are RGB.
  final Style? hoverStyle;

  /// Over [style] while it is disabled; [ThemeData.muted] when null, and
  /// with [style] null too, not bold and on a chip half of the way from
  /// [ThemeData.surface] to [ThemeData.background].
  final Style? disabledStyle;

  @override
  State<Button> createState() => _ButtonState();
}

final class _ButtonState extends State<Button> {
  var _presses = 0;

  void _press() {
    final onPressed = widget.onPressed;
    if (onPressed != null) {
      setState(() => _presses++);
      onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final style = widget.style;
    final pressable = Pressable(
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      bindings: {'enter': _press, 'space': _press},
      hints: const {'enter': 'press'},
      onTap: enabled ? (_) => _press() : null,
      builder: (context, focused) {
        final theme = Theme.of(context);
        if (widget._look != _Look.chip) {
          return _boxed(theme, focused: focused, enabled: enabled);
        }
        final rest = theme.text.merge(
          style ?? _lifted(theme, buttonStyle(theme), context),
        );
        // one that changes nothing asks for no motion of the mouse
        final hover = enabled
            ? widget.hoverStyle ?? buttonHoverStyle(theme, rest)
            : const Style();
        return PressChip(
          ' ${widget.label} ',
          style: !enabled
              ? rest.merge(
                  widget.disabledStyle ??
                      (style == null
                          ? buttonDisabledStyle(theme)
                          : theme.muted),
                )
              : focused
              ? rest.merge(
                  widget.focusedStyle ?? buttonFocusedStyle(theme, rest),
                )
              : rest,
          hoverStyle: hover == const Style()
              ? null
              : focused
              ? const Style()
              : hover,
          presses: _presses,
          enabled: enabled,
        );
      },
    );
    return Semantics(
      role: SemanticsRole.button,
      label: widget.label,
      state: SemanticsState(disabled: !enabled),
      child: pressable,
    );
  }
}

extension on _ButtonState {
  /// A button of [Button.outlined] or [Button.filled], [focused] or not.
  Widget _boxed(
    ThemeData theme, {
    required bool focused,
    required bool enabled,
  }) {
    final outlined = widget._look == _Look.outlined;
    final color = widget.style?.fg;
    final Style rest;
    if (outlined) {
      rest = !enabled
          ? theme.muted
          : focused
          ? theme.primary.merge(const Style(attrs: Attr.bold))
          : theme.text;
    } else {
      rest = !enabled
          ? buttonDisabledStyle(theme)
          : focused
          ? theme.fill(theme.text.fg).merge(const Style(attrs: Attr.bold))
          : theme.fill(color ?? theme.primary.fg);
    }
    return PressChip.builder(
      style: rest,
      hoverStyle: enabled && !focused && !outlined
          ? buttonHoverStyle(theme, rest)
          : enabled && !focused
          ? const Style()
          : null,
      presses: _presses,
      enabled: enabled,
      builder: (context, style, hovered) {
        final label = Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(widget.label, style: style, wrap: TextWrap.none),
        );
        final tall = widget.tall;
        if (!outlined) {
          return Box(
            style: style,
            padding: tall
                ? const EdgeInsets.only(left: 3, right: 3, top: 1, bottom: 1)
                : const EdgeInsets.x(2),
            child: label,
          );
        }
        final line = !enabled
            ? theme.faint
            : focused
            ? theme.primary
            : hovered
            ? theme.text
            : color == null
            ? theme.border
            : Style(fg: color);
        if (tall) {
          return Box(
            border: Border.all(style: line),
            padding: const EdgeInsets.x(2),
            child: label,
          );
        }
        // one row: the edges at either end, the label in the middle of what
        // is between them; bars where block elements are two columns wide
        final thin = segmenterOf(context).width('▕') == 1;
        final open = Text(thin ? '▕' : '│', style: line);
        final close = Text(thin ? '▏' : '│', style: line);
        final inner = Padding(padding: const EdgeInsets.x(1), child: label);
        return LayoutBuilder(
          builder: (context, c) => Row(
            mainAxisSize: c.minW == c.maxW
                ? MainAxisSize.max
                : MainAxisSize.min,
            children: [
              open,
              if (c.minW == c.maxW) Expanded(child: inner) else inner,
              close,
            ],
          ),
        );
      },
    );
  }
}

/// The looks of a [Button].
enum _Look { chip, outlined, filled }

/// [chip], a button's at rest, where it sits at [context]: a step from its
/// background towards [ThemeData.text] where that is the background it
/// sits on ([_sitsOn]), so that it stands out of it, as is.
Style _lifted(ThemeData theme, Style chip, BuildContext context) {
  final bg = chip.bg;
  if (bg == null || _sitsOn(context) != bg) {
    return chip;
  }
  final k = theme.brightness == Brightness.dark ? 0.08 : 0.06;
  final lifted = mixRgb(bg, theme.text.fg, k);
  return lifted == null ? chip : chip.merge(Style(bg: lifted));
}

/// The background of the nearest [Box] above [context] that has an opaque
/// one: what a widget there sits on.
Color? _sitsOn(BuildContext context) {
  Color? bg;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Box) {
      final style = widget.style;
      if (style?.bg != null && style!.bgAlpha == 255) {
        bg = style.bg;
        return false;
      }
    }
    return true;
  });
  return bg;
}
