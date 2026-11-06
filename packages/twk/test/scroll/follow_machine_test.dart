// FollowMachine: when a followed file started over and what to read, from
// stats and events given in every order, with no file, watch or clock.
import 'package:test/test.dart';
import 'package:twk/src/platform/follow_machine.dart';

FollowMachine started({
  int? size = 10,
  bool fromEnd = true,
  bool identity = false,
}) =>
    FollowMachine(tellsIdentity: identity)
      ..start(fromEnd: fromEnd, size: size, identity: identity ? 'a' : null);

/// A look with nothing in between.
FollowPlan look(FollowMachine m, int? size, [Object? identity]) =>
    m.look(m.beginLook(), size: size, identity: identity);

/// The plan of a look, its range told as read.
FollowPlan read(FollowMachine m, int? size, [Object? identity]) {
  final plan = look(m, size, identity);
  if (plan.reads) {
    m.told(plan.to - plan.from);
  }
  return plan;
}

void expectPlan(FollowPlan plan, {bool reset = false, int? from, int? to}) {
  expect(plan.reset, reset, reason: '$plan');
  if (from == null) {
    expect(plan.reads, isFalse, reason: '$plan');
  } else {
    expect([plan.from, plan.to], [from, to], reason: '$plan');
  }
}

void main() {
  group('sizes', () {
    test('from the end, what is there is not read, what is added is', () {
      final m = started();
      expectPlan(look(m, 10));
      expectPlan(read(m, 14), from: 10, to: 14);
      expectPlan(look(m, 14));
    });

    test('from the start, all of it is read', () {
      final m = started(fromEnd: false);
      expectPlan(read(m, 10), from: 0, to: 10);
    });

    test('shorter than what was read: a reset, then it from its start', () {
      final m = started();
      expectPlan(read(m, 4), reset: true, from: 0, to: 4);
      expect(m.position, 4);
    });

    test('a file gone: a reset, and the next one is read from its start', () {
      final m = started();
      expectPlan(read(m, null), reset: true);
      expectPlan(read(m, 3), from: 0, to: 3);
    });

    test('a read told in parts goes on from the last part', () {
      final m = started(size: 0);
      final plan = look(m, 9);
      m.told(4);
      expect(plan.from, 0);
      expectPlan(look(m, 9), from: 4, to: 9);
    });
  });

  group('a file put at the name', () {
    test(
      'a create event, whatever the size: a reset and all from the start',
      () {
        final m = started()..nameEvent(puts: true);
        expectPlan(read(m, 30), reset: true, from: 0, to: 30);
      },
    );

    test('an event that is not a put resets nothing', () {
      final m = started()..nameEvent(puts: false);
      expectPlan(look(m, 10));
    });

    test('before anything was read there is nothing to reset', () {
      final m = started(size: 0, fromEnd: false)..nameEvent(puts: true);
      expectPlan(look(m, 8), from: 0, to: 8);
    });

    test('a put is one reset, however many looks follow', () {
      final m = started()..nameEvent(puts: true);
      expectPlan(read(m, 30), reset: true, from: 0, to: 30);
      expectPlan(look(m, 30));
    });
  });

  group('the appearance of a file not there', () {
    test('its create event, before the look that finds it, resets nothing', () {
      final m = started(size: null, fromEnd: false)..nameEvent(puts: true);
      expectPlan(read(m, 5), from: 0, to: 5);
      m.nameEvent(puts: false);
      expectPlan(read(m, 8), from: 5, to: 8);
    });

    test('its create event, after the look that finds it, resets nothing', () {
      final m = started(size: null, fromEnd: false);
      expectPlan(read(m, 5), from: 0, to: 5);
      m.nameEvent(puts: true);
      expectPlan(read(m, 8), from: 5, to: 8);
    });

    test('a second put after the appearance is a replacement', () {
      final m = started(size: null, fromEnd: false);
      expectPlan(read(m, 5), from: 0, to: 5);
      m
        ..nameEvent(puts: true)
        ..nameEvent(puts: true);
      expectPlan(read(m, 5), reset: true, from: 0, to: 5);
    });

    test('a file removed and seen so, then made again: its create event is '
        'its appearance', () {
      final m = started();
      expectPlan(read(m, null), reset: true);
      expectPlan(read(m, 6), from: 0, to: 6);
      m.nameEvent(puts: true);
      expectPlan(look(m, 6));
    });
  });

  group('events and a look out of order', () {
    test('a create event that comes before the answer of a look whose stat '
        'saw no file is not forgotten by it: the next replacement is told', () {
      final m = started();
      // a look takes its stat when the file is gone ...
      final began = m.beginLook();
      // ... the file is made, and the watch tells it before the look's
      // answer comes back
      m
        ..nameEvent(puts: true)
        ..look(began, size: null);
      // the new file is read
      expectPlan(read(m, 6), from: 0, to: 6);
      // then another is renamed over it, no longer than what was read
      m.nameEvent(puts: true);
      expectPlan(read(m, 6), reset: true, from: 0, to: 6);
    });

    test('the same for a file that was not there at the start, its '
        'appearance told before the look that found it absent answers', () {
      final m = started(size: null, fromEnd: false);
      final began = m.beginLook();
      m
        ..nameEvent(puts: true)
        ..look(began, size: null);
      expectPlan(read(m, 4), from: 0, to: 4);
      m.nameEvent(puts: true);
      expectPlan(read(m, 4), reset: true, from: 0, to: 4);
    });

    test('the appearance event after a look whose stat saw the file absent '
        'is not a replacement', () {
      final m = started(size: null, fromEnd: false);
      final began = m.beginLook();
      m
        ..look(began, size: null)
        ..nameEvent(puts: true);
      expectPlan(read(m, 4), from: 0, to: 4);
      expectPlan(read(m, 4));
    });

    test('two creates before a look are one reset', () {
      final m = started()
        ..nameEvent(puts: true)
        ..nameEvent(puts: true);
      expectPlan(read(m, 12), reset: true, from: 0, to: 12);
      expectPlan(look(m, 12));
    });

    test('a put during a look is a reset in that look, or the next', () {
      final m = started();
      final began = m.beginLook();
      m.nameEvent(puts: true);
      expectPlan(m.look(began, size: 14), reset: true, from: 0, to: 14);
    });

    test('writes told after a put do not undo it', () {
      final m = started()
        ..nameEvent(puts: true)
        ..nameEvent(puts: false)
        ..nameEvent(puts: false);
      expectPlan(read(m, 12), reset: true, from: 0, to: 12);
    });
  });

  group('where the platform tells files apart', () {
    test('the identity decides, the events do not', () {
      final m = started(identity: true)..nameEvent(puts: true);
      expectPlan(look(m, 10, 'a'));
      expectPlan(read(m, 14, 'b'), reset: true, from: 0, to: 14);
      expectPlan(look(m, 14, 'b'));
    });

    test('a replacement as long as the old one is told by the identity', () {
      final m = started(identity: true);
      expectPlan(read(m, 10, 'b'), reset: true, from: 0, to: 10);
    });

    test('a look without an identity (the file gone) keeps the last one', () {
      final m = started(identity: true);
      expectPlan(read(m, null), reset: true);
      expectPlan(read(m, 3, 'a'), from: 0, to: 3);
    });
  });
}
