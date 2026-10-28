/// What the controls share: a node of the focus tree that a disabled
/// control keeps out of the focus, the keys it takes while it has it, and
/// a click that focuses it: [Pressable].
library;

import 'package:twk_core/twk_core.dart' show Attr, Brightness, Color, TextWrap;

import '../animation/animation_controller.dart';
import '../animation/ticker.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../style/color_mix.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show segmenterOf;
import '../text/widgets.dart';

/// A control's node of the focus tree: what [builder] builds, which takes
/// the focus, its keys and a click of the mouse while [enabled].
///
/// Disabled, it cannot take the focus, and Tab passes it by. Enabled,
/// [bindings] are a layer of the focus tree right below it, with their
/// [hints]: they get its keys from the moment it has the focus, and
/// [onKeyEvent] those they leave. A press of the left button over it
/// focuses it, while it is enabled, and a tap over it calls [onTap] (see
/// `GestureDetector`). [builder] is called again as the focus comes and
/// goes.
///
/// A control of its own, which Space and a click turn on and off, shown in
/// the primary color while it has the focus:
///
/// ```dart
/// Pressable(
///   bindings: {'space': () => print('toggled')},
///   hints: const {'space': 'toggle'},
///   onTap: (_) => print('toggled'),
///   builder: (context, focused) => Text(
///     '[ power ]',
///     style: focused ? Theme.of(context).primary : const Style(),
///   ),
/// )
/// ```
///
/// See also:
///
///  * [Focus], the node of the focus tree without the rest.
///  * `KeyBindings`, the keys without the node.
final class Pressable extends StatefulWidget {
  /// A control built by [builder], enabled unless [enabled] is false.
  const Pressable({
    required this.builder,
    super.key,
    this.enabled = true,
    this.bindings = const {},
    this.hints = const {},
    this.onKeyEvent,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  /// Builds what it shows, by whether it has the focus.
  final Widget Function(BuildContext context, bool focused) builder;

  /// Whether it can take the focus and the presses.
  final bool enabled;

  /// The keys it takes while it has the focus, as `KeyBindings` takes them.
  final Map<String, VoidCallback?> bindings;

  /// What the [bindings] do.
  final Map<String, String> hints;

  /// Gets the keys while it has the focus, those the [bindings] leave.
  final FocusOnKeyEventCallback? onKeyEvent;

  /// A tap of the left button over it, the cell in its coordinates; null
  /// for a disabled control.
  final PointerEventListener? onTap;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  @override
  State<Pressable> createState() => _PressableState();
}

final class _PressableState extends State<Pressable> {
  FocusNode? _own;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_changed);
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.focusNode, oldWidget.focusNode)) {
      // the Focus below lets an own node go after this build: it is
      // disposed with this state
      (oldWidget.focusNode ?? _own)?.removeListener(_changed);
      _node.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _down(PointerEvent event) {
    if (event.button == 0) {
      _node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: enabled,
      onKeyEvent: widget.onKeyEvent,
      child: KeyBindings(
        enabled ? widget.bindings : const {},
        hints: enabled ? widget.hints : const {},
        child: Listener(
          onDown: enabled ? _down : null,
          child: GestureDetector(
            onTap: widget.onTap,
            child: widget.builder(context, _node.hasFocus),
          ),
        ),
      ),
    );
  }
}

/// The style of a control's row in [theme]: its text and [style];
/// [focusedStyle] over it while [focused]; or [disabledStyle] while not
/// [enabled], [ThemeData.muted] when null.
Style rowStyle(
  ThemeData theme, {
  required Style? style,
  required bool focused,
  required Style focusedStyle,
  required bool enabled,
  required Style? disabledStyle,
}) {
  final row = theme.text.merge(style ?? const Style());
  if (!enabled) {
    return row.merge(disabledStyle ?? theme.muted);
  }
  return focused ? row.merge(focusedStyle) : row;
}

/// A mark that is on in [theme]: [ThemeData.primary] in bold.
Style markStyle(ThemeData theme) =>
    theme.primary.merge(const Style(attrs: Attr.bold));

/// A row that has the focus in [theme], as the design marks a focused
/// Checkbox, Switch or RadioGroup row: on [ThemeData.selection].
Style focusedRow(ThemeData theme) => theme.selection;

/// The spans of a mark between brackets, [open] [mark] [close]: [mark] in
/// [markStyle] while [on] and [enabled], the brackets over it in
/// [bracketStyle], [ThemeData.muted] not bold when null.
List<Span> bracketed(
  ThemeData theme,
  String open,
  String mark,
  String close,
  bool on,
  bool enabled,
  Style? bracketStyle,
) {
  final marked = on && enabled ? markStyle(theme) : const Style();
  final brackets = marked.merge(
    bracketStyle ?? theme.muted.merge(const Style(attrsOff: Attr.bold)),
  );
  return [Span(open, brackets), Span(mark, marked), Span(close, brackets)];
}

/// A button at rest in [theme]: [ThemeData.primary] in bold on a chip of
/// [ThemeData.surface].
Style buttonStyle(ThemeData theme) => theme.surface.merge(markStyle(theme));

/// A button that has the focus, over [rest]: the chip filled with the
/// color of [rest]'s text ([ThemeData.primary] where it has none) and
/// text that reads on it ([ThemeData.fill]), bold.
Style buttonFocusedStyle(ThemeData theme, Style rest) =>
    theme.fill(rest.fg).merge(const Style(attrs: Attr.bold));

/// A button the mouse is over in [theme], over [rest]: its chip 0.18 of
/// the way to its text color, [ThemeData.hover] where either is not RGB;
/// nothing where [rest] has no chip.
Style buttonHoverStyle(ThemeData theme, Style rest) => rest.bg == null
    ? const Style()
    : switch (mixRgb(rest.bg, rest.fg, 0.18)) {
        final bg? => Style(bg: bg),
        null => Style(bg: theme.hover.bg),
      };

/// A disabled button in [theme]: [ThemeData.muted], not bold, on a chip
/// half of the way from [ThemeData.surface] to [ThemeData.background].
Style buttonDisabledStyle(ThemeData theme) => theme.muted.merge(
  Style(
    bg: mixRgb(theme.surface.bg, theme.background.bg, 0.5) ?? theme.surface.bg,
    attrsOff: Attr.bold,
  ),
);

/// [text] on one row in [style], as a button's chip: [hoverStyle] over it
/// while the mouse is over it, when that is not null; a flash each time
/// [presses] grows, and while the left button is held over it, its
/// background 0.28 of the way to white on a dark theme, black on a light
/// one, back to its own over [flash]. A background that is not RGB does
/// not flash.
final class PressChip extends StatefulWidget {
  /// A chip of [text] in [style] that flashes as [presses] grows.
  const PressChip(
    this.text, {
    required this.style,
    super.key,
    this.hoverStyle,
    this.presses = 0,
    this.enabled = true,
    this.flash = const Duration(milliseconds: 260),
  }) : builder = null;

  /// A chip of what [builder] builds in the style the chip has now, [style]
  /// with the hover and the flash over it, and whether the mouse is over
  /// it: a box of more than a row, as `Button.outlined` is.
  const PressChip.builder({
    required Widget Function(BuildContext context, Style style, bool hovered)
    this.builder,
    required this.style,
    super.key,
    this.hoverStyle,
    this.presses = 0,
    this.enabled = true,
    this.flash = const Duration(milliseconds: 260),
  }) : text = '';

  /// What it shows, the blanks around it too; empty for a [builder].
  final String text;

  /// Builds what it shows instead of [text]; null for [text].
  final Widget Function(BuildContext context, Style style, bool hovered)?
  builder;

  /// The chip at rest: its text and background.
  final Style style;

  /// Over [style] while the mouse is over it; null for no hover, and then
  /// it asks the terminal for no motion of the mouse.
  final Style? hoverStyle;

  /// How many times it has been pressed: each one more flashes it.
  final int presses;

  /// Whether a button held over it flashes it.
  final bool enabled;

  /// How long a flash takes to fade.
  final Duration flash;

  @override
  State<PressChip> createState() => _PressChipState();
}

final class _PressChipState extends State<PressChip>
    with TickerProviderStateMixin {
  AnimationController? _flash;
  var _hovered = false;
  var _held = false;

  @override
  void didUpdateWidget(PressChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.presses != oldWidget.presses) {
      (_flash ??= AnimationController(vsync: this)..addListener(_changed))
        ..duration = widget.flash
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  // over it: told by the hover region where there is one, else by the
  // press and the drags after it
  void _down(PointerEvent event) {
    if (event.button == 0) {
      setState(() {
        _held = true;
        _hovered = true;
      });
    }
  }

  void _up(PointerEvent event) {
    if (_held) {
      setState(() {
        _held = false;
        _hovered = _hovered && widget.hoverStyle != null;
      });
    }
  }

  void _drag(PointerEvent event) {
    if (_held && widget.hoverStyle == null && widget.builder == null) {
      _hover(
        event.y == 0 &&
            event.x >= 0 &&
            event.x < segmenterOf(context).width(widget.text),
      );
    }
  }

  void _hover(bool hovered) {
    if (hovered != _hovered) {
      setState(() => _hovered = hovered);
    }
  }

  /// How much of the flash shows, 1 to 0.
  double get _strength {
    if (!widget.enabled) {
      return 0;
    }
    if (_held && _hovered) {
      return 1;
    }
    final flash = _flash;
    return flash != null && flash.status == AnimationStatus.forward
        ? 1 - flash.value
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final hoverStyle = widget.hoverStyle;
    var style = widget.style;
    if (hoverStyle != null && _hovered && widget.enabled) {
      style = style.merge(hoverStyle);
    }
    final k = _strength;
    if (k > 0) {
      final toward = Theme.of(context).brightness == Brightness.dark
          ? const Color.rgb(0xff, 0xff, 0xff)
          : const Color.rgb(0, 0, 0);
      if (mixRgb(style.bg, toward, 0.28 * k) case final bg?) {
        style = style.merge(Style(bg: bg));
      }
    }
    var chip = switch (widget.builder) {
      final build? => build(context, style, _hovered && widget.enabled),
      null => Text(widget.text, style: style, wrap: TextWrap.none, maxLines: 1),
    };
    if (widget.enabled) {
      chip = Listener(onDown: _down, onUp: _up, onDrag: _drag, child: chip);
    }
    if (hoverStyle != null && widget.enabled) {
      chip = MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: chip,
      );
    }
    return chip;
  }
}
