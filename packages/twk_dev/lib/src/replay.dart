/// What a recording kept of the input, and which of it is the person's:
/// [InputSplitter] tells the terminal's answers to the program's queries
/// from keys, and [replaySteps] are the keys of a recording, to be typed
/// into a live program by `twk record --replay`.
library;

import 'cast.dart';

/// A piece of input: either what a person typed (a key, a mouse report, a
/// paste, a focus change) or what the terminal said in answer to a query
/// of the program.
final class InputPiece {
  /// A piece of [text] that [isAnswer] or is not.
  const InputPiece(this.text, {required this.isAnswer});

  /// The bytes, as characters.
  final String text;

  /// Whether the terminal wrote it in answer to a query.
  final bool isAnswer;

  @override
  String toString() => '${isAnswer ? 'answer' : 'keys'} ${_show(text)}';

  static String _show(String s) =>
      s.replaceAll('\x1b', r'\e').replaceAll('\x07', r'\a');
}

/// Cuts input into [InputPiece]s: an escape sequence is an answer when a
/// person's keys never make one like it, a key otherwise.
///
/// The answers of a terminal, by their shape:
///
/// - `CSI ? … c`, `CSI > … c`, `CSI = … c`: device attributes;
/// - `CSI … $ y`: a mode report (DECRPM);
/// - `CSI ? … u`: the kitty keyboard flags (a key event of that protocol
///   has no `?`);
/// - `CSI ? … R`, and `CSI row ; column R` once the program asked for the
///   cursor position (`CSI 6 n`) and it was not answered yet: `CSI 1 ; 5
///   R` is also the modified F3, so a position nobody asked for is a key;
/// - `CSI … n` (a status report, the colour scheme), `CSI … t` (a size
///   report);
/// - a string (OSC, DCS, APC, PM, SOS) up to its terminator: a colour, the
///   terminal's name, a capability, a kitty graphics reply.
///
/// Everything else is a key: characters, `CSI A` and the other cursor keys,
/// `CSI … ~`, `CSI … u` (kitty), SS3 sequences, `CSI I` and `CSI O` (focus),
/// `CSI < … M` (mouse), and a paste (`CSI 200 ~` up to `CSI 201 ~`, its
/// content whatever it holds). An Alt+letter that opens a string is
/// indistinguishable from the answer's start: with no terminator it is
/// taken for keys when [flush]ed.
///
/// The cursor-position answers are told by the output: [sawOutput] is
/// given what the program wrote, in order.
final class InputSplitter {
  /// How much of an unfinished sequence is waited for before it is keys.
  static const maxPending = 4096;

  var _carry = '';
  var _positionAsked = 0;

  /// The start of a query the last output ended in.
  var _queryStart = '';

  /// The program wrote [text]: each cursor-position query in it makes a
  /// `CSI row ; column R` an answer, until the person types a key (an
  /// answer comes within milliseconds; a query nobody answered must not
  /// make a later modified F3 one). A query cut between two writes counts.
  void sawOutput(String text) {
    final all = '$_queryStart$text';
    _positionAsked += _positionQuery.allMatches(all).length;
    _queryStart = _queryCut.firstMatch(all)?.group(0) ?? '';
  }

  static final _positionQuery = RegExp(r'\x1b\[\??6n');
  static final _queryCut = RegExp(r'\x1b(\[\??6?)?$');

  /// The pieces in [text] after what [add] kept of the one before; what is
  /// the start of a sequence only is kept for the next call.
  List<InputPiece> add(String text) => _split(_carry + text, flush: false);

  /// What [add] kept, as keys.
  List<InputPiece> flush() => _split(_carry, flush: true);

  /// What is kept: the start of a sequence.
  String get pending => _carry;

  List<InputPiece> _split(String s, {required bool flush}) {
    _carry = '';
    final out = <InputPiece>[];
    var keyed = false;
    void emit(String text, bool answer) {
      keyed |= !answer;
      if (out.isNotEmpty && out.last.isAnswer == answer) {
        out[out.length - 1] = InputPiece(
          out.last.text + text,
          isAnswer: answer,
        );
      } else {
        out.add(InputPiece(text, isAnswer: answer));
      }
    }

    var i = 0;
    while (i < s.length) {
      if (s.codeUnitAt(i) != 0x1b) {
        emit(s[i], false);
        i++;
        continue;
      }
      final r = _sequence(s, i);
      if (r == null) {
        // not finished
        if (!flush && s.length - i <= maxPending) {
          _carry = s.substring(i);
          if (keyed) {
            _positionAsked = 0;
          }
          return out;
        }
        emit(s.substring(i), false);
        if (keyed) {
          _positionAsked = 0;
        }
        return out;
      }
      emit(s.substring(i, r.end), r.answer);
      i = r.end;
    }
    if (keyed) {
      // the queries before a key are given up
      _positionAsked = 0;
    }
    return out;
  }

  /// The sequence that starts at [i], an Escape; null when [s] ends in it.
  ({int end, bool answer})? _sequence(String s, int i) {
    if (i + 1 >= s.length) {
      return null;
    }
    final c = s.codeUnitAt(i + 1);
    switch (c) {
      case 0x5b: // [
        return _csi(s, i);
      case 0x5d || 0x50 || 0x5f || 0x5e || 0x58: // ] P _ ^ X
        for (var j = i + 2; j < s.length; j++) {
          final u = s.codeUnitAt(j);
          if (u == 0x07 && c == 0x5d) {
            return (end: j + 1, answer: true);
          }
          if (u == 0x1b) {
            if (j + 1 >= s.length) {
              return null;
            }
            // ST ends it; any other Escape is a key's, and it was not one
            return s.codeUnitAt(j + 1) == 0x5c
                ? (end: j + 2, answer: true)
                : (end: i + 2, answer: false);
          }
        }
        return null;
      case 0x4f: // O: SS3 and a letter
        return i + 2 >= s.length ? null : (end: i + 3, answer: false);
      default:
        // Alt and a key
        return (end: i + 2, answer: false);
    }
  }

  ({int end, bool answer})? _csi(String s, int i) {
    var j = i + 2;
    while (j < s.length && _inRange(s.codeUnitAt(j), 0x30, 0x3f)) {
      j++;
    }
    final paramsEnd = j;
    while (j < s.length && _inRange(s.codeUnitAt(j), 0x20, 0x2f)) {
      j++;
    }
    if (j >= s.length) {
      return null;
    }
    final last = s.codeUnitAt(j);
    if (!_inRange(last, 0x40, 0x7e)) {
      // not a sequence: the Escape and the bracket are keys
      return (end: i + 2, answer: false);
    }
    final params = s.substring(i + 2, paramsEnd);
    final intermediates = s.substring(paramsEnd, j);
    final end = j + 1;
    final marker = params.isEmpty ? '' : params[0];
    final private = marker == '?' || marker == '>' || marker == '=';
    final f = String.fromCharCode(last);
    if (f == '~' && params == '200' && intermediates.isEmpty) {
      // a paste: its content is the person's
      final close = s.indexOf('\x1b[201~', end);
      return close < 0 ? null : (end: close + 6, answer: false);
    }
    final answer = switch (f) {
      'c' => private,
      'y' => intermediates == r'$',
      'u' => marker == '?',
      'R' =>
        marker == '?' ||
            (_positionAsked > 0 && _positionAnswer.hasMatch(params)),
      'n' || 't' => intermediates.isEmpty,
      _ => false,
    };
    if (answer && f == 'R' && marker != '?') {
      _positionAsked--;
    }
    return (end: end, answer: answer);
  }

  static final _positionAnswer = RegExp(r'^\d+;\d+$');

  static bool _inRange(int c, int lo, int hi) => c >= lo && c <= hi;
}

/// A time at which the keys of a recording were typed.
///
/// `reacts` is whether the recorded program wrote something after the keys
/// and before the next ones in the order of the recording's events (not by
/// their times alone, which can be equal).
typedef ReplayStep = ({double time, String keys, bool reacts});

/// The keys of [cast], the input events with the terminal's answers taken
/// out ([InputSplitter]), each at its time; the events that were answers
/// only are left out.
List<ReplayStep> replaySteps(Cast cast) {
  final splitter = InputSplitter();
  final steps = <ReplayStep>[];
  var reacts = false;
  void close() {
    if (steps.isNotEmpty && reacts) {
      steps[steps.length - 1] = (
        time: steps.last.time,
        keys: steps.last.keys,
        reacts: true,
      );
    }
    reacts = false;
  }

  for (final event in cast.events) {
    switch (event.code) {
      case CastEvent.output:
        splitter.sawOutput(event.data);
        // by the order of the events, not their times (they are rounded: a
        // reaction can carry its key's time): output after a key and before
        // the next is the first one's
        if (steps.isNotEmpty) {
          reacts = true;
        }
      case CastEvent.input:
        final keys = [
          for (final piece in splitter.add(event.data))
            if (!piece.isAnswer) piece.text,
        ].join();
        if (keys.isNotEmpty) {
          close();
          steps.add((time: event.time, keys: keys, reacts: false));
        }
    }
  }
  final rest = [
    for (final piece in splitter.flush())
      if (!piece.isAnswer) piece.text,
  ].join();
  close();
  if (rest.isNotEmpty) {
    steps.add((time: cast.duration, keys: rest, reacts: false));
  }
  return steps;
}
