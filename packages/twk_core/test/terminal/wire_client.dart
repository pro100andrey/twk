// An app's end of the wire spoken by hand, for socket_test.dart and
// socket_wire_test.dart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:twk_core/src/terminal/socket.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show waitUntil;

/// An app's end of the wire, frame by frame.
final class WireClient {
  WireClient._(this.socket) {
    socket.listen(
      (bytes) => _reader.add(bytes),
      onError: (Object _) {},
      onDone: () {
        if (!_closed.isCompleted) {
          _closed.complete();
        }
      },
    );
  }

  static Future<WireClient> connect(LocalAddress address) async =>
      WireClient._(await address.connect());

  final Socket socket;
  late final _reader = FrameReader(
    (type, payload) => frames.add((type, payload)),
  );
  final _closed = Completer<void>();

  /// What the shell sent, in order.
  final frames = <(int, Uint8List)>[];

  /// Completes when the shell closes the connection.
  Future<void> get closed => _closed.future;

  void send(int type, [List<int> payload = const []]) =>
      socket.add(frame(type, payload));

  /// Completes once the shell has taken in everything sent before: it
  /// answers a flush after the frames that came before it.
  Future<void> sync() async {
    int answers() => frames.where((f) => f.$1 == Wire.flushed).length;
    final before = answers();
    send(Wire.flush);
    await waitUntil(() => answers() > before, 'the flush answered');
  }

  void hello(String token, {int protocol = Wire.protocol}) => socket.add(
    jsonFrame(Wire.hello, {'protocol': protocol, 'token': token}),
  );
}
