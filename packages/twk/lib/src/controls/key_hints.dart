/// What can be pressed now: [KeyHintsBar].
library;

import 'package:twk_core/twk_core.dart'
    show Attr, KeyCode, TextOverflow, TextWrap;

import '../focus/focus.dart';
import '../framework/framework.dart';
import '../style/style.dart';
import '../text/widgets.dart';

/// A row of the keys that can be pressed now, each before its hint:
/// `ctrl+s save   q quit`.
///
/// The keys are those of the `KeyBindings` and `Shortcuts` on the key
/// path, the nearest layer's first, a key bound to null or to an intent
/// no enabled action does left to the layers above
/// ([FocusManagerKeys.activeKeys]); the bar follows them as the focus
/// moves and the layers change ([FocusManager.keysChanged]). The keys a
/// focused node takes in its own `onKeyEvent` are not among them.
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
  });

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
  /// `pgdn`); any other key as [KeyCombo.toString] does (`ctrl+s`).
  static String signs(KeyCombo combo) {
    final sign = switch (combo.code) {
      KeyCode.escape => 'esc',
      KeyCode.left => '←',
      KeyCode.right => '→',
      KeyCode.up => '↑',
      KeyCode.down => '↓',
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
  }) {
    final label = keyLabel ?? signs;
    // each entry: the names of the keys it shows, their family, its hint
    final shown = <(List<String>, int?, String?)>[];
    for (final key in keys) {
      final hint = key.hint;
      if (hint == null && !showUnhinted) {
        continue;
      }
      final name = key.label(label);
      if (shown.any((e) => e.$3 == hint && e.$1.contains(name))) {
        continue;
      }
      final family = joinKeys && hint != null && key.then.isEmpty
          ? _familyOf(key.combo)
          : null;
      final joined = family == null
          ? null
          : shown.where((e) => e.$2 == family && e.$3 == hint).firstOrNull;
      if (joined != null) {
        joined.$1.add(name);
      } else {
        shown.add(([name], family, hint));
      }
    }
    return [
      for (final (names, family, hint) in shown)
        // the arrows' signs together, other keys apart by a blank
        (
          names.join(
            family == 0 && names.every((n) => n.length == 1) ? '' : ' ',
          ),
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

final class _KeyHintsBarState extends State<KeyHintsBar> {
  FocusManager? _manager;

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
    final spans = <Span>[];
    for (final (keys, hint) in KeyHintsBar.entries(
      _manager?.activeKeys ?? const <ActiveKey>[],
      keyLabel: widget.keyLabel,
      joinKeys: widget.joinKeys,
      showUnhinted: widget.showUnhinted,
    )) {
      if (spans.isNotEmpty) {
        spans.add(Span(widget.separator));
      }
      spans.add(Span(keys, keyStyle));
      if (hint != null) {
        spans.add(Span(' $hint', hintStyle));
      }
    }
    return Text.rich(
      spans,
      style: theme.text.merge(widget.style ?? const Style()),
      wrap: TextWrap.none,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}
