/// A session's terminal as twk_core's `Terminal` runs over it: an
/// [SshTerminalLink].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:twk_core/twk_core.dart' show TerminalException, TerminalLink;

import 'session.dart';

/// The terminal at the client's end of [session], which asked for one
/// (`pty-req`): what `Terminal.overLink` opens a terminal over.
///
/// [environment] is what the client sent, with the `TERM` of its
/// `pty-req`; [columns] and [lines] its terminal's size as it is now
/// (80 by 24 where the client sent 0, which is not known),
/// [resizes] its `window-change`s, [eraseChar] the VERASE of its modes.
/// The client keeps its terminal's modes itself (`ssh` puts the local
/// tty in raw mode), so [enterRaw], [restore] and [restoreWith] do
/// nothing, and neither does [close]: the session goes on until it
/// exits. [input] is what the client types, and ends with a
/// [TerminalException] when the client sends EOF or the session ends;
/// [add] and [flush] are the session's.
final class SshTerminalLink implements TerminalLink {
  /// The link of [session], which must have a terminal ([SshSession.pty]);
  /// an [ArgumentError] if it has none.
  SshTerminalLink(this.session)
    : _pty =
          session.pty ??
          (throw ArgumentError.value(session, 'session', 'no terminal'));

  /// The session the terminal is on.
  final SshSession session;

  /// Called at the end of [input] in place of its error, when set:
  /// `serveSsh` quits the app then, which unmounts it, rather than have it
  /// end with an error, which would leave its widgets mounted.
  @internal
  void Function()? onEnd;

  final SshPty _pty;

  SshPty get _now => session.pty ?? _pty;

  @override
  late final Map<String, String> environment = Map.unmodifiable({
    ...session.environment,
    'TERM': _pty.term,
  });

  @override
  bool get windows => false;

  // RFC 4254 §6.2: a size of 0 is not known (ssh -tt without a local
  // terminal); the terminal is then taken to be 80 by 24
  @override
  int get columns => _now.columns > 0 ? _now.columns : 80;

  @override
  int get lines => _now.rows > 0 ? _now.rows : 24;

  @override
  int? get eraseChar => _pty.eraseChar;

  @override
  late final Stream<List<int>> input = session.input.transform(
    StreamTransformer<Uint8List, List<int>>.fromHandlers(
      handleDone: (sink) {
        if (onEnd case final end?) {
          end();
        } else {
          sink.addError(
            TerminalException(
              session.isDone
                  ? 'the SSH session ended'
                  : 'the SSH client sent EOF',
            ),
          );
        }
        sink.close();
      },
    ),
  );

  @override
  Stream<void> get resizes => session.resizes;

  @override
  void enterRaw() {}

  @override
  void restore() {}

  @override
  void restoreWith(List<int> bytes) {}

  @override
  void add(List<int> bytes) => session.add(bytes);

  @override
  Future<void> flush() => session.flush();

  @override
  Future<void> close() async {}
}
