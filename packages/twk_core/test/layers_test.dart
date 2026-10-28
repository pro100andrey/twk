// The core's layers: each library of lib/src imports its own layer and the
// ones below it only, so that a program that needs the terminal's links
// and stdio compiles them and not the app, the render tree and the rest.
// Doc imports (`/// @docImport`) don't count: they compile nothing.
// package:twk_core/terminal.dart, the terminal without the render tree and
// the app, is held to the layers below the app and off the render tree, and
// to names package:twk_core/twk_core.dart exports too.
import 'dart:io';

import 'package:test/test.dart';

/// The layers, lowest first. A library imports the libraries of its own
/// layer and of the layers before it; `render` and `terminal`, the two
/// halves of a frame, don't import each other.
const _layers = <(String, List<String>)>[
  // Unicode segmentation, widths and bidi: tables and code only.
  ('unicode', ['unicode/']),
  // Cells, pens and their bytes, and the input decoded: no dart:io.
  (
    'draw',
    [
      'byte_sink.dart',
      'canvas.dart',
      'fill.dart',
      'graphics.dart',
      'input/',
      'line_encoder.dart',
      'presenter.dart',
      'screen.dart',
      'style.dart',
      'surface.dart',
      'terminal/sequences.dart',
    ],
  ),
  // The process: stdio, the terminal's links, files, signals, local
  // sockets; the only layer that imports dart:io and dart:ffi.
  (
    'platform',
    [
      'platform/',
      'terminal/address.dart',
      'terminal/link.dart',
      'terminal/outbox.dart',
      'terminal/plain.dart',
      'terminal/posix_tty.dart',
      'terminal/socket.dart',
      'terminal/stdio_link.dart',
      'terminal/windows_console.dart',
    ],
  ),
  // The records of an app, served over the platform's sockets.
  ('log', ['log.dart']),
  // The render tree, which logs its overflows.
  ('render', ['render/']),
  // The terminal: caps, input, modes and trace over a link.
  ('terminal', ['terminal/terminal.dart', 'terminal/trace.dart']),
  // What runs a render tree on a terminal.
  ('app', ['app.dart', 'headless.dart']),
];

/// The two layers at the same height: neither imports the other.
const _siblings = {'render', 'terminal'};

/// The index of the layer [path] (relative to lib/src) is in.
int _layerOf(String path) {
  for (var i = 0; i < _layers.length; i++) {
    for (final prefix in _layers[i].$2) {
      if (prefix.endsWith('/') ? path.startsWith(prefix) : path == prefix) {
        return i;
      }
    }
  }
  throw StateError('lib/src/$path is in no layer: add it to one');
}

/// The name of the layer [path] is in.
String _nameOf(String path) => _layers[_layerOf(path)].$1;

/// The libraries of lib/src (part files left out) and what each imports
/// or exports of lib/src, conditional URIs included.
Map<String, Set<String>> _imports() {
  final src = Directory('lib/src');
  final directive = RegExp(
    r"^(?:import|export)\s+'([^']+)'([^;]*);",
    multiLine: true,
  );
  final conditional = RegExp(r"if\s*\([^)]*\)\s*'([^']+)'");
  final out = <String, Set<String>>{};
  for (final file in src.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) {
      continue;
    }
    final text = file.readAsStringSync();
    if (RegExp(r'^part of\b', multiLine: true).hasMatch(text)) {
      continue;
    }
    final path = file.uri.pathSegments
        .skipWhile((s) => s != 'src')
        .skip(1)
        .join('/');
    final dir = Uri.parse(path);
    out[path] = {
      for (final m in directive.allMatches(text))
        for (final uri in [
          m[1]!,
          ...conditional.allMatches(m[2]!).map((c) => c[1]!),
        ])
          if (!uri.contains(':')) dir.resolve(uri).path,
    };
  }
  return out;
}

/// What [library] (relative to lib) exports of lib/src: each library's
/// path relative to lib/src, and the names it shows, null for all.
Map<String, Set<String>?> _exports(String library) {
  final directive = RegExp(
    r"^export\s+'src/([^']+)'\s*(?:show\s+([^;]+))?;",
    multiLine: true,
  );
  return {
    for (final m in directive.allMatches(
      File('lib/$library').readAsStringSync(),
    ))
      m[1]!: m[2]?.split(',').map((name) => name.trim()).toSet(),
  };
}

void main() {
  final imports = _imports();

  test('every library of lib/src is in a layer', () {
    for (final path in imports.keys) {
      expect(() => _layerOf(path), returnsNormally, reason: path);
    }
  });

  test('no library imports a layer above its own, nor its sibling', () {
    final upward = [
      for (final MapEntry(key: from, value: targets) in imports.entries)
        for (final to in targets)
          if (_layerOf(to) > _layerOf(from) ||
              (_layerOf(to) != _layerOf(from) &&
                  _siblings.contains(_nameOf(to)) &&
                  _siblings.contains(_nameOf(from))))
            '$from (${_nameOf(from)}) -> $to (${_nameOf(to)})',
    ]..sort();
    expect(upward, isEmpty);
  });

  test('only the platform layer imports dart:io and dart:ffi', () {
    final io = RegExp(r"^import\s+'dart:(io|ffi)'", multiLine: true);
    final platform = _layers.indexWhere((l) => l.$1 == 'platform');
    final outside = [
      for (final path in imports.keys)
        if (_layerOf(path) != platform &&
            io.hasMatch(File('lib/src/$path').readAsStringSync()))
          path,
    ];
    expect(outside, isEmpty);
  });

  group('package:twk_core/terminal.dart', () {
    final exports = _exports('terminal.dart');

    test('reaches no library of the render tree or the app', () {
      final terminal = _layers.indexWhere((l) => l.$1 == 'terminal');
      final reached = <String>{};
      final pending = [...exports.keys];
      while (pending.isNotEmpty) {
        final path = pending.removeLast();
        if (reached.add(path)) {
          pending.addAll(imports[path] ?? const {});
        }
      }
      expect(reached, contains('terminal/terminal.dart'));
      final above = [
        for (final path in reached)
          if (_layerOf(path) > terminal || _nameOf(path) == 'render')
            '$path (${_nameOf(path)})',
      ]..sort();
      expect(above, isEmpty);
    });

    test('exports only what package:twk_core/twk_core.dart exports', () {
      final core = _exports('twk_core.dart');
      final extra = [
        for (final MapEntry(key: path, value: names) in exports.entries)
          if (!core.containsKey(path))
            path
          else if (core[path] case final shown?)
            if (names == null)
              '$path: all of it, twk_core.dart only $shown'
            else
              for (final name in names.difference(shown)) '$path: $name',
      ];
      expect(extra, isEmpty);
    });
  });
}
