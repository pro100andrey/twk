// The fakes of the four ports, for the core's tests.
import 'dart:async';
import 'dart:typed_data';

import 'package:twk_core/twk_core.dart' show KeyEvent, MouseEvent;
import 'package:twk_driver/twk_driver.dart';

/// A terminal whose output the test writes and whose input it reads.
final class FakeTerminal implements TerminalPort {
  final _out = StreamController<Uint8List>();

  /// What the driver wrote, one list a write.
  final writes = <List<int>>[];

  /// The sizes it was set to.
  final sizes = <(int, int)>[];

  @override
  bool? nlToCrNl = true;

  @override
  Uint8List? modesAtEnd;

  @override
  Stream<Uint8List> get output => _out.stream;

  /// What the app writes.
  void app(String text) => _out.add(Uint8List.fromList(text.codeUnits));

  /// The end of the terminal's output.
  Future<void> endOutput() => _out.close();

  @override
  void write(List<int> bytes) => writes.add(bytes);

  @override
  void resize(int width, int height) => sizes.add((width, height));
}

/// A launched program.
final class FakeLaunched implements Launched {
  @override
  // the type is the fake's, which the interface's would hide from a test
  // ignore: omit_obvious_property_types
  final FakeTerminal terminal = FakeTerminal();

  final _exit = Completer<int?>();

  @override
  Future<int?> get exitCode => _exit.future;

  @override
  Future<Uri> get serviceUri async => Uri.parse('http://fake/');

  /// Whether the program was killed.
  var killed = false;

  /// Ends the program with [code] and its terminal after it.
  Future<void> exit(int code) async {
    _exit.complete(code);
    await terminal.endOutput();
  }

  @override
  Future<void> kill() async {
    killed = true;
    if (!_exit.isCompleted) {
      _exit.complete(-15);
      await terminal.endOutput();
    }
  }
}

/// A process port that launches one [launched].
final class FakeProcess implements ProcessPort {
  /// The program it starts.
  final launched = FakeLaunched();

  @override
  Future<Launched> spawn(ProcessSpec spec) async => launched;
}

/// A VM service of canned answers.
final class FakeService implements AppServicePort {
  final _events = StreamController<AppEvent>.broadcast();
  final _done = Completer<void>();

  /// The calls, `method params` each.
  final calls = <String>[];

  /// The frames the app has run, as `status` says.
  var frames = 0;

  /// The bytes the app has written, as `status` says.
  var statusWritten = 0;

  /// What a method answers.
  final answers = <String, Json Function(Map<String, String>)>{};

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    calls.add('$method $params');
    final answer = answers[method];
    if (answer != null) {
      return answer(params);
    }
    return switch (method) {
      'status' => {
        'version': 1,
        'frame': frames,
        'quitting': false,
        'size': {'width': 80, 'height': 24},
        'inputRead': 0,
        'outputWritten': statusWritten,
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

  /// The app posts `twk.frame`.
  void frame({
    required int frame,
    required int inputRead,
    required int outputWritten,
    bool drawn = true,
    int width = 80,
    int height = 24,
    bool inputPending = false,
    bool scheduled = false,
    bool quitting = false,
  }) => _post('twk.frame', {
    'quitting': quitting,
    'frame': frame,
    'drawn': drawn,
    'inputRead': inputRead,
    'outputWritten': outputWritten,
    'width': width,
    'height': height,
    'inputPending': inputPending,
    'scheduled': scheduled,
  });

  /// The app posts `twk.input`.
  void input({
    required int frame,
    required int inputRead,
    required int outputWritten,
    int width = 80,
    int height = 24,
    bool inputPending = false,
    bool scheduled = false,
    bool quitting = false,
  }) => _post('twk.input', {
    'quitting': quitting,
    'frame': frame,
    'drawn': false,
    'inputRead': inputRead,
    'outputWritten': outputWritten,
    'width': width,
    'height': height,
    'inputPending': inputPending,
    'scheduled': scheduled,
  });

  void _post(String kind, Map<String, Object?> d) => _events.add(
    AppEvent(kind, {
      'version': 1,
      'frame': d['frame'],
      'drawn': d['drawn'],
      'size': {'width': d['width'], 'height': d['height']},
      'inputRead': d['inputRead'],
      'outputWritten': d['outputWritten'],
      'inputPending': d['inputPending'],
      'scheduled': d['scheduled'],
      'frameDue': null,
      'time': 0,
      'nextDue': null,
      'quitting': d['quitting'] ?? false,
    }),
  );
}

/// A screen that records what the frame emulator took and answers the
/// queries `?` of the app with `!`.
final class FakeScreen implements ScreenPort {
  /// What the answering emulator took.
  final answering = StringBuffer();

  /// What the frame emulator took, a piece for each feed.
  final frames = <String>[];

  void Function(Uint8List)? _answer;

  /// Whether the app tracks the mouse.
  @override
  var mouseTracked = true;

  @override
  void answerTo(void Function(Uint8List bytes)? sink) => _answer = sink;

  @override
  void feedAnswering(List<int> bytes) {
    final text = String.fromCharCodes(bytes);
    answering.write(text);
    for (final _ in '?'.allMatches(text)) {
      _answer?.call(Uint8List.fromList('!'.codeUnits));
    }
  }

  @override
  void feedFrame(List<int> bytes) => frames.add(String.fromCharCodes(bytes));

  /// The size the frame emulator was set to last.
  var frameSize = (80, 24);

  /// The size the answering emulator was set to last.
  var answeringSize = (80, 24);

  @override
  ScreenView get frame => _View(this);

  @override
  Uint8List encodeKey(KeyEvent key) => Uint8List.fromList(
    '<${key.char.isEmpty ? key.code.name : key.char}>'.codeUnits,
  );

  @override
  Uint8List encodeText(String text) => Uint8List.fromList(text.codeUnits);

  @override
  Uint8List encodePaste(String text) => Uint8List.fromList('[$text]'.codeUnits);

  @override
  Uint8List encodeMouse(MouseEvent event) => Uint8List.fromList(
    '{${event.kind.name} ${event.x},${event.y}}'.codeUnits,
  );

  @override
  void resizeAnswering(int width, int height) =>
      answeringSize = (width, height);

  @override
  void resizeFrame(int width, int height) => frameSize = (width, height);
}

final class _View implements ScreenView {
  _View(this._screen);

  final FakeScreen _screen;

  @override
  String get text => _screen.frames.join();

  @override
  int get width => _screen.frameSize.$1;

  @override
  int get height => _screen.frameSize.$2;

  @override
  String line(int y) => y == 0 ? text : '';

  @override
  bool isContinuation(int x, int y) => false;

  @override
  int get cursorX => 0;

  @override
  int get cursorY => 0;

  @override
  bool get cursorVisible => true;

  @override
  bool get alternateScreen => true;
}
