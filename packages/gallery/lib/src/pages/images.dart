// The Images group of the gallery.
import 'dart:math' as math;

import 'package:twk/twk.dart' show Alignment;
import 'package:twk_rich/image.dart';

import '../page.dart';
import 'pictures.dart';

/// The pages of the Images group that draw.
final imagePages = <GalleryPage>[_image];

/// The pictures, by the option's value: the file the Code names, and its
/// size in pixels.
const _pictures = {
  'lake': ('lake.jpg', 240, 160),
  'logo': ('logo.png', 128, 128),
};

/// The alignments the page offers, by name.
const _alignments = <String, Alignment>{
  'center': .center,
  'topLeft': .topLeft,
  'centerLeft': .centerLeft,
  'centerRight': .centerRight,
  'bottomRight': .bottomRight,
};

final _image = GalleryPage(
  group: 'Images',
  title: 'Image',
  about:
      'A PNG or JPEG fitted to its cells. Where the terminal has a graphics '
      'protocol (kitty, sixel, iTerm2) its pixels are placed over the cells; '
      'where it has none, or with forceBlocks, as here, it is drawn in half '
      'blocks or quadrants.',
  options: [
    const ChoiceOption(
      'picture',
      'picture',
      values: ['lake', 'logo'],
      labels: ['lake.jpg', 'logo.png'],
    ),
    const ChoiceOption(
      'fit',
      'fit',
      values: ['contain', 'cover', 'fill', 'scaleDown'],
    ),
    // where a contained picture sits in the room it leaves, and which
    // part of a covering one shows
    const ChoiceOption(
      'alignment',
      'alignment',
      values: ['center', 'topLeft', 'centerLeft', 'centerRight', 'bottomRight'],
    ),
    const ChoiceOption('mode', 'blocks', values: ['half', 'quadrant']),
    SliderOption(
      'width',
      'width',
      min: 8,
      max: 80,
      initial: 44,
      format: (v) => '$v cells',
    ),
    SliderOption(
      'height',
      'height',
      min: 3,
      max: 30,
      initial: 12,
      format: (v) => '$v rows',
    ),
  ],
  // the bytes of the file the Code reads
  build: (context, o) => Image.memory(
    pictureBytes[_pictures[o.choice<String>('picture')]!.$1]!,
    width: o.number('width').toInt(),
    height: o.number('height').toInt(),
    fit: ImageFit.values.byName(o.choice('fit')),
    alignment: _alignments[o.choice<String>('alignment')]!,
    blockMode: BlockMode.values.byName(o.choice('mode')),
    forceBlocks: true,
  ),
  heightIn: (o, room) =>
      math.min(o.number('height').toInt(), math.max(3, room.height)),
  code: (o) {
    final (file, w, h) = _pictures[o.choice<String>('picture')]!;
    return [
      '@override',
      'Widget build(BuildContext context) => Image.file(',
      "  'assets/$file', // $w × $h pixels",
      '  width: ${o.label('width')},',
      '  height: ${o.label('height')},',
      if (o.label('fit') != 'contain') '  fit: .${o.label('fit')},',
      if (o.label('alignment') != 'center')
        '  alignment: .${o.label('alignment')},',
      if (o.label('mode') != 'half') '  blockMode: .quadrant,',
      "  // in blocks wherever it runs; without it the terminal's graphics",
      '  // protocol where it has one: kitty, sixel or iTerm2',
      '  forceBlocks: true,',
      ');',
    ].join('\n');
  },
);
