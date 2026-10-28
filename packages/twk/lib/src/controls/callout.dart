/// A boxed notice of a [StatusKind]: [Callout].
library;

import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        Attr,
        CrossAxisAlignment,
        EdgeInsets,
        MainAxisAlignment,
        MainAxisSize,
        TextWrap;

import '../binding/app_binding.dart';
import '../focus/focus.dart';
import '../foundation/change_notifier.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../gestures/mouse.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../layout/stack.dart';
import '../semantics/semantics.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'status.dart';

/// A notice in a box lined in the color of its [kind]: what a command-line
/// tool prints for "a newer version is available", a hint, a fatal error.
///
/// ```text
/// ┌─ ℹ Info ──────────────[×]─┐
/// │ A newer version is out.   │
/// └───────────────────────────┘
/// ```
///
/// The top edge has the kind's icon ([icon] in its place, a tip's `💡`)
/// and the [title], by default the kind's name (Info, Success, Warning,
/// Error), in the kind's color and bold; the border is in the kind's
/// color, [child] inside it a blank in from either side, in the theme's
/// text. The [actions], buttons, go below the child, at the right. The
/// box is as wide as what it holds, within its constraints, and its text
/// wraps there; it has no width of its own, as a [Box] has none.
///
/// With [onDismissed], `[×]` at the right of the top edge calls it when it
/// is clicked, as Escape does while the focus is in the callout (on one
/// of its [actions]), hinted. The callout does not take itself away: the
/// app builds it no more.
///
/// The styles, each merged over those before it: the theme's text and
/// [style] for the box, its background and the child's text; the kind's
/// color ([StatusKind.styleIn]) for the border, in bold for the title.
///
/// On plain output (`TerminalInfo.plain`: a pipe, a file, CI) there is no
/// box: the icon and the title, then `: ` and the child, which wraps under
/// itself, `ℹ Info: A newer version is out.`; the actions below it, and
/// no `[×]`.
///
/// A screen reader reads a [SemanticsRole.status] of its title, an
/// [SemanticsRole.alert] for a warning or an error, then what is in it as
/// it reads that anywhere.
///
/// A warning to dismiss, and a tip with a button:
///
/// ```dart
/// Column(
///   children: [
///     Callout.text(
///       'The disk is 95 % full.',
///       kind: StatusKind.warning,
///       onDismissed: () => print('dismissed'),
///     ),
///     Callout.text(
///       'Press Ctrl+K to search everything.',
///       title: 'Tip',
///       icon: '💡',
///       actions: [Button('Got it', onPressed: () => print('ok'))],
///     ),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [StatusMessage], a message of a kind on its line, without a box.
///  * `Toast`, a notice that comes and goes over the app.
final class Callout extends StatelessWidget {
  /// A notice of [child] in a box of [kind], information by default.
  const Callout({
    required Widget this._child,
    super.key,
    this.kind = StatusKind.info,
    this.title,
    this.icon,
    this.onDismissed,
    this.actions = const [],
    this.style,
  }) : _message = null;

  /// A notice of a message, a [Text] that wraps, in a box of [kind].
  const Callout.text(
    String this._message, {
    super.key,
    this.kind = StatusKind.info,
    this.title,
    this.icon,
    this.onDismissed,
    this.actions = const [],
    this.style,
  }) : _child = null;

  final Widget? _child;

  final String? _message;

  /// What it says: the child given, or a [Text] of the message given to
  /// [Callout.text].
  Widget get child => _child ?? Text(_message ?? '');

  /// What it is about: the color of its border and title, its icon and
  /// its role; [StatusKind.info] by default.
  final StatusKind kind;

  /// On the top edge after the icon; null for the kind's name, capitalised
  /// (`Warning`).
  final String? title;

  /// In place of the kind's icon ([StatusKind.icon]); an empty one for
  /// none.
  final String? icon;

  /// Called by a click of `[×]` and by Escape while the focus is in the
  /// callout; null for neither and no `[×]`.
  final VoidCallback? onDismissed;

  /// Below the child, at the right, a blank apart: buttons.
  final List<Widget> actions;

  /// The box and the child's text, over the theme's text.
  final Style? style;

  /// The title it shows.
  String get _title {
    final name = kind.name;
    return title ?? '${name[0].toUpperCase()}${name.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colored = kind.styleIn(theme);
    final marked = colored.merge(const Style(attrs: Attr.bold));
    final icon = this.icon ?? kind.icon;
    final head = [if (icon.isNotEmpty) icon, _title].join(' ');
    final plain =
        AppBinding.maybeOf(context)?.twkApp.terminal.info.plain ?? false;
    final text = theme.text.merge(style ?? const Style());
    var body = child;
    if (actions.isNotEmpty) {
      // stretched across the box, which is as wide as it likes
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            gap: 1,
            children: actions,
          ),
        ],
      );
    }
    Widget callout;
    if (plain) {
      callout = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('$head: ', style: marked, wrap: TextWrap.none),
          ),
          Flexible(
            child: DefaultTextStyle(style: text, child: body),
          ),
        ],
      );
      if (actions.isNotEmpty) {
        callout = IntrinsicWidth(child: callout);
      }
    } else {
      final onDismissed = this.onDismissed;
      callout = Box(
        style: text,
        border: Border.all(style: colored),
        titles: [
          BorderTitle('─ $head ─', style: marked),
          if (onDismissed != null)
            const BorderTitle('[×]─', alignment: Alignment.topRight),
        ],
        padding: const EdgeInsets.x(1),
        child: body,
      );
      if (actions.isNotEmpty) {
        callout = IntrinsicWidth(child: callout);
      }
      if (onDismissed != null) {
        callout = KeyBindings(
          {'escape': onDismissed},
          hints: const {'escape': 'dismiss'},
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              callout,
              Positioned(
                top: 0,
                right: 2,
                child: _Dismiss(onDismissed, style: colored),
              ),
            ],
          ),
        );
      }
    }
    // a node of the title before what the child reads as, which a node
    // around it would take in
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned(
          left: 0,
          top: 0,
          width: 0,
          height: 0,
          child: Semantics(
            role: kind == StatusKind.warning || kind == StatusKind.error
                ? SemanticsRole.alert
                : SemanticsRole.status,
            label: _title,
            child: const SizedBox(),
          ),
        ),
        callout,
      ],
    );
  }
}

/// `[×]` on a [Callout]'s top edge in [style], which a click of it
/// dismisses: in the theme's text and bold while the mouse is over it.
final class _Dismiss extends StatefulWidget {
  const _Dismiss(this.onDismissed, {required this.style});

  final VoidCallback onDismissed;

  final Style style;

  @override
  State<_Dismiss> createState() => _DismissState();
}

final class _DismissState extends State<_Dismiss> {
  var _hovered = false;

  void _hover(bool hovered) {
    if (hovered != _hovered) {
      setState(() => _hovered = hovered);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: MouseRegion(
        onEnter: (_) => _hover(true),
        onExit: (_) => _hover(false),
        child: GestureDetector(
          onTap: (_) => widget.onDismissed(),
          child: Text(
            '[×]',
            style: _hovered
                ? widget.style.merge(
                    theme.text.merge(const Style(attrs: Attr.bold)),
                  )
                : widget.style,
            wrap: TextWrap.none,
          ),
        ),
      ),
    );
  }
}
