// runApp's onError: told of every error the binding reports, of each
// ErrorOrigin, in addition to what happens to it; it cannot stop the app
// from ending, and an error it throws is logged, not reported again.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/log.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

/// What `onError` was told of.
typedef _Told = (Object, StackTrace, ErrorOrigin, String?);

final class _Bad extends LeafRenderObjectWidget {
  const _Bad({this.layout = false, this.paint = false});

  final bool layout;
  final bool paint;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBad(this);
}

final class _RenderBad extends RenderObject {
  _RenderBad(this.widget);

  final _Bad widget;

  @override
  void performLayout(BoxConstraints c) {
    if (widget.layout) {
      throw StateError('layout oops');
    }
    width = c.constrainWidth(4);
    height = c.constrainHeight(1);
  }

  @override
  void paint(PaintContext ctx) {
    if (widget.paint) {
      throw StateError('paint oops');
    }
  }
}

void main() {
  late List<_Told> told;
  ErrorReporter collect() {
    told = [];
    return (e, s, o, p) => told.add((e, s, o, p));
  }

  test('a build that throws is told as build, with the widget path, and '
      'still shows an ErrorWidget', () async {
    final run = Run(
      column([
        Probe((_) => throw StateError('build oops')),
        const Label('below'),
      ]),
      onError: collect(),
    );
    await run.settle();
    final [(error, stack, origin, path)] = told;
    expect(error, isA<StateError>());
    expect('$stack', contains('build'));
    expect(origin, ErrorOrigin.build);
    expect(path, startsWith('Column'));
    expect(run.logged(LogLevel.error), hasLength(1));
    expect(run.rows, contains('below'));
    run.term.type('\x03');
    await run.ended();
  });

  test('a layout that throws is told as layout, a paint as paint', () async {
    final run = Run(
      column(const [_Bad(layout: true), _Bad(paint: true)]),
      onError: collect(),
    );
    await run.settle();
    expect(told.map((t) => t.$3), [ErrorOrigin.layout, ErrorOrigin.paint]);
    expect(told.map((t) => t.$4), everyElement(contains('_Bad')));
    expect(told[0].$1, isA<StateError>());
    expect(run.logged(LogLevel.error), hasLength(2));
    run.term.type('\x03');
    await run.ended();
  });

  test('an InputListener, a focus key handler and a mouse Listener that '
      'throw are told as input, and the app ends with a WidgetError', () async {
    Future<void> check(Widget child, String input, String path) async {
      final run = Run(Stack(children: [child]), onError: collect());
      await run.settle();
      run.term.type(input);
      final ended = await run.ended().then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      expect(ended, isA<WidgetError>());
      final [(error, _, origin, told0)] = told;
      expect((error as StateError).message, 'input oops');
      expect(origin, ErrorOrigin.input);
      expect(told0, path);
      expect(told0, (ended! as WidgetError).path);
      expect(run.term.closed, isTrue);
    }

    await check(
      InputListener(
        onEvent: (e) => throw StateError('input oops'),
        child: const SizedBox(),
      ),
      'a',
      'Stack → InputListener',
    );
    await check(
      Focus(
        autofocus: true,
        onKeyEvent: (n, e) => throw StateError('input oops'),
        child: const Label('x'),
      ),
      'a',
      'Stack → Focus',
    );
    await check(
      Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => throw StateError('input oops'),
        child: const SizedBox.expand(),
      ),
      '\x1b[<0;1;1M',
      'Stack → Listener',
    );
  });

  test('an error nothing catches is told as uncaught once, with no path, '
      'and the app ends with it', () async {
    final key = GlobalKey<ProbeState>();
    final run = Run(
      Probe(key: key, (_) => const Label('x')),
      onError: collect(),
    );
    await run.settle();
    AppBinding.of(key.currentContext!).startTimer(
      const Duration(milliseconds: 5),
      () => throw StateError('late oops'),
    );
    await run.settle();
    final ended = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(ended, isA<StateError>());
    final [(error, _, origin, path)] = told;
    expect(error, same(ended));
    expect(origin, ErrorOrigin.uncaught);
    expect(path, isNull);
    expect(run.term.closed, isTrue);
  });

  test('onError that throws is logged and not told again; the app goes on '
      'and ends as it would', () async {
    var calls = 0;
    final run = Run(
      column([
        Probe((_) => throw StateError('build oops')),
        InputListener(
          onEvent: (e) => throw StateError('input oops'),
          child: const SizedBox(),
        ),
      ]),
      onError: (e, s, o, p) {
        calls++;
        throw StateError('hook oops');
      },
    );
    await run.settle();
    expect(calls, 1);
    expect(run.rows.first, isNotEmpty);
    run.term.type('a');
    final ended = await run.ended().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(ended, isA<WidgetError>(), reason: 'the hook did not stop the end');
    expect(calls, 2);
    final hook = run.logs.records.where(
      (r) => r.message.startsWith('onError threw'),
    );
    expect(hook, hasLength(2));
    expect(hook.first.error, isA<StateError>());
  });

  test(
    'without onError nothing is told and the app behaves as before',
    () async {
      final run = Run(Probe((_) => throw StateError('build oops')));
      await run.settle();
      expect(run.logged(LogLevel.error), hasLength(1));
      run.term.type('\x03');
      await run.ended();
    },
  );
}
