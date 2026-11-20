// `twk tape` on fake ports, its clock moved by the test: Wait Widget and
// Wait Text look at the app's tree when the step starts and after each frame
// the app draws, never on a timer of the tape's clock; Click Key taps the
// widget with that key and says why it cannot.
import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_dev/src/tape.dart';
import 'package:twk_driver/twk_driver.dart';

/// What the app has written when the session starts: its first screen, on
/// the alternate screen, the mouse tracked.
const _start = '\x1b[?1049h\x1b[?1000h\x1b[?1006hstart';

final class _Terminal implements TerminalPort {
  final _out = StreamController<Uint8List>();
  final writes = <String>[];

  @override
  bool? get nlToCrNl => true;

  @override
  Uint8List? get modesAtEnd => null;

  @override
  Stream<Uint8List> get output => _out.stream;

  void app(String text) => _out.add(Uint8List.fromList(text.codeUnits));

  @override
  void write(List<int> bytes) => writes.add(String.fromCharCodes(bytes));

  @override
  void resize(int width, int height) {}
}

final class _Launched implements Launched {
  @override
  // the fake's type, which the interface's would hide from the test
  // ignore: omit_obvious_property_types
  final _Terminal terminal = _Terminal();
  final _exit = Completer<int?>();

  @override
  Future<int?> get exitCode => _exit.future;

  @override
  Future<Uri> get serviceUri async => Uri.parse('http://fake/');

  @override
  Future<void> kill() async {
    if (!_exit.isCompleted) {
      _exit.complete(-15);
      await terminal._out.close();
    }
  }
}

final class _Process implements ProcessPort {
  final launched = _Launched();

  @override
  Future<Launched> spawn(ProcessSpec spec) async => launched;
}

/// An app service whose `find` and `hitTest` the test answers.
final class _Service implements AppServicePort {
  final _events = StreamController<AppEvent>.broadcast();
  final _done = Completer<void>();
  final calls = <String>[];
  final answers = <String, Json Function(Map<String, String>)>{};
  var frames = 1;
  int written = _start.length;
  var inputRead = 0;

  int get finds => calls.where((c) => c.startsWith('find ')).length;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    calls.add('$method $params');
    if (answers[method] case final answer?) {
      return answer(params);
    }
    return switch (method) {
      'status' => {
        'version': 1,
        'frame': frames,
        'quitting': false,
        'size': {'width': 30, 'height': 6},
        'inputRead': inputRead,
        'outputWritten': written,
        'inputPending': false,
        'scheduled': false,
        'frameDue': null,
        'time': 0,
        'nextDue': null,
      },
      'find' => {
        'version': 1,
        'frame': frames,
        'count': 0,
        'matches': <Object>[],
      },
      _ => {'version': 1},
    };
  }

  /// The app draws [text] and posts the frame that ends with it.
  void frame(_Terminal terminal, String text) {
    terminal.app(text);
    frames++;
    written += text.length;
    _events.add(
      AppEvent('twk.frame', {
        'version': 1,
        'frame': frames,
        'drawn': true,
        'size': {'width': 30, 'height': 6},
        'inputRead': inputRead,
        'outputWritten': written,
        'inputPending': false,
        'scheduled': false,
        'frameDue': null,
        'time': 0,
        'nextDue': null,
        'quitting': false,
      }),
    );
  }

  @override
  Stream<AppEvent> get events => _events.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

Json _found(List<Json> matches) => {
  'version': 1,
  'frame': 1,
  'count': matches.length,
  'matches': matches,
};

Json _node(int id, {String? key}) => {
  'id': id,
  'type': 'Button',
  'key': key,
  'text': null,
  'rect': {'x': 4, 'y': 2, 'width': 8, 'height': 1},
  'shown': {'x': 4, 'y': 2, 'width': 8, 'height': 1},
};

void main() {
  late _Process process;
  late _Service service;
  late _Clock clock;
  late List<String> said;
  late List<String> reported;

  setUp(() {
    process = _Process();
    service = _Service();
    clock = _Clock();
    said = [];
    reported = [];
    process.launched.terminal.app(_start);
  });

  /// Starts the tape [body] on the fakes; its exit code.
  Future<int> start(String body) {
    final runner = TapeRunner(
      Tape.parse(
        'Set Width 30\nSet Height 6\nSet WaitTimeout 60s\n'
        'Run dart app.dart\n$body',
        name: 't.tape',
      ),
      check: true,
      clock: clock,
      log: said.add,
      report: reported.add,
      program: process,
      connect: (_) async => service,
    );
    final ran = runner.run();
    addTearDown(() async {
      runner.stop(130);
      await ran;
    });
    return ran;
  }

  test(
    'Wait Widget asks the tree once, then after each frame: it ends on '
    'the frame that shows the widget, and time passing asks nothing',
    () async {
      var shown = false;
      service.answers['find'] = (_) => _found([if (shown) _node(7)]);
      final ran = start('Wait Widget Button\n');
      await pumpEventQueue();
      expect(service.finds, 1);
      clock.advance(const Duration(seconds: 10));
      await pumpEventQueue();
      expect(
        service.finds,
        1,
        reason: 'the tape clock moving is no reason to look at the tree',
      );

      // a frame that does not show it: looked at again, still waiting
      service.frame(process.launched.terminal, '.');
      await pumpEventQueue();
      expect(service.finds, 2);
      expect(reported.where((r) => r.contains('Wait Widget')), isEmpty);

      shown = true;
      service.frame(process.launched.terminal, '!');
      expect(await ran, 0, reason: '$said');
      expect(service.finds, 3);
      expect(reported, [
        't.tape:3: ok Set WaitTimeout 60s',
        't.tape:5: ok Wait Widget Button',
        't.tape: passed, 2 statements',
      ]);
    },
  );

  test('Wait Text that no frame shows fails on the tape clock, with the '
      'screen', () async {
    service.answers['find'] = (_) => _found([]);
    final ran = start('Wait@5s Text "Saved"\n');
    await pumpEventQueue();
    clock.advance(const Duration(seconds: 5));
    expect(await ran, 1);
    expect(
      said.single,
      startsWith(
        'twk tape: t.tape:5: Wait timed out after '
        '5.0s for Text "Saved"; the screen:',
      ),
    );
    expect(said.single, contains('start'));
  });

  test('Click Key taps the widget with that key, a bare number is an int '
      'key', () async {
    service.answers['find'] = (params) => _found([_node(7, key: 'save')]);
    service.answers['hitTest'] = (_) => {
      'version': 1,
      'frame': 1,
      'takenBy': null,
      'path': [
        {'id': 7, 'type': 'Button', 'render': 8},
      ],
      'listeners': [
        {
          'render': 8,
          'type': 'Listener',
          'callbacks': ['down', 'up'],
        },
      ],
      'absorbedBy': null,
    };
    final ran = start('Click Key "save"\nClick Key 3\n');
    // each press and each release waits for the frame that has read it
    final terminal = process.launched.terminal;
    var done = false;
    unawaited(ran.whenComplete(() => done = true));
    for (var i = 0; i < 100 && !done; i++) {
      await pumpEventQueue();
      // the typing speed after a click
      clock.advance(const Duration(milliseconds: 60));
      final written = terminal.writes.fold(0, (n, w) => n + w.length);
      if (written > service.inputRead) {
        service
          ..inputRead = written
          ..frame(terminal, '.');
      }
    }
    expect(await ran, 0, reason: '$said');
    expect(
      service.calls.where((c) => c.startsWith('find')),
      containsAllInOrder([
        contains('{"key":{"value":"save"}}'),
        contains('{"key":{"value":3}}'),
      ]),
    );
    expect(
      process.launched.terminal.writes.where((w) => w.contains('\x1b[<0;')),
      hasLength(4),
      reason: 'a press and a release for each',
    );
    expect(
      reported,
      containsAllInOrder([
        't.tape:5: ok Click Key "save"',
        't.tape:6: ok Click Key 3',
      ]),
    );
  });

  test('a key the tape parser accepts and the key bindings do not name '
      '(Shift+Space, Shift+1) is pressed by its event: the app gets its '
      'bytes', () async {
    final ran = start('Shift+Space\nShift+1\n');
    final terminal = process.launched.terminal;
    var done = false;
    unawaited(ran.whenComplete(() => done = true));
    for (var i = 0; i < 100 && !done; i++) {
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 60));
      final written = terminal.writes.fold(0, (n, w) => n + w.length);
      if (written > service.inputRead) {
        service
          ..inputRead = written
          ..frame(terminal, '.');
      }
    }
    expect(await ran, 0, reason: '$said');
    expect(terminal.writes, [' ', '1']);
  });

  test('Click Key of a key the tree lacks fails the tape, saying what it '
      'found', () async {
    service.answers['find'] = (_) => _found([]);
    final ran = start('Click Key "nope"\n');
    expect(await ran, 1);
    expect(
      said.single,
      allOf(
        startsWith('twk tape: t.tape:5: Click Key "nope": '),
        contains('the finder matches nothing'),
      ),
    );
    expect(process.launched.terminal.writes, isEmpty);
  });
}

/// Time the test moves: pauses and alarms are over when [advance] reaches
/// them.
final class _Clock extends TapeClock {
  Duration _now = Duration.zero;
  final _alarms = <_Alarm>[];

  @override
  Duration get elapsed => _now;

  @override
  Future<void> pause(Duration duration, Future<void> stop) {
    final done = Completer<void>();
    final alarm = timer(duration, done.complete);
    return Future.any([done.future, stop]).whenComplete(alarm.cancel);
  }

  @override
  Timer timer(Duration after, void Function() callback) {
    final alarm = _Alarm(_now + after, callback);
    _alarms.add(alarm);
    return alarm;
  }

  /// Moves time by [by]; the alarms due by then go off, in order.
  void advance(Duration by) {
    _now += by;
    final due = [..._alarms.where((a) => a.active && a.due <= _now)]
      ..sort((a, b) => a.due.compareTo(b.due));
    for (final alarm in due) {
      alarm.fire();
    }
    _alarms.removeWhere((a) => !a.active);
  }
}

final class _Alarm implements Timer {
  _Alarm(this.due, this._callback);

  final Duration due;
  final void Function() _callback;

  var active = true;

  @override
  bool get isActive => active;

  void fire() {
    if (active) {
      active = false;
      _callback();
    }
  }

  @override
  void cancel() => active = false;

  @override
  int get tick => 0;
}
