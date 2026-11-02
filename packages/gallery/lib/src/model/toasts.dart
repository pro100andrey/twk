// The toasts the gallery shows at its bottom right: at most a few, each
// for a while (README.md, "Routes": `toast=`, `kind=`).
import '../page.dart';

/// The toasts shown at once at most; the oldest goes for a new one.
const toastCap = 3;

/// How long a toast shows, in milliseconds.
const toastMs = 2600;

/// A toast: [message] of [kind], shown at [at].
final class Toast {
  Toast(this.message, this.kind, this.at);

  final String message;
  final ToastKind kind;
  final Duration at;
}

/// The toasts showing, the oldest first: [toastCap] at most, each for
/// [toastMs].
final class Toasts {
  final _list = <Toast>[];

  /// The toasts showing, the oldest first.
  List<Toast> get list => List.unmodifiable(_list);

  bool get isEmpty => _list.isEmpty;

  /// Shows [toast]; the oldest goes where that makes more than
  /// [toastCap], unless [capped] is false (a route's, before the first
  /// frame).
  void add(Toast toast, {bool capped = true}) {
    _list.add(toast);
    if (capped && _list.length > toastCap) {
      _list.removeAt(0);
    }
  }

  /// Takes away the toasts shown for [toastMs] by [now].
  void expire(Duration now) =>
      _list.removeWhere((t) => (now - t.at).inMilliseconds >= toastMs);

  /// When the first of them goes; null for none.
  Duration? get nextEnd => _list.isEmpty
      ? null
      : _list.map((t) => t.at).reduce((a, b) => a < b ? a : b) +
            const Duration(milliseconds: toastMs);
}
