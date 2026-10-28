/// What is drawn around a field: [InputDecoration], its [InputBorder]s, and
/// the [InputDecorator] that draws it around any child.
///
/// @docImport '../controls/form.dart';
/// @docImport 'text_field.dart';
library;

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show EdgeInsets, TextOverflow;

import '../focus/focus_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// The line drawn around or under the row of an [InputDecorator]:
/// [InputBorder.none], an [UnderlineInputBorder] or an
/// [OutlineInputBorder]. Flutter's InputBorder.
@immutable
sealed class InputBorder {
  const InputBorder();

  /// No line: the row alone, its label above it.
  static const InputBorder none = _NoInputBorder();
}

final class _NoInputBorder extends InputBorder {
  const _NoInputBorder();
}

/// A line under the row of an [InputDecorator], as wide as the row, its
/// label above the row: three rows with a label, two without.
final class UnderlineInputBorder extends InputBorder {
  /// A line of [type] under the row: [BorderType.single] by default.
  const UnderlineInputBorder({this.type = BorderType.single});

  /// The line it is drawn with.
  final BorderType type;

  @override
  bool operator ==(Object other) =>
      other is UnderlineInputBorder && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// A box around the row of an [InputDecorator], its label on the box's
/// top edge and a cell between its sides and the row: three rows.
final class OutlineInputBorder extends InputBorder {
  /// A box of [type] around the row: [BorderType.rounded] by default.
  const OutlineInputBorder({this.type = BorderType.rounded});

  /// The lines the box is drawn with.
  final BorderType type;

  @override
  bool operator ==(Object other) =>
      other is OutlineInputBorder && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// What an [InputDecorator] draws around a field: an [icon] before it, a
/// [labelText] naming it, what goes before and after its text
/// ([prefixIcon], [prefixText], [suffixText], [suffixIcon]), a [border]
/// around or under it, a fill ([filled]) and a row under it of a
/// [helperText] or an [errorText] and a [counterText]. Each is left out
/// while null. Flutter's InputDecoration, drawn in cells:
///
/// ```text
/// ╭ Email ───────────────────╮       Site
/// │ you@example.com          │       https://twk.dev
/// ╰──────────────────────────╯       ───────────────
/// we never share it      0/40        where it lives
/// ```
///
/// The label does not float: it stays on the box's top edge, or above the
/// row, whether the field is empty or not, the field's placeholder
/// showing in the row while it is. Unlike Flutter's, a [TextField] has
/// no decoration by default, being often drawn in a `Box` of its own: a
/// line under it is `decoration: InputDecoration()`.
///
/// A field of an email address in a rounded box, an icon before it:
///
/// ```dart
/// const TextField(
///   placeholder: 'you@example.com',
///   decoration: InputDecoration(
///     icon: Text('✉'),
///     labelText: 'Email',
///     helperText: 'we never share it',
///     border: OutlineInputBorder(),
///   ),
/// )
/// ```
@immutable
final class InputDecoration {
  /// A decoration of the parts given; with none, a line under the field.
  const InputDecoration({
    this.icon,
    this.labelText,
    this.helperText,
    this.errorText,
    this.counterText,
    this.counter,
    this.prefixIcon,
    this.prefixText,
    this.suffixIcon,
    this.suffixText,
    this.border = const UnderlineInputBorder(),
    this.filled = false,
    this.fillStyle,
  });

  /// Before the field, outside its border, on the row of its text, a cell
  /// apart: a `Text` of a symbol (`Text('✉')`) or any widget one row
  /// tall. Its text in [ThemeData.muted], [ThemeData.primary] while the
  /// focus is in the field, where its own style leaves the color unset.
  final Widget? icon;

  /// What the field is, on the top edge of an [OutlineInputBorder] or on
  /// a row above the field; in [ThemeData.muted], [ThemeData.primary]
  /// while the focus is in it, [ThemeData.error] with an [errorText]. A
  /// [TextField] without a `semanticsLabel` is read by its label.
  final String? labelText;

  /// A line under the field that says what goes in it, in
  /// [ThemeData.muted]; the [errorText] in its place where there is one.
  final String? helperText;

  /// What is wrong with the text, under the field in [ThemeData.error], in
  /// place of the [helperText]; the border and the label take its color.
  final String? errorText;

  /// At the right of the row under the field, in [ThemeData.muted]: how
  /// many characters there are of how many (`3/40`). A [TextField] with a
  /// `maxLength` counts its characters there itself while this and
  /// [counter] are null.
  final String? counterText;

  /// In place of [counterText], a widget of its own.
  final Widget? counter;

  /// Inside the border, before the text, a cell apart: a symbol, as
  /// [icon]; in [ThemeData.muted], [ThemeData.primary] while the focus is
  /// in the field.
  final Widget? prefixIcon;

  /// Inside the border, right before the text, in [ThemeData.muted]:
  /// `https://`, `$`.
  final String? prefixText;

  /// Inside the border, after the text, a cell apart: a symbol, as
  /// [prefixIcon].
  final Widget? suffixIcon;

  /// Inside the border, right after the field, in [ThemeData.muted]:
  /// `.com`, `kg`.
  final String? suffixText;

  /// The line around or under the field: [UnderlineInputBorder] by
  /// default, [OutlineInputBorder] or [InputBorder.none]. In
  /// [ThemeData.border], [ThemeData.primary] while the focus is in the
  /// field, [ThemeData.error] with an [errorText].
  final InputBorder border;

  /// Whether the field's row, inside its border, is filled with
  /// [fillStyle], a cell before and after it.
  final bool filled;

  /// What fills the row with [filled]: [ThemeData.well] when null.
  final Style? fillStyle;

  /// This decoration with the parts given in place of its own.
  InputDecoration copyWith({
    Widget? icon,
    String? labelText,
    String? helperText,
    String? errorText,
    String? counterText,
    Widget? counter,
    Widget? prefixIcon,
    String? prefixText,
    Widget? suffixIcon,
    String? suffixText,
    InputBorder? border,
    bool? filled,
    Style? fillStyle,
  }) => InputDecoration(
    icon: icon ?? this.icon,
    labelText: labelText ?? this.labelText,
    helperText: helperText ?? this.helperText,
    errorText: errorText ?? this.errorText,
    counterText: counterText ?? this.counterText,
    counter: counter ?? this.counter,
    prefixIcon: prefixIcon ?? this.prefixIcon,
    prefixText: prefixText ?? this.prefixText,
    suffixIcon: suffixIcon ?? this.suffixIcon,
    suffixText: suffixText ?? this.suffixText,
    border: border ?? this.border,
    filled: filled ?? this.filled,
    fillStyle: fillStyle ?? this.fillStyle,
  );
}

/// [child], a field, in [decoration]: its icon, label, border, fill and
/// the row under it, colored by whether the focus is in [child] and
/// whether [enabled]. Flutter's InputDecorator; a [TextField] or a
/// [TextFormField] with a `decoration` draws itself in one.
///
/// It is as wide as its constraints allow, [child] taking the room its
/// prefix and suffix leave in the row (an `Expanded`'s); [child] is one
/// row tall.
///
/// Another control as a field, a label on its box:
///
/// ```dart
/// InputDecorator(
///   decoration: const InputDecoration(
///     labelText: 'Language',
///     border: OutlineInputBorder(),
///   ),
///   child: Select<String>(
///     choices: const [Choice('en', 'English'), Choice('uk', 'Ukrainian')],
///     value: 'en',
///     onChanged: (v) => print(v),
///   ),
/// )
/// ```
final class InputDecorator extends StatelessWidget {
  /// Draws [decoration] around [child].
  const InputDecorator({
    required this.decoration,
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// What is drawn around [child].
  final InputDecoration decoration;

  /// The field.
  final Widget child;

  /// Whether the field takes input: false draws the label, the icons and
  /// the border in [ThemeData.muted] and [ThemeData.border], whatever the
  /// focus and the error; the error's message still shows, as Flutter's
  /// does, in [ThemeData.error] (a form disabled while it submits keeps
  /// what is wrong in view).
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      decoratedField(decoration, enabled: enabled, child: child);
}

/// What an [InputDecorator] builds: [child] in [decoration], [aroundBox]
/// around the part of it its border draws (the box of an outline, the row
/// and the line under it, the row alone without a border): what a control
/// opens a list under, from the border's left edge. Hidden from the
/// library's exports.
Widget decoratedField(
  InputDecoration decoration, {
  required Widget child,
  bool enabled = true,
  Widget Function(Widget box)? aroundBox,
}) => FocusBuilder(
  debugLabel: 'InputDecorator',
  builder: (context, hasFocus, child) => _decorated(
    decoration,
    Theme.of(context),
    enabled: enabled,
    focused: enabled && hasFocus,
    aroundBox: aroundBox ?? _same,
    child: child!,
  ),
  child: child,
);

Widget _same(Widget box) => box;

Widget _decorated(
  InputDecoration d,
  ThemeData theme, {
  required bool enabled,
  required bool focused,
  required Widget Function(Widget box) aroundBox,
  required Widget child,
}) {
  final error = d.errorText != null;
  final line = !enabled
      ? theme.border
      : error
      ? theme.error
      : focused
      ? theme.primary
      : theme.border;
  final labelStyle = !enabled
      ? theme.muted
      : error
      ? theme.error
      : focused
      ? theme.primary
      : theme.muted;
  final iconStyle = focused ? theme.primary : theme.muted;
  final fill = d.filled ? d.fillStyle ?? theme.well : null;
  final label = d.labelText;
  final border = d.border;

  Widget row = Row(
    children: [
      if (d.prefixIcon case final icon?)
        Padding(
          padding: const EdgeInsets.only(right: 1),
          child: DefaultTextStyle(style: iconStyle, child: icon),
        ),
      if (d.prefixText case final text?) Text(text, style: theme.muted),
      Expanded(child: child),
      if (d.suffixText case final text?) Text(text, style: theme.muted),
      if (d.suffixIcon case final icon?)
        Padding(
          padding: const EdgeInsets.only(left: 1),
          child: DefaultTextStyle(style: iconStyle, child: icon),
        ),
    ],
  );
  final outlined = border is OutlineInputBorder;
  if (border is OutlineInputBorder) {
    row = Box(
      style: fill,
      border: Border.all(type: border.type, style: line),
      titles: [
        if (label != null) BorderTitle(' $label ', style: labelStyle),
      ],
      padding: const EdgeInsets.x(1),
      child: row,
    );
  } else if (fill != null) {
    row = Box(style: fill, padding: const EdgeInsets.x(1), child: row);
  }

  final under = error ? d.errorText : d.helperText;
  final counter =
      d.counter ??
      switch (d.counterText) {
        final text? => Text(text),
        null => null,
      };
  final column = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null && !outlined)
        Text(
          label,
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      aroundBox(switch (border) {
        UnderlineInputBorder(:final type) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            Divider(type: type, style: line),
          ],
        ),
        _ => row,
      }),
      if (under != null || counter != null)
        Row(
          gap: 1,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                under ?? '',
                style: error ? theme.error : theme.muted,
              ),
            ),
            if (counter != null)
              DefaultTextStyle(style: theme.muted, child: counter),
          ],
        ),
    ],
  );
  final icon = d.icon;
  if (icon == null) {
    return column;
  }
  // on the row of the text: under the box's top edge, or the label
  final above = outlined || label != null ? 1 : 0;
  return Row(
    gap: 1,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(top: above),
        child: DefaultTextStyle(style: iconStyle, child: icon),
      ),
      Expanded(child: column),
    ],
  );
}
