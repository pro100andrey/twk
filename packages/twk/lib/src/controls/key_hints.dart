/// What can be pressed now: [KeyHintsBar].
library;

import 'package:twk_core/twk_core.dart' show Attr, KeyCode;

import '../binding/app_binding.dart' show AppBinding;
import '../focus/focus.dart';
import '../framework/framework.dart';
import '../gestures/gesture_detector.dart';
import '../layout/basic.dart' show SizedBox;
import '../layout/flex.dart';
import '../overlay/dialog.dart';
import '../style/style.dart';
import '../text/hit_row.dart' show HitRow, HitSpan, segmenterOf;
import '../text/widgets.dart';

// Examples can assume:
// late BuildContext context;

/// A row of the keys that can be pressed now, each before its hint:
/// `ctrl+s save   q quit`.
///
/// The keys are those of the `KeyBindings` and `Shortcuts` on the key
/// path, the nearest layer's first, a key bound to null or to an intent
/// no enabled action does left to the layers above
/// ([FocusManagerKeys.activeKeys]); the bar follows them as the focus
/// moves and the layers change ([FocusManager.keysChanged]). The keys a
/// focused node takes in its own `onKeyEvent` are not among them. Keys
/// bound during the layout, by a `KeyBindings` a `LayoutBuilder` builds,
/// reach the bar in the frame after, which is asked for at once: a frame
/// builds before it lays out, as Flutter's does.
///
/// A sequence shows whole ([ActiveKey.label]): `ctrl+x ctrl+s save`; while
/// a layer holds its first keys, what can follow them: `ctrl+s save` once
/// Ctrl+X is pressed. Keys without a hint are left out, unless
/// [showUnhinted]. [keyLabel] names each key, by default as
/// [KeyHintsBar.signs] does: `ctrl+s`, the arrows and Escape by their
/// signs (`↑`, `esc`), Page Up and Down short (`pgup`). With [joinKeys],
/// keys of one family that share a hint show as one where the first of
/// them is, each without modifiers: the arrows together (`↑↓ move`), Page
/// Up and Down, Home and End apart by a blank (`pgup pgdn a page`).
/// [separator], three blanks by default, is between two keys. One row,
/// cut off with "…" when it does not fit.
///
/// The styles, each merged over those before it: [style] for the row, over
/// the theme's text; [keyStyle] for a key, [hintStyle] for a hint. One
/// left null is the theme's: [ThemeData.text] in bold and
/// [ThemeData.muted]. `keyStyle: theme.primary.merge(const Style(attrs:
/// Attr.bold))`, `separator: '  '`, `keyLabel: (c) => '$c'` and
/// `joinKeys: false` give a plain look: the keys in the primary color by
/// their names, each apart. Outside an app the row is empty.
///
/// A screen whose last row tells what its keys do:
///
/// ```dart
/// KeyBindings(
///   {'ctrl+s': () => print('saved'), 'q': () => print('bye')},
///   hints: const {'ctrl+s': 'save', 'q': 'quit'},
///   child: const Focus(
///     autofocus: true,
///     child: Column(
///       children: [
///         Expanded(child: Text('editor')),
///         KeyHintsBar(),
///       ],
///     ),
///   ),
/// )
/// ```
///
/// Something pinned at the right of the row is the row's neighbour, the bar
/// cut before it reaches it:
///
/// ```dart
/// Row(
///   children: [
///     const Expanded(child: KeyHintsBar()),
///     Button('? keys', onPressed: () => showKeyHelp(context)),
///   ],
/// )
/// ```
///
/// See also:
///
///  * [FocusManagerKeys.activeKeys], the keys it shows.
///  * [KeyHintsBar.entries], what it shows of them, for a bar drawn
///    otherwise.
///  * `StatusBar`, a row of the app's own text.
final class KeyHintsBar extends StatefulWidget {
  /// A row of the keys of the key path and their hints.
  const KeyHintsBar({
    super.key,
    this.showUnhinted = false,
    this.keyLabel,
    this.joinKeys = true,
    this.separator = '   ',
    this.style,
    this.keyStyle,
    this.hintStyle,
    this.pressable = false,
  }) : _pairs = null;

  /// A row of the keys [pairs] name, each before its hint, whatever keys
  /// are in force: for hints the app words itself, as they change with its
  /// state (`enter  open   d  delete`). Each pair is a key's name, read as
  /// [KeyCombo.parseSequence] reads those of a `KeyBindings` (`ctrl+s`,
  /// `g g`; one it cannot read is an error as the bar is built), and its
  /// hint. The row is drawn, joined, cut and styled as the bar of the keys
  /// in force is, and with [pressable] a click presses the key through
  /// [AppBinding.pressKey] the same, whether or not anything binds it. A
  /// pair whose hint is empty shows its key alone.
  /// The hints of a list that picks the keys by its state:
  ///
  /// ```dart
  /// KeyHintsBar.fromPairs(const [
  ///   ('enter', 'open'),
  ///   ('d', 'delete'),
  ///   ('esc', 'close'),
  /// ])
  /// ```
  const KeyHintsBar.fromPairs(
    List<(String, String)> pairs, {
    super.key,
    this.keyLabel,
    this.joinKeys = true,
    this.separator = '   ',
    this.style,
    this.keyStyle,
    this.hintStyle,
    this.pressable = false,
  }) : _pairs = pairs,
       showUnhinted = true;

  /// The fixed pairs of [KeyHintsBar.fromPairs]; null for the keys in force.
  final List<(String, String)>? _pairs;

  /// Whether a click on a key presses it ([AppBinding.pressKey]; a sequence
  /// key by key), and one on a hint presses its key where it has one key
  /// alone (not `↑↓ move`, whose keys are pressed each on its sign). False
  /// by default: the bar then listens to no mouse, and the terminal
  /// reports none for it.
  final bool pressable;

  /// Whether keys without a hint are shown, by their names alone.
  final bool showUnhinted;

  /// How a key is named, those of a sequence one by one; null for
  /// [signs].
  final String Function(KeyCombo combo)? keyLabel;

  /// Whether keys of one family that share a hint show as one: the
  /// arrows, Page Up and Down, Home and End.
  final bool joinKeys;

  /// [combo] as a hint names it: the arrows and Escape by their signs,
  /// Page Up and Down short, after the modifiers too (`alt+↓`, `esc`,
  /// `pgdn`); any other key as [KeyCombo.toString] does (`ctrl+s`). The
  /// arrows are [glyphs]' ([Glyphs.arrowLeft] and the rest).
  static String signs(KeyCombo combo, {Glyphs glyphs = Glyphs.unicode}) {
    final sign = switch (combo.code) {
      KeyCode.escape => 'esc',
      KeyCode.left => glyphs.arrowLeft,
      KeyCode.right => glyphs.arrowRight,
      KeyCode.up => glyphs.arrowUp,
      KeyCode.down => glyphs.arrowDown,
      KeyCode.pageUp => 'pgup',
      KeyCode.pageDown => 'pgdn',
      _ => null,
    };
    final name = '$combo';
    return sign == null
        ? name
        : name.substring(0, name.length - combo.code.name.length) + sign;
  }

  /// The entries a bar shows for [keys], in their order: each the keys it
  /// names, as [ActiveKey.label] names them by [keyLabel] ([signs] when
  /// null), and their hint.
  ///
  /// Keys without a hint are left out, unless [showUnhinted]; a key
  /// listed already with its hint is not listed again. With [joinKeys],
  /// keys of one family that share a hint are one entry where the first
  /// of them is, each without modifiers: the arrows together (`↑↓`) where
  /// each is named by one character, Page Up and Down, Home and End apart
  /// by a blank (`pgup pgdn`). A sequence is an entry of its own (`g g`).
  /// What a bar of the app's own lists, as a [KeyHintsBar] would:
  ///
  /// ```dart
  /// void move() {}
  /// final keys = [
  ///   ActiveKey(KeyCombo.parse('up'), binding: move, hint: 'move'),
  ///   ActiveKey(KeyCombo.parse('down'), binding: move, hint: 'move'),
  ///   ActiveKey(KeyCombo.parse('escape'), binding: move, hint: 'close'),
  ///   ActiveKey(KeyCombo.parse('f2'), binding: move),
  /// ];
  /// print(KeyHintsBar.entries(keys)); // [(↑↓, move), (esc, close)]
  /// ```
  static List<(String, String?)> entries(
    Iterable<ActiveKey> keys, {
    String Function(KeyCombo combo)? keyLabel,
    bool joinKeys = true,
    bool showUnhinted = false,
    Glyphs glyphs = Glyphs.unicode,
  }) => [
    for (final (names, gap, hint) in _entries(
      keys,
      glyphs,
      keyLabel: keyLabel,
      joinKeys: joinKeys,
      showUnhinted: showUnhinted,
    ))
      ([for (final (name, _) in names) name].join(gap), hint),
  ];

  /// [entries], each with the keys it names, apart by what is between
  /// their names.
  static List<(List<(String, ActiveKey)>, String, String?)> _entries(
    Iterable<ActiveKey> keys,
    Glyphs glyphs, {
    String Function(KeyCombo combo)? keyLabel,
    bool joinKeys = true,
    bool showUnhinted = false,
  }) {
    final label = keyLabel ?? (KeyCombo combo) => signs(combo, glyphs: glyphs);
    // each entry: the names of the keys it shows, their family, its hint
    final shown = <(List<(String, ActiveKey)>, int?, String?)>[];
    for (final key in keys) {
      final hint = key.hint;
      if (hint == null && !showUnhinted) {
        continue;
      }
      final name = key.label(label);
      if (shown.any((e) => e.$3 == hint && e.$1.any((n) => n.$1 == name))) {
        continue;
      }
      final family = joinKeys && hint != null && key.then.isEmpty
          ? _familyOf(key.combo)
          : null;
      final joined = family == null
          ? null
          : shown.where((e) => e.$2 == family && e.$3 == hint).firstOrNull;
      if (joined != null) {
        joined.$1.add((name, key));
      } else {
        shown.add(([(name, key)], family, hint));
      }
    }
    return [
      for (final (names, family, hint) in shown)
        // the arrows' signs together, other keys apart by a blank
        (
          names,
          family == 0 && names.every((n) => n.$1.length == 1) ? '' : ' ',
          hint,
        ),
    ];
  }

  /// What is between two keys.
  final String separator;

  /// The row, the theme's text under it.
  final Style? style;

  /// A key; [ThemeData.text] in bold when null.
  final Style? keyStyle;

  /// A hint; [ThemeData.muted] when null.
  final Style? hintStyle;

  @override
  State<KeyHintsBar> createState() => _KeyHintsBarState();
}

/// The families of keys a hint bar joins: the arrows, Page Up and Down,
/// Home and End.
const List<Set<KeyCode>> _families = [
  {KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down},
  {KeyCode.pageUp, KeyCode.pageDown},
  {KeyCode.home, KeyCode.end},
];

/// The index in [_families] of [combo]'s family; null for a key of none,
/// or one with modifiers.
int? _familyOf(KeyCombo combo) {
  if (combo.modifiers != 0) {
    return null;
  }
  final i = _families.indexWhere((f) => f.contains(combo.code));
  return i < 0 ? null : i;
}

/// The keys [pairs] name, as a bar of the keys in force lists them.
List<ActiveKey> _fixedKeys(List<(String, String)> pairs) => [
  for (final (name, hint) in pairs)
    if (KeyCombo.parseSequence(name) case [final first, ...final rest])
      ActiveKey(
        first,
        binding: name,
        hint: hint.isEmpty ? null : hint,
        then: rest,
      ),
];

final class _KeyHintsBarState extends State<KeyHintsBar> {
  FocusManager? _manager;
  final _hits = HitRow();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = Focus.maybeOf(context, createDependency: false)?.manager;
    if (!identical(manager, _manager)) {
      _manager?.keysChanged.removeListener(_changed);
      _manager = manager?..keysChanged.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _manager?.keysChanged.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyStyle =
        widget.keyStyle ?? theme.text.merge(const Style(attrs: Attr.bold));
    final hintStyle = widget.hintStyle ?? theme.muted;
    final spans = <HitSpan>[];
    // the keys a click presses, by target
    final keys = <ActiveKey>[];
    final pairs = widget._pairs;
    for (final (names, gap, hint) in KeyHintsBar._entries(
      pairs == null
          ? _manager?.activeKeys ?? const <ActiveKey>[]
          : _fixedKeys(pairs),
      _fitArrows(context, theme.glyphs),
      keyLabel: widget.keyLabel,
      joinKeys: widget.joinKeys,
      showUnhinted: widget.showUnhinted,
    )) {
      if (spans.isNotEmpty) {
        spans.add((span: Span(widget.separator), target: -1));
      }
      for (final (i, (name, key)) in names.indexed) {
        if (i > 0) {
          spans.add((span: Span(gap, keyStyle), target: -1));
        }
        spans.add((span: Span(name, keyStyle), target: keys.length));
        keys.add(key);
      }
      if (hint != null) {
        spans
          ..add((span: Span(' ', hintStyle), target: -1))
          // the hint of one key presses it
          ..add((
            span: Span(hint, hintStyle),
            target: names.length == 1 ? keys.length - 1 : -1,
          ));
      }
    }
    final row = _hits.row(
      spans,
      style: theme.text.merge(widget.style ?? const Style()),
      overflow: TextOverflow.ellipsis,
    );
    if (!widget.pressable) {
      return row;
    }
    // the hand over a key or a hint that presses a key; the ellipsis of a
    // cut row presses nothing, nor does the key or hint it stands for
    return GestureDetector(
      tapAt: (x, _) => _hits.at(x) >= 0,
      onTapDown: (tap) {
        final key = keys[_hits.at(tap.localPosition.dx)];
        final binding = AppBinding.of(context);
        for (final combo in [key.combo, ...key.then]) {
          binding.pressKey(combo);
        }
      },
      child: row,
    );
  }
}

/// Shows the keys in force where [context] is, with their hints, in a
/// dialog titled [title]: the keys a [KeyHintsBar] would show there, one a
/// line, as [KeyHintsBar.entries] makes them, the nearest layer's first
/// ([ActiveKey.layer]), a blank line between the layers, the key in bold
/// and its hint after it. A key without a hint is not listed. After them
/// come [extra], what no binding in force tells, as pairs of what is done
/// and what it does, in that order: a key a widget takes itself (Tab
/// moving the focus), the mouse (`'right click'`), each listed as a key is.
/// The last layer, apart from the others, is the dialog's own:
/// `esc  close`, which closes it. It comes last because the dialog is
/// about the screen's keys, and Escape is the footnote to them, as the
/// bar's keys are; it is there with no hinted key in force too. A list
/// taller than the screen scrolls. The keys are those in force as it is
/// called, before the dialog takes the focus; Escape or a click outside
/// closes it.
///
/// A help key that shows what the screen's keys do:
///
/// ```dart
/// KeyBindings(
///   {'ctrl+s': () {}, '?': () => showKeyHelp(context)},
///   hints: const {'ctrl+s': 'save', '?': 'help'},
///   child: const Focus(autofocus: true, child: Text('editor')),
/// )
/// ```
///
/// The same, with what the mouse does:
///
/// ```dart
/// showKeyHelp(
///   context,
///   extra: const [('click', 'select'), ('right click', 'menu')],
/// );
/// ```
Future<void> showKeyHelp(
  BuildContext context, {
  String title = 'Keys',
  List<(String, String)> extra = const [],
}) {
  final glyphs = _fitArrows(context, Theme.of(context).glyphs);
  final active = AppBinding.of(context).focusManager.activeKeys;
  final byLayer = <int, List<ActiveKey>>{};
  for (final key in active) {
    (byLayer[key.layer] ??= []).add(key);
  }
  // the nearest layer first; a layer with nothing to show leaves no gap
  final layers = [
    for (final i in byLayer.keys.toList()..sort())
      KeyHintsBar.entries(byLayer[i]!, glyphs: glyphs),
    extra,
    // the dialog's own binding (Dialog: `escape` with the hint `close`) is
    // not built until the dialog is, so it is named here, as it is there
    [(KeyHintsBar.signs(KeyCombo.parse('escape'), glyphs: glyphs), 'close')],
  ].where((e) => e.isNotEmpty).toList();
  final segmenter = segmenterOf(context);
  var widest = 0;
  for (final entries in layers) {
    for (final (keys, _) in entries) {
      final w = segmenter.width(keys);
      if (w > widest) {
        widest = w;
      }
    }
  }
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return Dialog(
        title: title,
        scrollable: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, entries) in layers.indexed) ...[
              if (i > 0) const SizedBox(height: 1),
              for (final (keys, hint) in entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    SizedBox(
                      width: widest,
                      child: Text(
                        keys,
                        style: theme.text.merge(const Style(attrs: Attr.bold)),
                      ),
                    ),
                    Text(hint ?? '', style: theme.muted),
                  ],
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// [glyphs] with the four arrows a hint names keys by as [ThemeMarks] fits
/// them for [context]: one cell each, else [Glyphs.ascii]'s. [glyphs]
/// itself where they all fit.
Glyphs _fitArrows(BuildContext context, Glyphs glyphs) {
  final marks = ThemeMarks.of(context);
  final left = marks.text(Marks.arrowLeft, glyphs);
  final right = marks.text(Marks.arrowRight, glyphs);
  final up = marks.text(Marks.arrowUp, glyphs);
  final down = marks.text(Marks.arrowDown, glyphs);
  if (left == glyphs.arrowLeft &&
      right == glyphs.arrowRight &&
      up == glyphs.arrowUp &&
      down == glyphs.arrowDown) {
    return glyphs;
  }
  return glyphs.copyWith(
    arrowLeft: left,
    arrowRight: right,
    arrowUp: up,
    arrowDown: down,
  );
}
