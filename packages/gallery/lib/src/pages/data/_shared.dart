// What the pages of the group share.
part of 'data.dart';

/// The rows a widget takes in [room]: [want]
/// rows, or the room's where it is lower, [least] at least.
int _rowsIn(StageRoom room, int want, int least) =>
    math.max(least, math.min(want, room.height));

/// The lines of a State whose timer calls [body] every [ms], and a blank.
List<String> _timer(int ms, List<String> body) => [
  ...timerLines(ms, body),
  '',
];

/// The step of [step] ms that [ms] is in; asks for a build at the next.
int _tick(int ms, int step, void Function(int) wake) {
  final k = ms ~/ step;
  wake((k + 1) * step);
  return k;
}

/// A value from 0 to 1 that looks random and is the same for the same [i],
/// as the Code's `_noise` computes it.
double _noise(int i) {
  final s = math.sin(i * 91.345 + 3.1) * 43758.5453;
  return s - s.floorToDouble();
}

/// The Code's line of what `_noise` gives.
const _noiseDoc =
    '/// A value from 0 to 1 that looks random and is the same for the same '
    '[i].';

/// The glyph of the custom marker.
const _customMarker = '*';

/// twk's markers, by the name the options give them, and one of a glyph's
/// own.
final _markers = <String, Marker>{
  'braille': Marker.braille,
  'halfBlock': Marker.halfBlock,
  'quadrant': Marker.quadrant,
  'sextant': Marker.sextant,
  'octant': Marker.octant,
  'block': Marker.block,
  'dot': Marker.dot,
  'bar': Marker.bar,
  'custom': Marker.custom(_customMarker),
};

/// The Code's marker of the options [o]: `.braille`, `.custom('*')`.
String _markerCode(Options o) => o.nameOf(_chartMarker) == 'custom'
    ? ".custom('$_customMarker')"
    : '.${o.nameOf(_chartMarker)}';

const _waveTick = 50;

// ------------------------------------------------------------ Table

typedef _File = (String, int, double);

/// The five files.
const _files = <_File>[
  ('box.dart', 412, .9),
  ('text.dart', 230, .75),
  ('flex.dart', 388, .6),
  ('grid.dart', 520, .4),
  ('stack.dart', 145, 1.0),
];

/// The lines a table draws between its columns and under its header.
const _borders = ['none', 'single', 'rounded', 'double', 'heavy', 'ascii'];
