// What the gallery keeps of each page while it runs: the raw values of its
// options, its own state (PageControl.state), and the control its widget
// reaches the gallery by.
import '../page.dart';

/// The options and the state of each page, by the page's key
/// (`controls/button`): what the inspector and a route set, what a page
/// keeps from visit to visit, and what "Reset the options" empties.
///
/// Every change goes through [update], so that the gallery builds again;
/// a page's toasts go to [toast].
final class PageStore {
  PageStore({required this.update, required this.toast});

  /// Makes a change and builds the gallery again: a State's `setState`.
  final void Function(void Function() change) update;

  /// Shows a toast for a page.
  final void Function(String message, ToastKind kind) toast;

  final _raw = <String, Map<String, Object>>{};
  final _states = <String, Map<String, Object?>>{};
  final _controls = <String, PageControl>{};
  final _resets = <String, int>{};

  /// The raw values of the options of page [key] that a route or the
  /// inspector set, by option; those not set start where they say.
  Map<String, Object> rawOf(String key) => _raw[key] ??= {};

  /// The options of [page], whose key is [key], as they are.
  Options optionsOf(String key, GalleryPage page) =>
      Options(page, rawOf(key), pageState: stateOf(key));

  /// Sets option [option] of page [key] to [raw].
  void set(String key, PageOption<Object?> option, Object raw) =>
      update(() => rawOf(key)[option.key] = raw);

  /// The state of page [key] ([PageControl.state]).
  Map<String, Object?> stateOf(String key) => _states[key] ??= {};

  /// How often page [key] was reset: a key of its widget, so that a reset
  /// builds it afresh.
  int resetsOf(String key) => _resets[key] ?? 0;

  /// Puts page [key]'s options back where they start and empties its
  /// state.
  void reset(String key) => update(() {
    _raw.remove(key);
    _states.remove(key);
    _resets[key] = resetsOf(key) + 1;
  });

  /// The control of [page], whose key is [key], for its widget.
  PageControl controlOf(String key, GalleryPage? page) =>
      _controls[key] ??= _Control(this, key, page);
}

/// What a page's widget asks of the gallery, through the store.
final class _Control implements PageControl {
  _Control(this._store, this._key, this._page);

  final PageStore _store;
  final String _key;
  final GalleryPage? _page;

  @override
  Map<String, Object?> get state => _store.stateOf(_key);

  @override
  void setOption<T>(PageOption<T> option, T value) {
    // the page's own option of its key says what raw value [value] is
    final own = _page?.options.where((o) => o.key == option.key).firstOrNull;
    final raw = own?.rawOf(value);
    if (own == null || raw == null) {
      return;
    }
    if (_store.rawOf(_key)[own.key] != raw) {
      _store.set(_key, own, raw);
    }
  }

  @override
  void toast(String message, [ToastKind kind = ToastKind.info]) =>
      _store.toast(message, kind);
}
