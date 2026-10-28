// What a page of the gallery is made of: GalleryPage, its options and
// their values.
import 'package:twk/twk.dart';

/// A page of the gallery: the widget of [title] in [group] (as the
/// catalog names them), live on the stage, its [options] in the
/// inspector, and the Dart that builds it in the Code tab.
///
/// [build] builds the widget with the options as they are; [code] writes
/// the Dart that builds the same, or [codeIn] where the Dart says a size
/// from the stage's room (both null: no Code tab). [stage] says how much
/// room the stage gives it. [about] replaces the catalog's line where
/// given.
final class GalleryPage {
  const GalleryPage({
    required this.group,
    required this.title,
    required this.build,
    this.about,
    this.options = const [],
    this.code,
    this.codeIn,
    this.heightIn,
    this.minWidth,
    this.modalTab = true,
    this.stage = StageSize.child,
    this.terminalAround = false,
    this.codeInTerminalColors = false,
  });

  /// The group the page is in, as the catalog names it: `Controls`.
  final String group;

  /// The page's title, as the catalog names it: `Button`.
  final String title;

  /// What the page is about, instead of the catalog's.
  final String? about;

  /// What the inspector offers, in its order.
  final List<PageOption> options;

  /// The widget, with the options at [options].
  final Widget Function(BuildContext context, Options options) build;

  /// The Dart that builds the widget, with the options at [options].
  final String Function(Options options)? code;

  /// The Dart that builds the widget, with the options at [options], in
  /// [room]: the cells the stage gives the widget, for a widget as tall as
  /// the room lets it be. Used
  /// instead of [code] where given.
  final String Function(Options options, StageRoom room)? codeIn;

  /// Whether the page has a Code tab.
  bool get hasCode => code != null || codeIn != null;

  /// The Dart of the Code tab with the options at [options] in [room]:
  /// [codeIn]'s, else [code]'s; null without a Code tab.
  String? codeOf(Options options, [StageRoom room = StageRoom.unbounded]) =>
      codeIn?.call(options, room) ?? code?.call(options);

  /// The room the stage gives the widget.
  final StageSize stage;

  /// Whether Tab moves the focus in what the page opens over the gallery
  /// (a dialog's buttons), so that the hint bar says `tab next` while it
  /// is open; false where it takes Tab itself or has nowhere to go (a
  /// menu, a command palette).
  final bool modalTab;

  /// The rows the widget takes in `room`, for a widget that fits itself
  /// to its room (a scrolling view, BigText choosing its font): the
  /// options under a narrow stage then take what it leaves of the room
  /// they leave it. Null: its height uncapped (its
  /// intrinsic height), which such a widget would ask for whole.
  final int Function(Options options, StageRoom room)? heightIn;

  /// The columns the widget needs on the stage, where fewer would cut it
  /// (a terminal of 80 columns in its border): where the inspector beside
  /// the stage would leave it fewer, the options go under the stage, as on
  /// a narrow page. Null: beside it wherever the page is wide enough.
  final int? minWidth;

  /// Whether the widget draws a terminal around the app its Code is (a
  /// window, a shell's history, the screen's edge), the app in a
  /// [CodeApp]: only that is the Code's, and while no [CodeApp] shows the
  /// Code's app draws nothing on the stage.
  final bool terminalAround;

  /// Whether the widget shows the Code's app in the terminal's own colors,
  /// as `runApp` gives an app them ([ThemeData.terminal]).
  final bool codeInTerminalColors;
}

/// The part of a page's widget that its Code's app draws, where the rest
/// is the terminal around it ([GalleryPage.terminalAround]).
final class CodeApp extends StatelessWidget {
  const CodeApp({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The cells the stage gives a page's widget: [width] × [height], less
/// its marks around it.
final class StageRoom {
  const StageRoom(this.width, this.height);

  /// As much room as the widget takes: before the stage was laid out, as
  /// a Code reads a room it was not given yet.
  static const unbounded = StageRoom(1 << 20, 1 << 20);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is StageRoom && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'StageRoom($width × $height)';
}

/// How the stage sizes a page's widget.
enum StageSize {
  /// As big as the widget makes itself in the stage's room, which is loose:
  /// a Column says `mainAxisSize: .min`.
  child,

  /// The stage's whole room: a view that takes the room it is given
  /// (MarkdownView, CodeView, TerminalView).
  room,
}

/// A choice in the inspector of how a page shows its widget: [key] names
/// it in a route's `o=` and in [Options]; [label] in the inspector, in
/// lower-case words. [disabled] says when it does not apply, the other
/// options as they are: dim then, and Tab, the keys and the mouse pass it
/// by.
sealed class PageOption {
  const PageOption(this.key, this.label, {this.disabled});

  final String key;
  final String label;
  final bool Function(Options options)? disabled;

  /// The raw value it starts at: an index, a bool or a number.
  Object get initialRaw;

  /// How the inspector's hint bar names its keys.
  List<(String, String)> get hints;

  /// The rows it takes in the inspector, its label above it, [width]
  /// wide.
  int rowsIn(int width);
}

/// One of [values], on a segmented track: named by [labels], or by the
/// values themselves (`none` for null).
final class ChoiceOption extends PageOption {
  const ChoiceOption(
    super.key,
    super.label, {
    required this.values,
    this.labels,
    this.initial,
    super.disabled,
  });

  final List<Object?> values;
  final List<String>? labels;

  /// The value it starts at; the first when null.
  final Object? initial;

  /// The name of each value.
  List<String> get names =>
      labels ??
      [
        for (final v in values)
          if (v == null) 'none' else '$v',
      ];

  @override
  Object get initialRaw {
    final i = values.indexOf(initial);
    return initial == null || i < 0 ? 0 : i;
  }

  @override
  List<(String, String)> get hints => const [
    ('←', 'previous'),
    ('→', 'next'),
  ];

  @override
  int rowsIn(int width) {
    var rows = 1;
    var x = 0;
    for (final name in names) {
      final w = stringWidth(name) + 2;
      if (x > 0 && x + w > width) {
        rows++;
        x = 0;
      }
      x += w;
    }
    return 1 + rows;
  }
}

/// On or off, a pill switch.
final class SwitchOption extends PageOption {
  const SwitchOption(
    super.key,
    super.label, {
    this.initial = false,
    super.disabled,
  });

  final bool initial;

  @override
  Object get initialRaw => initial;

  @override
  List<(String, String)> get hints => const [('space', 'toggle')];

  @override
  int rowsIn(int width) => 1;
}

/// A number from [min] to [max] in steps of [step], on a slider, written
/// by [format] at the right of its label.
final class SliderOption extends PageOption {
  const SliderOption(
    super.key,
    super.label, {
    required this.min,
    required this.max,
    this.step = 1,
    this._initial,
    this.format,
    super.disabled,
  });

  final num min;
  final num max;
  final num step;
  final num? _initial;
  final String Function(num value)? format;

  /// [v] on a step, within the range.
  num clampStep(num v) {
    final n = ((v - min) / step).round() * step + min;
    final c = n < min ? min : (n > max ? max : n);
    return step is int && min is int ? c.round() : c;
  }

  /// [v] as the inspector writes it.
  String show(num v) => format?.call(v) ?? '$v';

  @override
  Object get initialRaw => _initial ?? min;

  @override
  List<(String, String)> get hints => const [
    ('←', 'decrease'),
    ('→', 'increase'),
  ];

  @override
  int rowsIn(int width) => 2;
}

/// One of the theme's colors, by name ([values]: `primary`, `accent`,
/// `success`…), as swatches.
final class ColorOption extends PageOption {
  const ColorOption(
    super.key,
    super.label, {
    required this.values,
    this.initial,
    super.disabled,
  });

  final List<String> values;
  final String? initial;

  @override
  Object get initialRaw {
    final i = values.indexOf(initial ?? values.first);
    return i < 0 ? 0 : i;
  }

  @override
  List<(String, String)> get hints => const [
    ('←', 'previous'),
    ('→', 'next'),
  ];

  @override
  int rowsIn(int width) => 3;
}

/// The values of a page's options, by key: `options['wrap']`, the value;
/// [label], its name; typed: [choice], [flag], [number], [color].
final class Options {
  Options(this.page, Map<String, Object> raw)
    : _raw = {
        for (final o in page.options) o.key: raw[o.key] ?? o.initialRaw,
      };

  /// The options of [page] as they start.
  Options.initial(this.page)
    : _raw = {for (final o in page.options) o.key: o.initialRaw};

  final GalleryPage page;
  final Map<String, Object> _raw;

  PageOption _option(String key) => page.options.firstWhere(
    (o) => o.key == key,
    orElse: () => throw ArgumentError.value(key, 'key', 'no such option'),
  );

  /// The raw value of [key]: an index (choice, color), a bool or a number.
  Object raw(String key) => _raw[key] ?? _option(key).initialRaw;

  /// The value of [key].
  Object? operator [](String key) => switch (_option(key)) {
    final ChoiceOption o => o.values[raw(key) as int],
    final ColorOption o => o.values[raw(key) as int],
    _ => raw(key),
  };

  /// The name of the value of [key], as the inspector and a route write
  /// it.
  String label(String key) => switch (_option(key)) {
    final ChoiceOption o => o.names[raw(key) as int],
    final ColorOption o => o.values[raw(key) as int],
    SliderOption() => _number(raw(key) as num),
    _ => '${raw(key)}',
  };

  static String _number(num v) => v == v.round() ? '${v.round()}' : '$v';

  /// The value of choice [key].
  T choice<T>(String key) => this[key] as T;

  /// The value of switch [key].
  bool flag(String key) => raw(key) as bool;

  /// The value of slider [key].
  num number(String key) => raw(key) as num;

  /// The name of the theme color of color option [key].
  String color(String key) => this[key]! as String;

  /// The theme's style of color option [key].
  Style colorStyle(BuildContext context, String key) =>
      themeColor(Theme.of(context), color(key));

  /// Whether [option] applies with the others as they are.
  bool applies(PageOption option) => !(option.disabled?.call(this) ?? false);

  /// These options with [key] at [raw].
  Options withRaw(String key, Object raw) => Options(page, {..._raw, key: raw});

  /// The options that differ from where they start, as a route's `o=`
  /// writes them: `wrap:none;width:40`.
  String get route => [
    for (final o in page.options)
      if (raw(o.key) != o.initialRaw) '${o.key}:${label(o.key)}',
  ].join(';');

  /// The raw values.
  Map<String, Object> get rawValues => Map.unmodifiable(_raw);

  @override
  bool operator ==(Object other) =>
      other is Options &&
      identical(other.page, page) &&
      _raw.length == other._raw.length &&
      _raw.entries.every((e) => other._raw[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    page,
    Object.hashAllUnordered([
      for (final e in _raw.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// The style of the theme slot named [name] (`primary`, `accent`,
/// `success`, `warning`, `error`, `info`, `text`, `muted`).
Style themeColor(ThemeData theme, String name) => switch (name) {
  'primary' => theme.primary,
  'accent' => theme.accent,
  'success' => theme.success,
  'warning' => theme.warning,
  'error' => theme.error,
  'info' => theme.info,
  'muted' => theme.muted,
  'border' => theme.border,
  _ => theme.text,
};

/// The hints of each [PageHints]'s node.
final _hintsOf = Expando<List<(String, String)>>('page hints');

/// The hints of the [PageHints] nearest above [node], or of [node]'s own;
/// null where there is none.
List<(String, String)>? pageHintsAt(FocusNode? node) {
  for (var n = node; n != null; n = n.parent) {
    if (_hintsOf[n] case final hints?) {
      return hints;
    }
  }
  return null;
}

/// [hints] the gallery's hint bar shows first while the focus is in
/// [child], before the hinted keys of the layers: often no key a layer binds
/// (`type take over`, `wheel scroll back`, `↑↓ scroll` of a view that takes
/// its keys itself). Its node cannot take the focus and Tab passes it by.
final class PageHints extends StatefulWidget {
  const PageHints({required this.hints, required this.child, super.key});

  /// The pairs of the bar, a key or a gesture and what it does.
  final List<(String, String)> hints;

  final Widget child;

  @override
  State<PageHints> createState() => _PageHintsState();
}

final class _PageHintsState extends State<PageHints> {
  final _node = FocusNode(
    debugLabel: 'page hints',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void didUpdateWidget(PageHints oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_same(oldWidget.hints, widget.hints)) {
      // the bar reads them again at the next flush
      _node.markKeysChanged();
    }
  }

  static bool _same(List<(String, String)> a, List<(String, String)> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _hintsOf[_node] = widget.hints;
    return Focus(focusNode: _node, child: widget.child);
  }
}

/// What a page's widget may ask of the gallery around it:
/// `PageControl.of(context)`.
abstract interface class PageControl {
  /// The control of the page [context] is on.
  static PageControl of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageControlScope>()!.control;

  /// Sets option [key] to [value], one of its values (a bool for a
  /// switch, a number for a slider), as its control in the inspector
  /// would: a page that moves its own option (a `cycle` switch). Not
  /// while building: from a callback or a timer.
  void setOption(String key, Object? value);

  /// Shows [message] in a toast of [kind]: `info`, `success`, `warning`,
  /// `error`.
  void toast(String message, [String kind = 'info']);

  /// The page's own state, kept while the gallery runs, as the page leaves
  /// it and comes back: counters, what was chosen. The palette's "Reset
  /// the options" empties it.
  Map<String, Object?> get state;
}

/// Gives the page's widget its [control].
final class PageControlScope extends InheritedWidget {
  const PageControlScope({
    required this.control,
    required super.child,
    super.key,
  });

  final PageControl control;

  @override
  bool updateShouldNotify(PageControlScope oldWidget) =>
      !identical(control, oldWidget.control);
}
