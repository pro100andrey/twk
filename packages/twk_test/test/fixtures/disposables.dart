// Tests whose end disposables_test.dart checks from outside: run by
// `dart test` in a process of their own.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Makes a controller, and disposes it unless [leak].
final class Owner extends StatefulWidget {
  const Owner({required this.leak, super.key});

  final bool leak;

  @override
  State<Owner> createState() => _OwnerState();
}

final class _OwnerState extends State<Owner> {
  final controller = ScrollController();
  final text = TextEditingController();

  @override
  void dispose() {
    if (!widget.leak) {
      controller.dispose();
    }
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('x');
}

void main() {
  testTwk('a controller left undisposed', trackDisposables: true, (t) async {
    await t.pumpWidget(const Owner(leak: true));
  });

  testTwk('a controller left undisposed, tracking off', (t) async {
    await t.pumpWidget(const Owner(leak: true));
  });

  testTwk('every controller disposed', trackDisposables: true, (t) async {
    await t.pumpWidget(const Owner(leak: false));
  });

  testTwk('a test that fails', trackDisposables: true, (t) async {
    await t.pumpWidget(const Owner(leak: true));
    fail('its own');
  });

  timerTests();
}

/// Starts a periodic timer, and cancels it unless [leak].
final class Ticker extends StatefulWidget {
  const Ticker({required this.leak, super.key});

  final bool leak;

  @override
  State<Ticker> createState() => _TickerState();
}

final class _TickerState extends State<Ticker> {
  late final Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    if (!widget.leak) {
      timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('x');
}

void timerTests() {
  testTwk('a timer left running', (t) async {
    await t.pumpWidget(const Ticker(leak: true));
  });

  testTwk('a timer left running, checking off', failOnPendingTimers: false, (
    t,
  ) async {
    await t.pumpWidget(const Ticker(leak: true));
  });

  testTwk('the timer cancelled', (t) async {
    await t.pumpWidget(const Ticker(leak: false));
  });

  testTwk('a plain app', (t) async {
    await t.pumpWidget(const Text('x'));
  });
}
