// Cli.inspect: a value as a JsonView shows it, expanded, its runtime type
// and label first; objects through toJson or toString, cycles marked; as
// the terminal takes it, at the info level.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';
import 'package:twk_rich/twk_rich.dart' show SyntaxTheme;

final class _Point {
  _Point(this.x, this.y);

  final int x;
  final int y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

final class _Opaque {
  @override
  String toString() => 'Opaque#1';
}

void main() {
  late FakeCliTerminal terminal;
  late Cli cli;

  setUp(() {
    terminal = FakeCliTerminal();
    cli = Cli(terminal: terminal);
  });

  test('a map fully expanded, after its label and runtime type', () async {
    await cli.inspect(<String, Object?>{
      'name': 'twk',
      'tags': ['tui', 'cli'],
      'nested': {'a': 1, 'b': null},
    }, label: 'config');
    expect(terminal.out.toString(), '''
config: _Map<String, Object?> {
  "name": "twk",
  "tags": [
    "tui",
    "cli"
  ],
  "nested": {
    "a": 1,
    "b": null
  }
}
''');
    expect(terminal.err.toString(), isEmpty);
  });

  test(
    'a list to expandedDepth, the rest folded; scalars on one line',
    () async {
      await cli.inspect([
        1,
        'two',
        {'three': 3.0},
      ], expandedDepth: 1);
      await cli.inspect(42, label: 'n');
      await cli.inspect(null);
      await cli.inspect(<int>[]);
      expect(terminal.out.toString(), '''
List<Object> [
  1,
  "two",
  { 1 key }
]
n: int 42
Null null
List<int> []
''');
    },
  );

  test(
    'an object through its toJson, else its toString; a cycle marked',
    () async {
      final cyclic = <String, Object?>{'name': 'a'};
      cyclic['self'] = cyclic;
      await cli.inspect(_Point(1, 2), label: 'p');
      await cli.inspect(_Opaque());
      await cli.inspect(cyclic);
      expect(terminal.out.toString(), '''
p: _Point {
  "x": 1,
  "y": 2
}
_Opaque "Opaque#1"
_Map<String, Object?> {
  "name": "a",
  "self": <cycle>
}
''');
    },
  );

  test(
    "in the styles of the theme's syntax where the terminal takes "
    'escapes, the label bold, the type muted; nothing under --quiet',
    () async {
      final ansi = FakeCliTerminal(ansi: true, outputIsTerminal: true);
      await Cli(terminal: ansi).inspect({'a': 'b'}, label: 'x');
      expect(ansi.screenLines, [
        'x: _Map<String, String> {',
        '  "a": "b"',
        '}',
      ]);
      final syntax = SyntaxTheme.from(const CliTheme().lineData);
      final screen = ansi.screen;
      expect(screen.cell(0, 0).attrs & Attr.bold, Attr.bold);
      expect(screen.cell(1, 0).attrs & Attr.bold, 0);
      // the terminal's muted: dim
      expect(screen.cell(3, 0).attrs & Attr.dim, Attr.dim);
      expect(screen.cell(24, 0).attrs & Attr.dim, 0);
      expect(
        [screen.cell(2, 1).fg, screen.cell(7, 1).fg],
        [
          isNot(screen.cell(5, 1).fg),
          isNot(screen.cell(2, 1).fg),
        ],
      );
      expect(syntax.key, isNot(syntax.string));

      final quiet = FakeCliTerminal();
      await Cli(terminal: quiet, level: LogLevel.error).inspect({'a': 1});
      expect(quiet.out.toString(), isEmpty);
    },
  );

  test('committed above what is live in the inline session', () async {
    // the session on a fake clock: what it commits comes in frames, as
    // the test moves the clock, 60 ms (a frame and then some) at a time
    final clock = FakeClock();
    Future<T> settle<T>(Future<T> future) => clock.elapseUntil(
      future,
      step: const Duration(milliseconds: 60),
      within: const Duration(seconds: 6),
    );
    final terminal = FakeCliTerminal.interactive(
      width: 40,
      height: 10,
      fakeClock: clock,
    );
    final cli = Cli(terminal: terminal);
    addTearDown(() => settle(cli.close()));
    await settle(cli.show(const Text('before')));
    await settle(cli.inspect({'a': 1}, label: 'x'));
    expect(terminal.screenLines, [
      'before',
      'x: _Map<String, int> {',
      '  "a": 1',
      '}',
    ]);
  });
}
