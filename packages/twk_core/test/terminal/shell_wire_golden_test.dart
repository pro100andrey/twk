// The wire of socket.dart held to shell_wire.golden.json, the description
// of it the VS Code extension's tests hold its second implementation
// (editors/vscode/src/core/wire.ts, shell.ts) to as well: the kinds and
// their types, each frame's bytes, and conversations a TerminalShell and
// a SocketLink are taken through, byte for byte. A change to the wire
// here that is not made in the golden fails this test; made in the
// golden, it fails the extension's until it follows.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/link.dart' show TerminalDeclaration;
import 'package:twk_core/src/terminal/socket.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show waitFor, waitUntil;

import 'fake_link.dart';
import 'wire_client.dart';

/// Where the golden is, from the package's directory.
const goldenPath = 'test/terminal/shell_wire.golden.json';

typedef Json = Map<String, Object?>;

final golden = jsonDecode(File(goldenPath).readAsStringSync()) as Json;

List<Json> listOf(Json json, String key) =>
    (json[key]! as List<Object?>).cast<Json>();

final Map<String, Json> kinds = {
  for (final k in listOf(golden, 'kinds')) k['name']! as String: k,
};

final Map<String, Json> frames = {
  for (final f in listOf(golden, 'frames')) f['name']! as String: f,
};

/// The bytes of [hex] as the golden writes them: `type length payload`.
Uint8List bytesOf(String hex) {
  final digits = hex.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < digits.length; i += 2)
      int.parse(digits.substring(i, i + 2), radix: 16),
  ]);
}

/// [bytes] in hex, two digits each.
String hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// [bytes] as the golden writes a frame.
String hexOf(List<int> bytes) => [
  hex(bytes.take(1)),
  hex(bytes.skip(1).take(4)),
  if (bytes.length > 5) hex(bytes.skip(5)),
].join(' ');

/// The type of the golden frame [f].
int typeOf(Json f) =>
    (f['type'] as int?) ?? kinds[f['kind']! as String]!['type']! as int;

/// The frame named [name], as bytes.
Uint8List frameBytes(String name) =>
    bytesOf(frames[name]?['hex'] as String? ?? fail('no frame "$name"'));

/// The golden frame [f] made with this side's [frame] and [jsonFrame].
Uint8List encode(Json f) {
  final type = typeOf(f);
  if (f.containsKey('json')) {
    return jsonFrame(type, f['json']!);
  }
  if (f.containsKey('bytes')) {
    return frame(type, bytesOf(f['bytes']! as String));
  }
  return frame(type, utf8.encode(f['text']! as String));
}

/// What the payload of [f] says, decoded as the golden writes it.
Object? decode(Json f, Uint8List payload) {
  if (f.containsKey('json')) {
    return jsonDecode(utf8.decode(payload));
  }
  if (f.containsKey('bytes')) {
    return hex(payload);
  }
  return utf8.decode(payload);
}

/// The value [f] decodes to.
Object? decoded(Json f) => f['json'] ?? f['bytes'] ?? f['text'];

/// The token of the golden's hello.
String get token => (frames['hello']!['json']! as Json)['token']! as String;

/// The terminal of the golden's welcome.
Json get welcome => frames['welcome']!['json']! as Json;

/// The frames' types socket.dart's [Wire] declares, read from its source:
/// a kind added there and not to the golden fails, as one left out.
Map<String, String> declaredInSource() {
  final source = File('lib/src/terminal/socket.dart').readAsStringSync();
  final body = RegExp(
    r'abstract final class Wire \{(.*?)\n\}',
    dotAll: true,
  ).firstMatch(source)![1]!;
  return {
    for (final m in RegExp(
      r'static const (?:int )?(\w+) = ([^;]+);',
    ).allMatches(body))
      m[1]!: m[2]!,
  };
}

/// [Wire]'s kinds by name.
const Map<String, int> wireKinds = {
  'hello': Wire.hello,
  'output': Wire.output,
  'flush': Wire.flush,
  'lost': Wire.lost,
  'raw': Wire.raw,
  'welcome': Wire.welcome,
  'refused': Wire.refused,
  'input': Wire.input,
  'size': Wire.size,
  'flushed': Wire.flushed,
};

/// Plays the app's side of a `side: shell` conversation against a
/// [TerminalShell] serving a [FakeLink] of the golden's welcome.
Future<void> playShell(Json conversation, Directory dir) async {
  final environment = (welcome['environment']! as Json).map(
    (k, v) => MapEntry(k, v! as String),
  );
  final declaration = TerminalDeclaration.fromJson(welcome['declares']);
  // all of it taken: nothing of the golden's declares is lost on the way
  expect(declaration.toJson(), welcome['declares'] ?? isEmpty);
  final link = FakeLink(
    columns: welcome['columns']! as int,
    lines: welcome['lines']! as int,
    environment: environment,
    declaration: declaration,
  );
  // the welcome's other fields are FakeLink's
  expect(welcome['eraseChar'], link.eraseChar);
  expect(welcome['windows'], link.windows);
  final (server, bound) = await LocalAddress.bind(dir.path, 'shell');
  final shell = TerminalShell.serve(
    link,
    server,
    LocalAddress(bound.address, bound.port, token),
  );
  addTearDown(() async {
    await shell.stop();
    bound.unlink();
  });
  final apps = <int, WireClient>{};
  final seen = <int, int>{};
  final closed = <int>{};
  Future<WireClient> app(int by) async {
    final existing = apps[by];
    if (existing != null) {
      return existing;
    }
    final client = await WireClient.connect(shell.address);
    unawaited(client.closed.then((_) => closed.add(by)));
    seen[by] = 0;
    return apps[by] = client;
  }

  for (final step in listOf(conversation, 'steps')) {
    final by = step['by'] as int? ?? 1;
    final what = 'step $step';
    switch (step) {
      case {'sends': final String name}:
        (await app(by)).socket.add(frameBytes(name));
      case {'gets': final String name}:
        final client = await app(by);
        await waitUntil(() => client.frames.length > seen[by]!, what);
        final (type, payload) = client.frames[seen[by]!];
        seen[by] = seen[by]! + 1;
        expect(
          hexOf(frame(type, payload)),
          frames[name]!['hex'],
          reason: '$what: the shell sent another frame',
        );
      case {'closed': true}:
        await app(by);
        await waitUntil(() => closed.contains(by), what);
      case {'closes': true}:
        (await app(by)).socket.destroy();
      case {'types': final String text}:
        link.type(text);
      case {'resizes': [final int columns, final int lines]}:
        link.resize(columns, lines);
      case {'shows': final String text}:
        await waitUntil(() => link.text == text, '$what, got "${link.text}"');
      default:
        fail('a step of no kind: $step');
    }
  }
  for (final MapEntry(key: by, value: client) in apps.entries) {
    expect(
      [for (final (t, p) in client.frames.skip(seen[by]!)) hexOf(frame(t, p))],
      isEmpty,
      reason: 'app $by got frames the conversation does not name',
    );
    client.socket.destroy();
  }
}

/// Plays the shell's side of a `side: app` conversation against a
/// [SocketLink].
Future<void> playApp(Json conversation, Directory dir) async {
  final (server, bound) = await LocalAddress.bind(dir.path, 'shell');
  addTearDown(() async {
    await server.close();
    bound.unlink();
  });
  final accepted = Completer<Socket>();
  final got = <(int, Uint8List)>[];
  var closed = false;
  server.listen((socket) {
    accepted.complete(socket);
    final reader = FrameReader((t, p) => got.add((t, p)));
    socket.listen(reader.add, onDone: () => closed = true);
  });
  final connecting = SocketLink.connect(
    LocalAddress(bound.address, bound.port, token),
  );
  SocketLink? link;
  final read = BytesBuilder();
  Future<void>? flushing;
  var flushed = false;
  var seen = 0;
  for (final step in listOf(conversation, 'steps')) {
    final what = 'step $step';
    switch (step) {
      case {'gets': final String name}:
        await waitUntil(() => got.length > seen, what);
        final (type, payload) = got[seen++];
        expect(
          hexOf(frame(type, payload)),
          frames[name]!['hex'],
          reason: '$what: the link sent another frame',
        );
      case {'sends': final String name}:
        (await waitFor(accepted.future, 'the link to connect')).add(
          frameBytes(name),
        );
        if (name == 'welcome') {
          final l = await waitFor(connecting, 'the link welcomed');
          link = l;
          l.input.listen(read.add, onError: (Object _) {});
          expect(
            {
              'columns': l.columns,
              'lines': l.lines,
              'eraseChar': l.eraseChar,
              'windows': l.windows,
              'environment': l.environment,
              if (!l.declaration.isEmpty) 'declares': l.declaration.toJson(),
            },
            welcome,
            reason: 'the link takes the welcome as it says',
          );
        }
      case {'link': final String action}:
        final l = link ?? fail('$what before the welcome');
        switch (action) {
          case 'enterRaw':
            l.enterRaw();
          case 'restore':
            l.restore();
          case 'add':
            l.add(utf8.encode(step['text']! as String));
          case 'restoreWith':
            l.restoreWith(utf8.encode(step['text']! as String));
          case 'flush':
            flushing = l.flush().then((_) => flushed = true);
          case 'close':
            await waitFor(l.close(), 'the link closed');
          default:
            fail('no such link action: $step');
        }
      case {'reads': final String text}:
        await waitUntil(() => utf8.decode(read.toBytes()) == text, what);
      case {'sized': [final int columns, final int lines]}:
        await waitUntil(
          () => link?.columns == columns && link?.lines == lines,
          what,
        );
      case {'closed': true}:
        await waitUntil(() => closed, what);
      default:
        fail('a step of no kind: $step');
    }
  }
  if (accepted.isCompleted) {
    (await accepted.future).destroy();
  }
  if (flushing != null) {
    await waitUntil(() => flushed, 'the flush answered');
  }
  expect(
    [for (final (t, p) in got.skip(seen)) hexOf(frame(t, p))],
    isEmpty,
    reason: 'the link sent frames the conversation does not name',
  );
}

void main() {
  test('the golden names the protocol and the longest payload', () {
    expect(golden['protocol'], Wire.protocol);
    expect(golden['maxPayload'], Wire.maxPayload);
  });

  test("the golden's kinds are Wire's, of its types, none left out", () {
    expect(declaredInSource().keys.toSet(), {
      ...wireKinds.keys,
      'protocol',
      'maxPayload',
    }, reason: 'Wire declares a kind wireKinds and the golden lack');
    expect(
      {for (final MapEntry(:key, :value) in kinds.entries) key: value['type']},
      wireKinds,
    );
  });

  group('each frame', () {
    for (final f in frames.values) {
      final name = f['name']! as String;
      final bytes = bytesOf(f['hex']! as String);
      if (f.containsKey('header')) {
        test('"$name": its header is refused by a FrameReader', () {
          expect(bytes.length, 5);
          expect(
            () => FrameReader((_, _) => fail('a frame')).add(bytes),
            throwsFormatException,
          );
        });
        continue;
      }
      test('"$name": made by frame/jsonFrame, read back by a FrameReader '
          'a byte at a time', () {
        expect(hexOf(encode(f)), f['hex'], reason: 'as this side makes it');
        final read = <(int, Uint8List)>[];
        final reader = FrameReader((t, p) => read.add((t, p)));
        for (final b in bytes) {
          reader.add([b]);
        }
        expect(read, hasLength(1));
        expect(read.single.$1, typeOf(f));
        expect(decode(f, read.single.$2), decoded(f));
      });
    }
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_golden'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('conversation', () {
    for (final c in listOf(golden, 'conversations')) {
      test(
        '"${c['name']}" (${c['side']} side): ${c['description']}',
        () => switch (c['side']) {
          'shell' => playShell(c, dir),
          'app' => playApp(c, dir),
          final side => fail('no side $side'),
        },
      );
    }
  });
}
