// A widget whose screen changes on a timer, for the tests of the frames.
import 'dart:async';

import 'package:twk/twk.dart';

/// Shows `tick n`, n going up by one every [period] until it is [to].
final class TickingCounter extends StatefulWidget {
  const TickingCounter(this.period, {required this.to, super.key});

  final Duration period;
  final int to;

  @override
  State<TickingCounter> createState() => _TickingCounterState();
}

final class _TickingCounterState extends State<TickingCounter> {
  var _n = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (timer) {
      setState(() => _n++);
      if (_n == widget.to) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('tick $_n');
}
