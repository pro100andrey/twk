// The port of twk's key names (lib/src/key_names.dart) held to twk's own:
// KeyCombo's parser, twk_core's KeyCode and input parser, and twk_test's
// bytes of an xterm without the kitty keyboard protocol.

import 'package:test/test.dart';
import 'package:twk/twk.dart' show KeyCombo;
import 'package:twk_core/twk_core.dart' show InputParser, KeyCode, KeyEvent;
import 'package:twk_lints/src/key_names.dart';
// the bytes the tester sends for a key, which twk_test does not export
import 'package:twk_test/src/keys.dart' show keyBytes;

void main() {
  test('the key names are those of KeyCode', () {
    expect(keyNames, [
      for (final code in KeyCode.values)
        if (code != KeyCode.char) code.name.toLowerCase(),
    ]);
  });

  // every key twk names, with each set of modifiers
  final keys = [
    for (final name in [
      for (var c = 0x21; c < 0x7F; c++) String.fromCharCode(c),
      'space',
      'я',
      'Я',
      ...keyNames,
      // Escape by the name the hints show it by
      'esc',
    ])
      for (var m = 0; m < 16; m++)
        [
          for (final (bit, modifier) in [
            (4, 'ctrl'),
            (2, 'alt'),
            (1, 'shift'),
            (8, 'super'),
          ])
            if (m & bit != 0) modifier,
          name,
        ].join('+'),
  ];

  // names that are not ones, one for each message
  const wrong = [
    '',
    'a  b',
    ' a',
    'leader',
    'leader x',
    'ctrl+leader',
    'cmd+s',
    'Ctrl+s',
    'control+a',
    'ctrl+ctrl+a',
    'ctrl+shift+ctrl+a',
    'shift+space',
    'Esc',
    'ret',
    'Enter',
    'pgdn',
    'spacebar',
    'ctrl',
    'ctrl+alt',
    'ctrl+',
    'ab',
    'ctrl+\x01',
    '\x7F',
    'shift+1',
    'shift+?',
    'shift+я',
    'F1',
    'f13',
  ];

  test('the names read as KeyCombo.parseSequence reads them', () {
    for (final spec in [...keys, ...wrong, 'g g', 'ctrl+x ctrl+s', '+ -']) {
      expect(_port(() => parseKeys(spec)), _twk(spec), reason: spec);
    }
    for (final spec in ['leader', 'leader w', 'g leader', 'ctrl+leader']) {
      expect(
        _port(() => parseKeys(spec, leader: true)),
        _twk(spec, leader: KeyCombo.parse('f12')).replaceAll('f12', 'leader'),
        reason: spec,
      );
    }
  });

  test('one key reads as KeyCombo.parse reads it', () {
    for (final spec in ['a', 'g g', 'ctrl+x ctrl+s', 'esc']) {
      expect(
        _port(() => [parseKey(spec)]),
        _twk(spec, one: true),
        reason: spec,
      );
    }
  });

  test('a key arrives without the kitty protocol as xterm sends it', () {
    for (final spec in keys) {
      final KeySpec key;
      try {
        key = parseKey(spec);
      } on KeyNameException {
        continue;
      }
      final sent = _sent(spec);
      switch (withoutKitty(key)) {
        case AsItself():
          expect(sent, '$key', reason: spec);
        case AsOther(key: final other, sent: true):
          expect(sent, isNot('$key'), reason: spec);
          expect(sent, '$other', reason: spec);
        // what twk documents of a key without bytes of its own
        case AsOther(sent: false) || NotSent():
          expect(sent, isNull, reason: spec);
      }
    }
  });

  test("the keys without bytes of their own are KeyCombo's", () {
    String? other(String spec) => switch (withoutKitty(parseKey(spec))) {
      AsOther(:final key, sent: false) => '$key',
      _ => null,
    };
    expect(other('ctrl+shift+c'), 'ctrl+c');
    expect(other('ctrl+alt+S'), 'ctrl+alt+s');
    expect(other('ctrl+enter'), 'enter');
    expect(other('shift+enter'), 'enter');
    expect(other('alt+shift+escape'), 'alt+escape');
    expect(other('ctrl+2'), 'ctrl+space');
    expect(withoutKitty(parseKey('super+a')), isA<NotSent>());
    expect(withoutKitty(parseKey('ctrl+tab')), isA<NotSent>());
  });
}

/// What the port makes of a spec: the keys, or the message.
String _port(List<KeySpec> Function() parse) {
  try {
    return parse().join(' ');
  } on KeyNameException catch (e) {
    return 'error: ${e.message}';
  }
}

/// What twk makes of [spec]: the keys, or the message.
String _twk(String spec, {KeyCombo? leader, bool one = false}) {
  try {
    return one
        ? '${KeyCombo.parse(spec)}'
        : KeyCombo.parseSequence(spec, leader: leader).join(' ');
  } on FormatException catch (e) {
    return 'error: ${e.message}';
  }
}

/// The key twk reads from the bytes an xterm sends for [spec] without the
/// kitty protocol; null where it sends none of its own.
String? _sent(String spec) {
  final List<int> bytes;
  try {
    bytes = keyBytes(spec, kitty: false).single;
    // keyBytes's word for a key xterm sends no bytes of its own for
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return null;
  }
  final parser = InputParser();
  final events = [...parser.feed(bytes), ...parser.flush()];
  return events.whereType<KeyEvent>().map(KeyCombo.fromEvent).join(' ');
}
