/// A row of a list, as Flutter's: [ListTile].
library;

import 'package:twk_core/twk_core.dart' show Attr;

import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'pressable.dart';

/// A row of a list: [title], under it [subtitle], [leading] before them
/// and [trailing] after them, a column apart; tapped, by a click or by
/// Enter or Space while it has the focus, it calls [onTap].
///
/// [title] is in the theme's text, [ThemeData.primary] in bold where
/// [selected], and [subtitle] in [ThemeData.muted]; disabled
/// ([enabled] false), both muted. With [onTap] it takes the focus, which
/// Tab moves to it, and a press of the mouse: the row on
/// [ThemeData.selection] while it has the focus and on [ThemeData.hover]
/// while the mouse is over it. Without one it is a row and nothing more.
///
/// As wide as its constraints, its title and subtitle taking what
/// [leading] and [trailing] leave: in a `Row`, in an `Expanded` or a
/// `SizedBox`, as Flutter's.
///
/// A list of files, the one open selected:
///
/// ```dart
/// Column(
///   children: [
///     ListTile(
///       leading: const Text('▤'),
///       title: const Text('notes.md'),
///       subtitle: const Text('2 KB, an hour ago'),
///       trailing: const Text('›'),
///       selected: true,
///       onTap: () {},
///     ),
///     ListTile(
///       leading: const Text('▤'),
///       title: const Text('todo.md'),
///       onTap: () {},
///     ),
///   ],
/// )
/// ```
///
/// A screen reader reads one with [onTap] as a [SemanticsRole.button],
/// `disabled` while it is.
///
/// See also:
///
///  * `SelectionList`, a list whose rows are chosen, with the keys of one.
///  * `Expansion`, a row that shows more under it when it is opened.
final class ListTile extends StatefulWidget {
  /// A row of [title], and of [leading], [subtitle] and [trailing] where
  /// given, that calls [onTap] when it is tapped.
  const ListTile({
    required this.title,
    super.key,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
  });

  /// What the row is: its first line.
  final Widget title;

  /// Before [title] and [subtitle]: an icon, a mark.
  final Widget? leading;

  /// Under [title], in [ThemeData.muted].
  final Widget? subtitle;

  /// After [title] and [subtitle], at the right end: a count, an arrow.
  final Widget? trailing;

  /// What a tap does; null for a row that takes neither the focus nor the
  /// mouse.
  final VoidCallback? onTap;

  /// Whether it is the one chosen: its title in [ThemeData.primary], bold.
  final bool selected;

  /// Whether it can be tapped; false mutes it.
  final bool enabled;

  /// See [Focus.focusNode].
  final FocusNode? focusNode;

  /// See [Focus.autofocus].
  final bool autofocus;

  @override
  State<ListTile> createState() => _ListTileState();
}

final class _ListTileState extends State<ListTile> {
  var _hovered = false;

  void _hover(bool over) {
    if (over != _hovered) {
      setState(() => _hovered = over);
    }
  }

  @override
  void didUpdateWidget(ListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // without onTap it has no MouseRegion, and would not hear the mouse
    // leave: tappable again, it shows the hover once the mouse enters
    if (widget.onTap == null) {
      _hovered = false;
    }
  }

  bool get _tappable => widget.enabled && widget.onTap != null;

  void _tap() {
    if (_tappable) {
      widget.onTap!();
    }
  }

  Widget _row(BuildContext context, {required bool focused}) {
    final theme = Theme.of(context);
    final enabled = widget.enabled;
    final title = !enabled
        ? theme.muted
        : widget.selected
        ? theme.primary.merge(const Style(attrs: Attr.bold))
        : theme.text;
    final row = focused
        ? focusedRow(theme)
        : _hovered && _tappable
        ? theme.hover
        : const Style();
    final leading = widget.leading;
    final subtitle = widget.subtitle;
    final trailing = widget.trailing;
    return Box(
      style: row,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null)
            Padding(
              padding: const EdgeInsets.only(right: 1),
              child: DefaultTextStyle(
                style: enabled ? theme.text : theme.muted,
                child: leading,
              ),
            ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle(style: title, child: widget.title),
                if (subtitle != null)
                  DefaultTextStyle(style: theme.muted, child: subtitle),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: DefaultTextStyle(style: theme.muted, child: trailing),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return _row(context, focused: false);
    }
    final enabled = widget.enabled;
    // heard while disabled too, so that enabled again it shows the hover
    // only under the mouse; and the tree the same either way, so that the
    // Pressable and its node stay
    return Semantics(
      role: SemanticsRole.button,
      state: SemanticsState(disabled: !enabled),
      child: MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: Pressable(
          enabled: enabled,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          bindings: {'enter': _tap, 'space': _tap},
          hints: const {'enter': 'open'},
          onTap: enabled ? (_) => _tap() : null,
          builder: (context, focused) => _row(context, focused: focused),
        ),
      ),
    );
  }
}
