/// Toasts: short messages [showToast] puts over the app for a while, in
/// turn.
library;

import 'dart:async';

import 'package:twk_core/twk_core.dart'
    show
        Alignment,
        BoxConstraints,
        CrossAxisAlignment,
        EdgeInsets,
        MainAxisSize,
        PaintContext,
        RenderObject,
        StackFit;

import '../animation/animation_controller.dart';
import '../animation/curves.dart';
import '../animation/switcher.dart' show FractionalTranslation, Opacity;
import '../animation/ticker.dart';
import '../foundation/change_notifier.dart';
import '../foundation/listenable_builder.dart';
import '../framework/framework.dart';
import '../layout/basic.dart';
import '../layout/box.dart';
import '../layout/flex.dart';
import '../layout/shadow.dart';
import '../layout/stack.dart';
import '../style/style.dart';
import '../text/widgets.dart';
import 'layer.dart';
import 'panel.dart';

// Examples can assume:
// late BuildContext context;

/// Shows [message] in a toast of the [Overlay] above [context] (a
/// [StateError] that says where to place one if there is none) for
/// [duration], three seconds by default, then takes it away.
///
/// The toasts of an overlay are shown in the order they came, at most three
/// at a time: the others wait in a queue, and each is shown, its
/// [duration] running from then, once one of those shown is gone. They
/// stand one under another, a cell in from the edges of the overlay, where
/// [alignment] puts them (the bottom right by default), in an entry of
/// their own, put over the overlay's others as the first of them is shown.
///
/// Each is a raised panel ([look]): the theme's surface, a bar `▌` down its
/// left edge and an icon before the message in the color of [style] (the
/// kind it is: [icon], or by default `✓` for the theme's success, `ℹ` its
/// info, `⚠` its warning and `✗` its error, none for another style), the
/// message in the theme's text, a row of room above and below it, and the
/// theme's panel shadow, which leaves a row between two toasts. It slides
/// in from the edge it stands by (the bottom for one centred at the
/// bottom, the top for one centred at the top) over 200 ms, easing out,
/// and fades into what is under it, its shadow with it, over the last
/// 260 ms of its time. With [look] [PanelLook.bordered]: a box of the
/// theme's surface with a border, the text in [style] merged onto the
/// theme's text, shown and taken away at once.
///
/// A toast of the theme's success, `✓` before its message, at the top
/// right for five seconds:
///
/// ```dart
/// showToast(
///   context,
///   'Saved notes.md',
///   style: Theme.of(context).success,
///   alignment: Alignment.topRight,
///   duration: const Duration(seconds: 5),
/// );
/// ```
void showToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
  Alignment alignment = Alignment.bottomRight,
  Style? style,
  String? icon,
  PanelLook look = PanelLook.raised,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) {
    throw StateError(
      'showToast: no Overlay above ${context.widget.runtimeType}: place '
      'an Overlay above it, as around the whole app: Overlay(child: …)',
    );
  }
  (_toasts[overlay] ??= _Toasts(overlay)).add(
    _Toast(message, duration, alignment, style, icon, look),
  );
}

/// How long a toast takes to slide in.
const _slideIn = Duration(milliseconds: 200);

/// How long a toast takes to fade out, at the end of its time.
const _fadeOut = Duration(milliseconds: 260);

/// How many toasts of an overlay are shown at a time.
const _maxShown = 3;

/// The toasts of each overlay with any.
final _toasts = Expando<_Toasts>();

final class _Toast {
  _Toast(
    this.message,
    this.duration,
    this.alignment,
    this.style,
    this.icon,
    this.look,
  );

  final String message;
  final Duration duration;
  final Alignment alignment;
  final Style? style;
  final String? icon;
  final PanelLook look;

  // runs while it is shown
  Timer? timer;
}

/// The toasts of [overlay], shown and waiting, in the order they came, and
/// the entry that shows them while there are any.
final class _Toasts {
  _Toasts(this.overlay);

  final OverlayState overlay;
  final _queue = <_Toast>[];
  OverlayEntry? _entry;

  /// The toasts shown.
  Iterable<_Toast> get shown => _queue.take(_maxShown);

  void add(_Toast toast) {
    _queue.add(toast);
    _update();
  }

  /// Starts the time of the toasts shown that have none running, and
  /// shows them: in the entry, put over the others when there was none.
  void _update() {
    for (final toast in shown) {
      toast.timer ??= Timer(toast.duration, () => _expire(toast));
    }
    final entry = _entry;
    if (entry == null) {
      overlay.insert(
        _entry = OverlayEntry(
          builder: (_) => _ToastLayer(this),
          fadeIn: Duration.zero,
          fadeOut: Duration.zero,
        ),
      );
    } else {
      entry.markNeedsBuild();
    }
  }

  void _expire(_Toast toast) {
    _queue.remove(toast);
    if (_queue.isEmpty) {
      _end();
    } else {
      _update();
    }
  }

  /// Takes the toasts away, and the entry; their time stops.
  void _end() {
    for (final toast in _queue) {
      toast.timer?.cancel();
    }
    _queue.clear();
    _entry?.remove();
    _entry = null;
    if (identical(_toasts[overlay], this)) {
      _toasts[overlay] = null;
    }
  }
}

/// The toasts shown, grouped by where they stand.
final class _ToastLayer extends StatefulWidget {
  const _ToastLayer(this.toasts);

  final _Toasts toasts;

  @override
  State<_ToastLayer> createState() => _ToastLayerState();
}

final class _ToastLayerState extends State<_ToastLayer> {
  @override
  void dispose() {
    // gone with the last toast, or with the overlay: their time stops
    widget.toasts._end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <Alignment, List<_Toast>>{};
    for (final toast in widget.toasts.shown) {
      (groups[toast.alignment] ??= []).add(toast);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final MapEntry(key: alignment, value: toasts) in groups.entries)
          Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: switch (alignment.x) {
                  < 0 => CrossAxisAlignment.start,
                  > 0 => CrossAxisAlignment.end,
                  _ => CrossAxisAlignment.center,
                },
                children: [
                  for (final toast in toasts)
                    if (toast.look == PanelLook.bordered)
                      Box(
                        key: ObjectKey(toast),
                        style: theme.surface.merge(theme.text),
                        border: Border.all(style: theme.border),
                        padding: const EdgeInsets.x(1),
                        child: Text(
                          toast.message,
                          style: toast.style ?? const Style(),
                        ),
                      )
                    else
                      _RaisedToast(toast, key: ObjectKey(toast)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A raised toast, sliding in and fading out.
final class _RaisedToast extends StatefulWidget {
  const _RaisedToast(this.toast, {super.key});

  final _Toast toast;

  @override
  State<_RaisedToast> createState() => _RaisedToastState();
}

final class _RaisedToastState extends State<_RaisedToast>
    with TickerProviderStateMixin<_RaisedToast> {
  late final _in = AnimationController(vsync: this, duration: _slideIn)
    ..forward();
  late final _out = AnimationController(vsync: this, duration: _fadeOut);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final wait = widget.toast.duration - _fadeOut;
    if (wait > Duration.zero) {
      _timer = Timer(wait, _out.forward);
    } else {
      _out.forward();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    _out.dispose();
    super.dispose();
  }

  /// The icon of a toast in [style]: the kind of the theme's status style
  /// it is, by its text color.
  static String? _iconOf(ThemeData theme, Style? style) {
    final fg = style?.fg;
    if (fg == null) {
      return null;
    }
    return switch (fg) {
      _ when fg == theme.success.fg => '✓',
      _ when fg == theme.info.fg => 'ℹ',
      _ when fg == theme.warning.fg => '⚠',
      _ when fg == theme.error.fg => '✗',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toast = widget.toast;
    final kind = Style(fg: toast.style?.fg ?? theme.primary.fg);
    final icon = toast.icon ?? _iconOf(theme, toast.style);
    final box = Box(
      style: theme.surface.merge(theme.text),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Edge(style: kind),
            Padding(
              padding: const EdgeInsets.only(
                left: 1,
                top: 1,
                right: 2,
                bottom: 1,
              ),
              child: Text.rich([
                if (icon != null) Span('$icon ', kind),
                Span(toast.message, theme.text),
              ]),
            ),
          ],
        ),
      ),
    );
    final a = toast.alignment;
    return ListenableBuilder(
      listenable: Listenable.merge([_in, _out]),
      builder: (context, child) {
        final shift = 1 - Curves.easeOut.transform(_in.value);
        return FractionalTranslation(
          x: a.y == 0 || a.x != 0 ? shift * (a.x < 0 ? -1.2 : 1.2) : 0,
          y: a.y != 0 && a.x == 0 ? shift * (a.y < 0 ? -1 : 1) : 0,
          child: Opacity(
            opacity: 1 - Curves.easeInOut.transform(_out.value),
            child: child,
          ),
        );
      },
      child: Shadow(shadow: Panel.shadowOf(theme), child: box),
    );
  }
}

/// A column of `▌` down the height it gets, in [style]: a toast's bar.
final class _Edge extends LeafRenderObjectWidget {
  const _Edge({required this.style});

  final Style style;

  @override
  _RenderEdge createRenderObject(BuildContext context) => _RenderEdge(style);

  @override
  void updateRenderObject(BuildContext context, _RenderEdge renderObject) =>
      renderObject.style = style;
}

final class _RenderEdge extends RenderObject {
  _RenderEdge(this._style);

  Style _style;
  Style get style => _style;
  set style(Style s) {
    if (s != _style) {
      _style = s;
      markNeedsPaint();
    }
  }

  @override
  int computeMinIntrinsicWidth(int height) => 1;

  @override
  int computeMaxIntrinsicWidth(int height) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(1);
    height = c.constrainH(0);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    final pen = _style.penIn(canvas.styles);
    for (var y = 0; y < height; y++) {
      canvas.text(0, y, '▌', pen);
    }
  }
}
