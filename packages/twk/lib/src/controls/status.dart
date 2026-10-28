/// What a message is about, shown by its color and icon: [StatusKind],
/// [StatusMessage] and [Badge].
library;

import 'package:twk_core/twk_core.dart'
    show Attr, CrossAxisAlignment, MainAxisSize, TextWrap;

import '../framework/framework.dart';
import '../layout/flex.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// What a [StatusMessage] or a [Badge] tells: each kind has its [icon] and
/// its color in the theme ([styleIn]).
enum StatusKind {
  /// Information, neither good nor bad: `ℹ`, [ThemeData.info].
  info('ℹ'),

  /// What succeeded: `✓`, [ThemeData.success].
  success('✓'),

  /// A warning: `⚠`, [ThemeData.warning].
  warning('⚠'),

  /// An error, what failed: `✗`, [ThemeData.error].
  error('✗');

  const StatusKind(this.icon);

  /// The sign of this kind, one column wide.
  final String icon;

  /// The color of this kind in [theme].
  Style styleIn(ThemeData theme) => switch (this) {
    info => theme.info,
    success => theme.success,
    warning => theme.warning,
    error => theme.error,
  };
}

/// A [message] of a [kind] after the kind's [StatusKind.icon] in its
/// color: `✓ Saved 3 files`.
///
/// With a [title], the title follows the icon, in bold and the kind's
/// color, and the message goes below it. The message wraps under itself,
/// the icon's column left blank; the widget is as wide as its text, within
/// its constraints.
///
/// The styles, each merged over those before it: the theme's text and
/// [style] for the message; the kind's color in bold and [iconStyle] for
/// the icon and the title.
///
/// ```dart
/// const Column(
///   children: [
///     StatusMessage('Saved 3 files', kind: StatusKind.success),
///     StatusMessage(
///       'The disk is 95 % full.',
///       kind: StatusKind.warning,
///       title: 'Low on space',
///     ),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [Badge], a short label in the kind's color.
final class StatusMessage extends StatelessWidget {
  /// A [message] of [kind], information by default.
  const StatusMessage(
    this.message, {
    super.key,
    this.kind = StatusKind.info,
    this.title,
    this.icon,
    this.style,
    this.iconStyle,
  });

  /// What it says.
  final String message;

  /// What it is about: its icon and color; [StatusKind.info] by default.
  final StatusKind kind;

  /// A line above the message; null for none.
  final String? title;

  /// In place of the kind's icon; one column wide, as it is.
  final String? icon;

  /// The message, over the theme's text.
  final Style? style;

  /// The icon and the title, over the kind's color in bold.
  final Style? iconStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marked = kind
        .styleIn(theme)
        .merge(const Style(attrs: Attr.bold))
        .merge(iconStyle ?? const Style());
    final text = Text(message, style: theme.text.merge(style ?? const Style()));
    final title = this.title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        Text(icon ?? kind.icon, style: marked, wrap: TextWrap.none),
        Flexible(
          child: title == null
              ? text
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: marked),
                    text,
                  ],
                ),
        ),
      ],
    );
  }
}

/// A short [label] set off by its color: a count, a state; ` 3 `, ` new `.
///
/// The label has a blank on either side, on one row, in [style] over the
/// [kind]'s color reversed and bold: the theme's [ThemeData.primary]
/// without a kind.
///
/// ```dart
/// const Row(
///   children: [
///     Text('Inbox '),
///     Badge('3'),
///     Text(' Build '),
///     Badge('failed', kind: StatusKind.error),
///   ],
/// )
/// ```
final class Badge extends StatelessWidget {
  /// A badge of [label], in the color of [kind] or the primary one.
  const Badge(this.label, {super.key, this.kind, this.style});

  /// What it shows.
  final String label;

  /// Whose color the badge is; null for the primary color.
  final StatusKind? kind;

  /// Over the color filled ([ThemeData.fill]) and bold.
  final Style? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      ' $label ',
      style: theme
          .fill((kind?.styleIn(theme) ?? theme.primary).fg)
          .merge(const Style(attrs: Attr.bold))
          .merge(style ?? const Style()),
      wrap: TextWrap.none,
      maxLines: 1,
    );
  }
}
