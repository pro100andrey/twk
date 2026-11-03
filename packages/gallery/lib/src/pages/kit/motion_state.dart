// A State that a Motion builds again on the gallery's clock.
import 'package:twk/twk.dart';

import '../../motion.dart';

/// A State with a [Motion] that builds it again when it asks: its
/// [motion], disposed with it. Its build begins and ends the motion.
mixin MotionState<W extends StatefulWidget> on State<W> {
  late final motion = Motion(() {
    if (mounted) {
      setState(() {});
    }
  });

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }
}
