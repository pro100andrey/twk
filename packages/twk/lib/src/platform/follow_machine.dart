/// When a followed file started over, and what to read of it: the decision
/// `tailFile` makes, apart from the file, the directory watch and the timer
/// that feed it.
library;

/// What a look at a followed file asks to be done ([FollowMachine.look]):
/// first the [reset], if any, then the read of the range, if any.
final class FollowPlan {
  /// A plan: [reset] the reader, then read bytes [from] to [to] when [to]
  /// is past [from].
  const FollowPlan({required this.reset, this.from = 0, this.to = 0});

  /// Whether the file started over: what was read of it before is of
  /// another file, and the next read is from its start.
  final bool reset;

  /// Where the range to read starts.
  final int from;

  /// Where the range to read ends (exclusive).
  final int to;

  /// Whether there is a range to read.
  bool get reads => to > from;

  @override
  String toString() =>
      'FollowPlan(reset: $reset, read: ${reads ? '$from-$to' : 'none'})';
}

/// The state of a followed file as the machine knows it: how far it was
/// read, and what says that the file at the name is not the one that was.
/// A stat and an event go in, a [FollowPlan] comes out; nothing here
/// touches a file, a watch or a clock.
///
/// The inputs come in whatever order the system delivers them. A look
/// ([look]) tells the file as it was when its stat was taken, an event
/// ([nameEvent]) tells a change when it was made, and the two reach the
/// machine in either order; [beginLook] and the token it gives are how a
/// look says which events its stat may not have seen.
final class FollowMachine {
  /// A machine for a platform that, when [tellsIdentity], gives the identity
  /// of the file at the path with each look: it then decides a replacement
  /// by the identity, and the watch's events decide nothing.
  FollowMachine({required this.tellsIdentity});

  /// Whether looks bring the identity of the file.
  final bool tellsIdentity;

  /// How far the file was read: the next range starts here.
  int get position => _position;
  var _position = 0;

  // a file made or moved onto the name: read from its start
  var _replaced = false;

  // the file was seen not there (at the start, or by a look) and has not been
  // put there by an event since: the next create or move onto the name is
  // that file's own appearance, however late after a look found it, and
  // replaces nothing
  var _owed = false;

  // the file the name held at the last look
  Object? _held;

  // how many creates and moves onto the name came
  var _puts = 0;

  /// Starts at the follow's start: [size] is the file's size, null where
  /// there is no file, [identity] its identity where [tellsIdentity]. With
  /// [fromEnd] the bytes there are not read.
  void start({required bool fromEnd, required int? size, Object? identity}) {
    _held = identity;
    _position = fromEnd ? size ?? 0 : 0;
    _owed = size == null;
  }

  /// An event of the watch: a file made or moved onto the name when [puts],
  /// any other event of the name otherwise (a write, a removal).
  void nameEvent({required bool puts}) {
    if (puts) {
      _puts++;
    }
    if (!tellsIdentity && puts) {
      if (_owed) {
        _owed = false;
      } else {
        _replaced = true;
      }
    }
  }

  /// Whether a look at a file of [size] and [identity] would change nothing
  /// and read nothing, so that it need not open the file. A file not there
  /// is not settled: the look says so.
  bool settled({required int? size, Object? identity}) =>
      !_replaced &&
      size == _position &&
      (!tellsIdentity || identity == null || identity == _held);

  /// Marks that a look is about to take its stat: pass what it returns to
  /// [look].
  int beginLook() => _puts;

  /// A look: the file's [size] now, null where there is no file, and its
  /// [identity] where [tellsIdentity]. [began] is what [beginLook] gave
  /// before the stat was taken.
  FollowPlan look(int began, {required int? size, Object? identity}) {
    if (tellsIdentity && identity != null) {
      _replaced = _replaced || (_held != null && identity != _held);
      _held = identity;
    }
    var reset = false;
    if (_replaced) {
      _replaced = false;
      if (_position > 0) {
        reset = true;
        _position = 0;
      }
    }
    if (size == null) {
      if (_puts != began) {
        // a file was put at the name after the stat that found none: the
        // absence is of the past, and the event has told what followed; had
        // it set the debt, the next put, a real replacement, would be taken
        // for this file's appearance. The next look sees the file.
        return FollowPlan(reset: reset);
      }
      _owed = true;
    }
    final end = size ?? 0;
    if (end < _position) {
      reset = true;
      _position = 0;
    }
    return FollowPlan(reset: reset, from: _position, to: end);
  }

  /// [count] bytes of the planned range were told: a read that fails
  /// further on goes on from here.
  void told(int count) => _position += count;
}
