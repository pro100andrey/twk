// A LayoutBuilder builds its child in the layout, with the constraints it
// is laid out within: again when they change, when it is replaced or when
// something it depends on changes, and at no other layout; what it builds
// is laid out in the same frame, the elements below it keep their state,
// and errors there are contained as a build's are.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineOwner, Screen;

import '../layout/view.dart' show Label, RenderLabel;
import 'harness.dart' show Probe, ProbeState;

/// A widget tree laid out at [width] × [height] and painted as a frame
/// does: the build scope, the layout and the paint, then [BuildOwner.
/// finalizeTree].
final class Ui {
  Ui(this.width, this.height, {this.onBuildError});

  int width;
  int height;
  final Widget Function(Element element, Object error, StackTrace stack)?
  onBuildError;
  final screen = Screen(40, 10);
  late final owner = BuildOwner(
    onBuildScheduled: () => scheduled++,
    onBuildError: onBuildError,
  );
  late final pipeline = PipelineOwner(
    () {},
    segmenter: screen.canvas.segmenter,
  );

  /// How many times the owner asked for a build scope.
  var scheduled = 0;

  RootElement? _root;
  RenderObject? _top;

  RootElement get root => _root!;

  /// Shows [widget] and runs a frame.
  void pump(Widget widget) {
    _root = RootWidget(child: widget).attach(owner, _root);
    frame();
  }

  /// Runs a frame at [w] × [h].
  void resize(int w, int h) {
    width = w;
    height = h;
    pipeline.markAllDirty();
    frame();
  }

  void frame() {
    owner.buildScope();
    final top = root.renderObject!;
    if (!identical(top, _top)) {
      pipeline.root = top;
      _top = top;
    }
    pipeline
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    owner.finalizeTree();
    screen.render();
  }

  /// The text of the rows laid out.
  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * 40 + x]),
      ].join().trimRight(),
  ];

  /// Every element of the tree, parents before children.
  Iterable<Element> get elements sync* {
    final stack = <Element>[root];
    while (stack.isNotEmpty) {
      final e = stack.removeLast();
      yield e;
      final children = <Element>[];
      e.visitChildren(children.add);
      stack.addAll(children.reversed);
    }
  }

  /// The state of the only state of type [S] in the tree.
  S stateOf<S extends State<StatefulWidget>>() => elements
      .whereType<StatefulElement>()
      .map((e) => e.state)
      .whereType<S>()
      .single;
}

/// `W×H` of [c]'s maximum.
String sizeOf(BoxConstraints c) => '${c.maxW}×${c.maxH}';

/// Shows [value] to the widgets below it that depend on it.
final class Value extends InheritedWidget {
  const Value(this.value, {required super.child});

  final String value;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Value>()!.value;

  @override
  bool updateShouldNotify(Value oldWidget) => value != oldWidget.value;
}

/// Shows the [Value] above it.
final class ShowValue extends StatelessWidget {
  const ShowValue();

  @override
  Widget build(BuildContext context) => Label(Value.of(context));
}

/// Shows what [builder] returns; [HostState.change] rebuilds it.
final class Host extends StatefulWidget {
  const Host(this.builder);

  final Widget Function(int count) builder;

  @override
  State<Host> createState() => HostState();
}

final class HostState extends State<Host> {
  var count = 0;

  void change() => setState(() => count++);

  @override
  Widget build(BuildContext context) => widget.builder(count);
}

/// A widget whose render object throws when it is created.
final class Broken extends LeafRenderObjectWidget {
  const Broken();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      throw StateError('no render object');
}

/// Shows what [error] says, as an app shows an error widget.
Widget shown(Element element, Object error, StackTrace stack) =>
    Label('! $error');

void main() {
  test('builds its child in the layout, with the constraints it is laid out '
      'within', () {
    final ui = Ui(10, 2)
      ..pump(LayoutBuilder(builder: (context, c) => Label(sizeOf(c))));
    expect(ui.rows(), ['10×2', '']);
  });

  test('builds again when the constraints change, and at no other '
      'layout', () {
    final log = <String>[];
    final ui = Ui(10, 2)
      ..pump(
        Align(
          alignment: Alignment.topLeft,
          child: LayoutBuilder(
            builder: (context, c) {
              log.add(sizeOf(c));
              return Probe('child', log, builder: (s) => Label('${s.count}'));
            },
          ),
        ),
      );
    expect(log, [
      '10×2',
      'child initState',
      'child didChangeDependencies',
      'child build',
    ]);
    log.clear();
    // laid out again because its child's text changed, and with its
    // parent at the same size
    ui.stateOf<ProbeState>().change(() => ui.stateOf<ProbeState>().count++);
    ui
      ..frame()
      ..pipeline.markAllDirty()
      ..frame();
    expect(log, ['child build']);
    expect(ui.rows(), ['1', '']);
    log.clear();
    ui.resize(6, 1);
    expect(log, ['6×1', 'child didUpdateWidget 0 to 0', 'child build']);
    expect(ui.rows(), ['1']);
  });

  test('builds again when it is replaced, or something it depends on '
      'changes', () {
    var builds = 0;
    final ui = Ui(10, 1)
      ..pump(
        Host(
          (count) => Value(
            'v${count ~/ 2}',
            child: LayoutBuilder(
              builder: (context, c) {
                builds++;
                return Label('${Value.of(context)} $count');
              },
            ),
          ),
        ),
      );
    expect(
      [ui.rows(), builds],
      [
        ['v0 0'],
        1,
      ],
    );
    final host = ui.stateOf<HostState>()..change();
    ui.frame();
    expect(
      [ui.rows(), builds],
      [
        ['v0 1'],
        2,
      ],
    );
    host.change();
    ui.frame();
    expect(
      [ui.rows(), builds],
      [
        ['v1 2'],
        3,
      ],
    );
  });

  test('a dependency changing below it rebuilds the dependent in the same '
      'layout, asking for no build scope', () {
    final ui = Ui(10, 1)
      ..pump(
        LayoutBuilder(
          builder: (context, c) =>
              Value(c.maxW > 5 ? 'wide' : 'narrow', child: const ShowValue()),
        ),
      );
    expect(ui.rows(), ['wide']);
    final scheduled = ui.scheduled;
    ui.resize(5, 1);
    expect(ui.rows(), ['narro']);
    expect(ui.scheduled, scheduled);
  });

  test('an element rebuilt in the build scope is marked dirty again and '
      'rebuilt in the layout build without failing an assert', () {
    final log = <String>[];
    final ui = Ui(10, 1)
      ..pump(
        LayoutBuilder(
          builder: (context, c) => Value(
            '${c.maxW}',
            child: Probe(
              'probe',
              log,
              builder: (state) => Label(Value.of(state.context)),
            ),
          ),
        ),
      );
    log.clear();
    ui.stateOf<ProbeState>().change(() {});
    ui
      ..width = 4
      ..pipeline.markAllDirty()
      ..frame();
    expect(log, [
      'probe build',
      'probe didUpdateWidget 0 to 0',
      'probe didChangeDependencies',
      'probe build',
    ]);
    expect(ui.rows(), ['4']);
  });

  test('an element elsewhere marked dirty in its build waits for the next '
      'build scope, which the owner asks for', () {
    HostState? host;
    final ui = Ui(10, 1)
      ..pump(
        Host(
          (count) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Label('host $count'),
              LayoutBuilder(
                builder: (context, c) {
                  host?.change();
                  return Label(sizeOf(c));
                },
              ),
            ],
          ),
        ),
      );
    host = ui.stateOf<HostState>();
    final scheduled = ui.scheduled;
    ui.resize(8, 2);
    expect(ui.rows(), ['host 0', '8×2']);
    expect(ui.scheduled, scheduled + 1);
    ui.frame();
    expect(ui.rows(), ['host 1', '8×2']);
  });

  test('a GlobalKey keeps the state of what moves from one layout to the '
      'other', () {
    final log = <String>[];
    final key = GlobalKey();
    final ui = Ui(10, 2)
      ..pump(
        LayoutBuilder(
          builder: (context, c) {
            final pane = Probe('pane', log, key: key, child: const Label('p'));
            return c.maxW >= 8
                ? Row(children: [const Label('wide'), pane])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [pane, const Label('narrow')],
                  );
          },
        ),
      );
    expect(ui.rows(), ['widep', '']);
    log.clear();
    ui.resize(6, 2);
    expect(ui.rows(), ['p', 'narrow']);
    expect(log, [
      'pane deactivate',
      'pane activate',
      'pane didUpdateWidget 0 to 0',
      'pane build',
    ]);
  });

  test('a GlobalKey it builds on two widgets at once fails the assert of '
      'the finalizeTree after the layout, also after frames with nothing '
      'to finalize', () {
    final key = GlobalKey();
    final onTwo = throwsA(
      isA<AssertionError>().having(
        (e) => '${e.message}',
        'message',
        contains('$key is on two widgets at once'),
      ),
    );
    final ui = Ui(10, 2);
    void pumpTwice() => ui.pump(
      LayoutBuilder(
        builder: (context, c) => c.maxW > 8
            ? Column(
                children: [
                  Label('a', key: key),
                  SizedBox(child: Label('b', key: key)),
                ],
              )
            : const Label('once'),
      ),
    );
    expect(pumpTwice, onTwo);
    ui
      ..frame()
      ..resize(8, 2)
      ..frame();
    expect(ui.rows(), ['once', '']);
    ui
      ..width = 10
      ..pipeline.markAllDirty();
    expect(ui.frame, onTwo);
  });

  group('the elements it removes', () {
    test('are unmounted when the tree is finalized after the layout', () {
      final log = <String>[];
      final ui = Ui(10, 1)
        ..pump(
          LayoutBuilder(
            builder: (context, c) =>
                c.maxW > 5 ? Probe('wide', log) : const Label('narrow'),
          ),
        );
      log.clear();
      ui.resize(5, 1);
      expect(log, ['wide deactivate', 'wide dispose']);
    });

    test('ask for no build scope: they wait for the finalizeTree after the '
        'layout', () {
      final log = <String>[];
      final ui = Ui(10, 1)
        ..pump(
          LayoutBuilder(
            builder: (context, c) =>
                c.maxW > 5 ? Probe('wide', log) : const Label('narrow'),
          ),
        );
      log.clear();
      final scheduled = ui.scheduled;
      ui.pipeline
        ..markAllDirty()
        ..flushLayout(5, 1);
      expect(log, ['wide deactivate']);
      expect(ui.scheduled, scheduled);
      ui.owner.finalizeTree();
      expect(log, ['wide deactivate', 'wide dispose']);
      // none is pending: a mark asks for the next build scope
      ui.root.markNeedsBuild();
      expect(ui.scheduled, scheduled + 1);
    });
  });

  group('an error', () {
    test('its builder throws is reported, and what the owner gives shown '
        'in place of its child until a build does not throw', () {
      final errors = <String>[];
      final ui =
          Ui(
            12,
            1,
            onBuildError: (element, error, stack) {
              errors.add('${element.widget.runtimeType}: $error');
              return Label('! $error');
            },
          )..pump(
            LayoutBuilder(
              builder: (context, c) =>
                  c.maxW > 8 ? throw StateError('too wide') : Label(sizeOf(c)),
            ),
          );
      expect(ui.rows(), ['! Bad state:']);
      expect(errors, ['LayoutBuilder: Bad state: too wide']);
      final element = ui.elements.whereType<RenderObjectElement>().first;
      expect(element.describe().flags, contains(DiagnosticsFlag.error));
      ui.resize(6, 1);
      expect(ui.rows(), ['6×1']);
      expect(element.describe().flags, isNot(contains(DiagnosticsFlag.error)));
    });

    test('what it builds throws as it is created is reported, and shown in '
        'its place', () {
      final errors = <String>[];
      final ui = Ui(
        30,
        1,
        onBuildError: (element, error, stack) {
          errors.add('${element.widget.runtimeType}: $error');
          return shown(element, error, stack);
        },
      )..pump(LayoutBuilder(builder: (context, c) => const Broken()));
      expect(ui.rows(), ['! Bad state: no render object']);
      expect(errors, ['LayoutBuilder: Bad state: no render object']);
    });

    test('an element below it rebuilt in its layout throws is shown below '
        'it, not above', () {
      final ui = Ui(30, 2, onBuildError: shown)
        ..pump(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Label('above'),
              LayoutBuilder(
                builder: (context, c) => Value(
                  c.maxW > 20 ? 'ok' : 'throw',
                  child: const _ThrowsOnUpdate(),
                ),
              ),
            ],
          ),
        );
      expect(ui.rows(), ['above', 'ok']);
      ui.resize(20, 2);
      expect(ui.rows(), ['above', '! Bad state: throw']);
    });

    test('a child it built throws in a later rebuild is shown in its '
        'place, not above it', () {
      final ui = Ui(30, 2, onBuildError: shown)
        ..pump(
          Host(
            (count) => Value(
              count == 0 ? 'ok' : 'throw',
              // the same widgets: only the child that depends on the value
              // is rebuilt
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Label('above'),
                  LayoutBuilder(builder: _throwsOnUpdate),
                ],
              ),
            ),
          ),
        );
      expect(ui.rows(), ['above', 'ok']);
      ui.stateOf<HostState>().change();
      ui.frame();
      expect(ui.rows(), ['above', '! Bad state: throw']);
    });
  });

  test('describes itself and what it built', () {
    final ui = Ui(10, 1)
      ..pump(LayoutBuilder(builder: (context, c) => const Label('a')));
    expect(ui.root.describe().toStringDeep(), '''
RootWidget       10×1
└─ LayoutBuilder 10×1
   └─ Label      10×1''');
  });

  test('a LayoutBuilder inside another builds in the same layout', () {
    final ui = Ui(10, 2)
      ..pump(
        LayoutBuilder(
          builder: (context, outer) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Label(sizeOf(outer)),
              LayoutBuilder(builder: (context, inner) => Label(sizeOf(inner))),
            ],
          ),
        ),
      );
    expect(ui.rows(), ['10×2', '10×2']);
  });

  test('the items of a ListView with an item extent it builds are laid out '
      'and painted in the same frame', () {
    final ui = Ui(20, 3)
      ..pump(
        Host(
          (count) => LayoutBuilder(
            builder: (context, c) => ListView(
              itemExtent: 1,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: count * 2),
                  child: const Text('item 0'),
                ),
                const Text('item 1'),
              ],
            ),
          ),
        ),
      );
    expect(ui.rows(), ['item 0', 'item 1', '']);
    ui
      ..stateOf<HostState>().change()
      ..frame();
    expect(ui.rows(), ['  item 0', 'item 1', '']);
    expect(ui.pipeline.hasWork, isFalse);
  });

  test('answers the intrinsic sizes of what it built last; a parent laid '
      'out by those it then changed is laid out again on the next frame', () {
    final ui = Ui(10, 1)
      ..pump(
        Row(
          children: [
            IntrinsicWidth(
              child: LayoutBuilder(
                builder: (context, c) => Text(c.maxW < 4 ? 'narrow' : 'wide'),
              ),
            ),
            const Label('|'),
          ],
        ),
      );
    // it had built nothing to answer with
    expect(ui.rows(), ['|']);
    expect(ui.pipeline.hasWork, isTrue);
    ui.frame();
    expect(ui.rows(), ['wide  |']);
    ui.frame();
    expect(ui.rows(), ['wide|']);
    expect(ui.pipeline.hasWork, isFalse);
  });
}

Widget _throwsOnUpdate(BuildContext context, BoxConstraints c) =>
    const _ThrowsOnUpdate();

/// Shows the [Value] above it, and throws when it changes to `throw`.
final class _ThrowsOnUpdate extends LeafRenderObjectWidget {
  const _ThrowsOnUpdate();

  @override
  RenderLabel createRenderObject(BuildContext context) =>
      RenderLabel(Value.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderLabel renderObject) {
    final value = Value.of(context);
    if (value == 'throw') {
      throw StateError(value);
    }
  }
}
