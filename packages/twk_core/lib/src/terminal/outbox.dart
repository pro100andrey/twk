/// Bytes on their way to the terminal.
///
/// dart:io rejects writes to stdout, and further flushes, while a flush is
/// pending ("StreamSink is bound to a stream"). The frame loop awaits each
/// flush, but a title, the clipboard or the exit sequence may be written in
/// the same microtasks: such bytes wait here, in order, and flushes run one
/// at a time.
///
/// A frame is copied into one buffer reused from frame to frame, so the
/// caller's buffer is free as soon as `Outbox.frame` returns and a frame
/// makes no garbage. The buffer is reused only after the flush that carried
/// it completed; a frame written before that gets a copy of its own.
library;

import 'dart:typed_data';

/// The bytes on their way to a terminal's sink: written in order, one
/// flush at a time, with what is written during a flush held back until it
/// completes.
///
/// `Terminal` writes everything through one: the frames ([frame]), copied
/// into a buffer it reuses, and its own sequences ([add]).
final class Outbox {
  /// An outbox to a sink that [add] writes to and [flush] flushes
  /// (`stdout.add`, `stdout.flush`).
  Outbox(this._add, this._flush);

  final void Function(List<int> bytes) _add;
  final Future<void> Function() _flush;

  var _flushing = false;
  final _queued = <List<int>>[];
  var _flushed = Future<void>.value();

  var _staging = Uint8List(1 << 14);
  var _stagingView = Uint8List(0); // onto _staging, as long as the last frame

  /// The staging buffer was handed to the sink and no flush completed
  /// since: it may still be on its way.
  var _stagingInFlight = false;

  /// Sends [bytes], which the outbox keeps (hand it a list nothing else
  /// writes to).
  void add(List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    if (_flushing) {
      _queued.add(bytes);
    } else {
      _add(bytes);
    }
  }

  /// Sends a copy of [bytes]: the caller may reuse its buffer at once.
  void frame(Uint8List bytes) {
    if (bytes.isEmpty) {
      return;
    }
    if (_flushing || _stagingInFlight) {
      // the staging buffer may still be on its way: a copy of its own
      add(Uint8List.fromList(bytes));
      return;
    }
    final n = bytes.length;
    if (_staging.length < n) {
      _staging = Uint8List(n * 2);
      _stagingView = Uint8List(0);
    }
    _staging.setRange(0, n, bytes);
    if (_stagingView.length != n) {
      _stagingView = Uint8List.sublistView(_staging, 0, n);
    }
    _stagingInFlight = true;
    _add(_stagingView);
  }

  /// Completes when everything sent so far reached the OS.
  Future<void> flush() {
    if (_flushing) {
      // one at a time; this one also covers what was queued meanwhile
      return _flushed = _flushed.then((_) => flush());
    }
    _flushing = true;
    return _flushed = _flush().whenComplete(() {
      _flushing = false;
      _stagingInFlight = false;
      _queued
        ..forEach(_add)
        ..clear();
    });
  }
}
