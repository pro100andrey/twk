// The toasts at the bottom right, sliding in and fading out.
part of 'shell.dart';

extension _ToastLayer on GalleryShellState {
  Widget? _toastLayer(Tokens t, int sw, int sh) {
    final now = _motion.now;
    if (!_clock.frozen) {
      _toasts.expire(now);
    }
    if (_toasts.isEmpty) {
      return null;
    }
    // where each goes, the newest lowest
    final placed = <({Toast toast, int x, int y, int w, double out})>[];
    var bottom = sh - 2;
    var top = bottom;
    var left = sw;
    for (final toast in _toasts.list.reversed) {
      final age = _clock.frozen ? 400 : (now - toast.at).inMilliseconds;
      final kin = easeOut((age / toastInMs).clamp(0, 1).toDouble());
      final kout = ((age - (toastMs - toastOutMs)) / toastOutMs)
          .clamp(0, 1)
          .toDouble();
      if (age < toastInMs || kout > 0) {
        _motion.animate();
      }
      final w = widthOf(toast.message) + 8;
      final x = sw - 2 - w + ((1 - kin) * (w + 2)).round();
      final y = bottom - 3 + 1;
      placed.add((toast: toast, x: x, y: y, w: w, out: kout));
      if (x < left) {
        left = x;
      }
      top = y;
      bottom -= 4;
    }
    if (!_clock.frozen) {
      _motion.wakeAt(_toasts.nextEnd!);
    }
    if (left < 0) {
      left = 0;
    }
    final height = sh - 1 - top;
    return Positioned(
      left: left,
      top: top,
      width: sw - left,
      height: height < 0 ? 0 : height,
      child: CellPaint(hit: false, (p) {
        for (final it in placed) {
          final color = t.named(it.toast.kind.name);
          final x = it.x - left;
          final y = it.y - top;
          p.fill(x, y, it.w, 3, Style(bg: t.surface));
          for (var r = 0; r < 3; r++) {
            p.text(x, y + r, '▌', Style(fg: color));
          }
          p
            ..text(x + 3, y + 1, _icons[it.toast.kind]!, Style(fg: color))
            ..text(x + 5, y + 1, it.toast.message, Style(fg: t.text));
          if (it.out > 0) {
            p.tint(x, y, it.w, 3, t.background, easeInOut(it.out));
          }
        }
      }),
    );
  }
}

const Map<ToastKind, String> _icons = {
  ToastKind.info: 'ℹ',
  ToastKind.success: '✓',
  ToastKind.warning: '⚠',
  ToastKind.error: '✗',
};
