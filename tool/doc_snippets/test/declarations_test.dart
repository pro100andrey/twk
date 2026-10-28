import 'package:test/test.dart';
import 'package:twk_doc_snippets/declarations.dart';

void main() {
  test('names members by their type, constructors .new or by name', () {
    const source = '''
/// A box.
class Box {
  /// Makes one.
  const Box(this.child);

  /// An empty one.
  Box.empty() : child = null;

  /// What it holds.
  final Object? child;

  /// Its size.
  int get size => 0;

  set grow(int by) {}

  int operator +(int other) => other;

  void _hidden() {}
}

class _Private {
  void shown() {}
}

enum Mode { on, off }

extension on String {
  int get twice => length * 2;
}

int top() => 1;

var count = 0, other = 1;

typedef Callback = void Function();
''';
    final found = {
      for (final d in declarationsOf(source)) d.name: (d.kind, d.isPublic),
    };
    expect(found, {
      'Box': ('class', true),
      'Box.new': ('constructor', true),
      'Box.empty': ('constructor', true),
      'Box.child': ('field', true),
      'Box.size': ('getter', true),
      'Box.grow': ('setter', true),
      'Box.+': ('operator', true),
      'Box._hidden': ('method', false),
      '_Private': ('class', false),
      '_Private.shown': ('method', false),
      'Mode': ('enum', true),
      'Mode.on': ('enum value', true),
      'Mode.off': ('enum value', true),
      'extension on String': ('extension', true),
      'extension on String.twice': ('getter', true),
      'top': ('function', true),
      'count': ('variable', true),
      'other': ('variable', true),
      'Callback': ('typedef', true),
    });
  });

  test('has code where there is a body or an initializer to run, which '
      'a constant has not', () {
    const source = '''
abstract class A {
  A();
  external A.native();
  final int a = 1;
  late final int b;
  void c();
  void d() {}
  external void e();
  static const j = 1;
}
int f() => 0;
external int g();
int h = 1;
int? i;
const k = [1, 2];
''';
    final code = {for (final d in declarationsOf(source)) d.name: d.hasCode};
    expect(code, {
      'A': false,
      'A.new': true,
      'A.native': false,
      'A.a': true,
      'A.b': false,
      'A.c': false,
      'A.d': true,
      'A.e': false,
      'A.j': false,
      'f': true,
      'g': false,
      'h': true,
      'i': false,
      'k': false,
    });
  });

  test('spans the lines of the code, not of its doc comment, and puts the '
      'name on its line', () {
    const source = '''
class A {
  /// Doc.
  @override
  void b(
    int x,
  ) {
    print(x);
  }
}
''';
    final b = declarationsOf(source).singleWhere((d) => d.name == 'A.b');
    expect((b.firstLine, b.line, b.lastLine), (4, 4, 8));
    expect(source.substring(b.nameOffset, b.nameOffset + 1), 'b');
  });
}
