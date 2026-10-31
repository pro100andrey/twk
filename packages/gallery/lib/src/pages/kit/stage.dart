// What the pages' widgets share on the stage: the room it gives them,
// the colours they offer, a bold style.
import 'dart:math' as math;

import 'package:twk/twk.dart';

import '../../page.dart';

/// The theme colours the pages offer a choice of, in the design's order.
const pageColors = ['primary', 'accent', 'success', 'warning', 'error', 'info'];

/// The colour option most pages offer: the style of their widget, from
/// [pageColors], `primary` first.
const pageColorOption = ColorOption(
  'color',
  'style',
  values: pageColors,
  initial: 'primary',
);

/// twk's [Alignment]s by name, as the pages' options name them.
const Map<String, Alignment> alignmentByName = {
  'topLeft': Alignment.topLeft,
  'topCenter': Alignment.topCenter,
  'topRight': Alignment.topRight,
  'centerLeft': Alignment.centerLeft,
  'center': Alignment.center,
  'centerRight': Alignment.centerRight,
  'bottomLeft': Alignment.bottomLeft,
  'bottomCenter': Alignment.bottomCenter,
  'bottomRight': Alignment.bottomRight,
};

/// Bold, and nothing else.
const bold = Style(attrs: Attr.bold);

/// [v] within [low] and [high]; [low] where they cross.
int clampTo(int v, int low, int high) => math.max(low, math.min(high, v));

/// [build] with the columns and rows of the stage's room: as many as a
/// widget takes where it is not bounded.
Widget inRoom(Widget Function(int width, int height) build) => LayoutBuilder(
  builder: (context, c) {
    const most = 1 << 20;
    return build(
      c.maxW < BoxConstraints.unbounded ? c.maxW : most,
      c.maxH < BoxConstraints.unbounded ? c.maxH : most,
    );
  },
);
