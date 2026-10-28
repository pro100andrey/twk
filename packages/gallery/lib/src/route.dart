// Where the gallery is, as a route says it, a URL hash:
// #/<group>/<page>?theme=…&o=…&t=… (README.md, "Routes").
import 'dart:convert';

/// [title] as a route names it: lower case, dashes for the rest
/// (`Checkbox, Switch` → `checkbox-switch`).
String slug(String title) => title
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// A route of the gallery, written as a URL hash:
/// `#/<group>/<page>?<parameters>`, so that the gallery opens at a place,
/// and a test or a still shows it the same each time.
///
/// The parameters: `theme=` (`dark`, `light`, `nord`, `mocha`, `latte`),
/// `tab=code`, `o=key:value;…` (the options), `t=` (time stopped at this
/// many milliseconds), `focus=` (`list`, `filter`, `page`, `stage`, `code`
/// or `o:<key>`), `filter=`, `palette=` (the palette open with this
/// query), `toast=` and `kind=`, `keys=` (comma-separated key names,
/// `comma` for a comma) and `type=` (characters typed after them).
/// `size=` and `bare=` are kept but mean nothing here: the terminal's size
/// is the grid. Unknown parameters are ignored.
final class GalleryRoute {
  const GalleryRoute({
    this.group,
    this.page,
    this.theme,
    this.tab,
    this.options = const {},
    this.t,
    this.focus,
    this.filter,
    this.palette,
    this.toast,
    this.kind,
    this.keys = const [],
    this.type,
    this.size,
    this.bare = false,
  });

  /// Reads a route as the design writes its hash, with or without the
  /// leading `#` and `/`; never throws.
  factory GalleryRoute.parse(String route) {
    var raw = route.trim();
    raw = raw.replaceFirst(RegExp('^#?/?'), '');
    raw = _decode(raw);
    final q = raw.indexOf('?');
    final path = q < 0 ? raw : raw.substring(0, q);
    final query = q < 0 ? '' : raw.substring(q + 1);
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final params = <String, String>{};
    for (final pair in query.split('&')) {
      if (pair.isEmpty) {
        continue;
      }
      final eq = pair.indexOf('=');
      final k = eq < 0 ? pair : pair.substring(0, eq);
      params[k] = eq < 0 ? '' : pair.substring(eq + 1);
    }
    final options = <String, String>{};
    for (final part in (params['o'] ?? '').split(';')) {
      final at = part.indexOf(':');
      if (at > 0) {
        options[part.substring(0, at)] = part.substring(at + 1);
      }
    }
    final t = num.tryParse(params['t'] ?? '');
    return GalleryRoute(
      group: parts.isNotEmpty ? parts[0] : null,
      page: parts.length > 1 ? parts[1] : null,
      theme: params['theme'],
      tab: params['tab'],
      options: options,
      t: params.containsKey('t')
          ? Duration(microseconds: ((t ?? 0) * 1000).round())
          : null,
      focus: params['focus'],
      filter: params['filter'],
      palette: params['palette'],
      toast: params['toast'],
      kind: params['kind'],
      keys: [
        for (final k in (params['keys'] ?? '').split(','))
          if (k == 'comma') ',' else if (k.isNotEmpty) k,
      ],
      type: params['type'],
      size: params['size'],
      bare: params['bare'] == '1',
    );
  }

  /// The group's slug: `controls`.
  final String? group;

  /// The page's slug: `checkbox-switch`.
  final String? page;

  final String? theme;

  /// `code` for the Code tab.
  final String? tab;

  /// The options by key, each value as the inspector names it.
  final Map<String, String> options;

  /// The time the clock stands still at.
  final Duration? t;

  final String? focus;
  final String? filter;
  final String? palette;
  final String? toast;
  final String? kind;

  /// Keys pressed after the gallery opens, as twk names them.
  final List<String> keys;

  /// Characters typed after [keys].
  final String? type;

  final String? size;
  final bool bare;

  /// The route as the design writes it.
  @override
  String toString() {
    final q = <String>[
      if (theme != null) 'theme=$theme',
      if (size != null) 'size=$size',
      if (tab != null) 'tab=$tab',
      if (t != null) 't=${_ms(t!)}',
      if (bare) 'bare=1',
      if (options.isNotEmpty) 'o=$_options',
      if (focus != null) 'focus=${_encode(focus!)}',
      if (filter != null) 'filter=${_encode(filter!)}',
      if (palette != null) 'palette=${_encode(palette!)}',
      if (toast != null) 'toast=${_encode(toast!)}',
      if (kind != null) 'kind=$kind',
      if (keys.isNotEmpty) 'keys=${keys.map(_key).join(',')}',
      if (type != null) 'type=${_encode(type!)}',
    ];
    final path = [?group, ?page].join('/');
    return '#/$path${q.isEmpty ? '' : '?${q.join('&')}'}';
  }

  /// The options as `o=` writes them: `wrap:none;width:40`.
  String get _options => [
    for (final MapEntry(:key, :value) in options.entries)
      '$key:${_encode(value)}',
  ].join(';');

  /// Key [k] as `keys=` names it.
  static String _key(String k) => k == ',' ? 'comma' : _encode(k);

  static String _ms(Duration d) {
    final us = d.inMicroseconds;
    return us % 1000 == 0 ? '${us ~/ 1000}' : '${us / 1000}';
  }

  /// [s] with blanks and what would end a parameter escaped.
  static String _encode(String s) => s
      .replaceAll('%', '%25')
      .replaceAll(' ', '%20')
      .replaceAll('&', '%26')
      .replaceAll('#', '%23')
      .replaceAll('+', '%2B');

  static final _hex = RegExp(r'^[0-9a-fA-F]{2}$');

  /// [s] with its %XX escapes decoded as UTF-8, a '+' kept (`ctrl+k`);
  /// what is no escape left as it is.
  static String _decode(String s) {
    final out = StringBuffer();
    final bytes = <int>[];
    void flush() {
      if (bytes.isNotEmpty) {
        out.write(utf8.decode(bytes, allowMalformed: true));
        bytes.clear();
      }
    }

    for (var i = 0; i < s.length; i++) {
      final hex =
          s[i] == '%' &&
              i + 3 <= s.length &&
              _hex.hasMatch(s.substring(i + 1, i + 3))
          ? int.parse(s.substring(i + 1, i + 3), radix: 16)
          : null;
      if (hex != null) {
        bytes.add(hex);
        i += 2;
      } else {
        flush();
        out.write(s[i]);
      }
    }
    flush();
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryRoute && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
