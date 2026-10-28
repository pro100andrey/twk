/// What of one read's input is delivered: the rule a `Terminal` and a
/// `HeadlessTerminal` share, so a test's input reaches the app as a real
/// terminal's does.
library;

import 'events.dart';

/// Hands [deliver] the events one read of the input was decoded into,
/// in order, but for a run of motions with no button held and the same
/// modifiers, of which only the last: a sweep reported in all-motion
/// mode costs the app one hit test per read, not one per cell crossed.
/// Presses, releases, wheel steps, every point of a drag, every other
/// event and the order of what is delivered are kept.
void deliverCoalesced(
  List<InputEvent> events,
  void Function(InputEvent) deliver,
) {
  final last = events.length - 1;
  for (var i = 0; i < last; i++) {
    final e = events[i];
    if (!_movedOn(e, events[i + 1])) {
      deliver(e);
    }
  }
  if (last >= 0) {
    deliver(events[last]);
  }
}

/// Whether [next] makes [e] needless: both are motions with no button
/// held and the same modifiers.
bool _movedOn(InputEvent e, InputEvent next) =>
    e is MouseEvent &&
    e.kind == MouseKind.move &&
    next is MouseEvent &&
    next.kind == MouseKind.move &&
    next.modifiers == e.modifiers;
