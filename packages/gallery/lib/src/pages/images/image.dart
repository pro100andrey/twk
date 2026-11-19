// The Image page.
part of 'images.dart';

/// The pictures, by the option's value: the file the Code names, and its
/// size in pixels.
const _pictures = {
  'lake': ('lake.jpg', 240, 160),
  'logo': ('logo.png', 128, 128),
  'orbit': ('orbit.gif', 64, 64),
};

/// The alignments the page offers, by name.
const _alignments = <String, Alignment>{
  'center': .center,
  'topLeft': .topLeft,
  'centerLeft': .centerLeft,
  'centerRight': .centerRight,
  'bottomRight': .bottomRight,
};

/// The Image page's `picture` option.
const _imagePicture = ChoiceOption<String>(
  'picture',
  'picture',
  values: ['lake', 'logo', 'orbit'],
  labels: ['lake.jpg', 'logo.png', 'orbit.gif'],
);

/// The Image page's `fit` option.
const _imageFit = ChoiceOption<String>(
  'fit',
  'fit',
  values: ['contain', 'cover', 'fill', 'scaleDown'],
);

/// The Image page's `alignment` option.
const _imageAlignment = ChoiceOption<String>(
  'alignment',
  'alignment',
  values: ['center', 'topLeft', 'centerLeft', 'centerRight', 'bottomRight'],
);

/// The Image page's `mode` option: in blocks of a mode, as the gallery is
/// drawn by default (a protocol's pixels lie over the cells, the menus and
/// hints too), or with the terminal's graphics protocol where it has one.
const _imageMode = ChoiceOption<String>(
  'mode',
  'drawn',
  values: [
    'detected',
    'half',
    'quadrant',
    'sextant',
    'octant',
    'braille',
    'ascii',
    'protocol',
  ],
);

/// The Image page's `width` option.
final _imageWidth = SliderOption(
  'width',
  'width',
  min: 8,
  max: 80,
  initial: 44,
  format: (v) => '$v cells',
);

/// The Image page's `height` option.
final _imageHeight = SliderOption(
  'height',
  'height',
  min: 3,
  max: 30,
  initial: 12,
  format: (v) => '$v rows',
);

final _image = GalleryPage(
  group: _group,
  title: 'Image',
  about:
      'A PNG, JPEG, GIF or APNG fitted to its cells; a GIF or APNG with '
      'frames plays on the app’s clock, each frame drawn as it comes, and '
      'kitty, which plays an animation itself, is sent all the frames once. '
      'A TickerMode that is off stands it on the frame it shows. Where the '
      'terminal has a graphics protocol (kitty, sixel, iTerm2) its pixels '
      'are placed over the cells (drawn: protocol); where it has none, or '
      'with forceBlocks, it is drawn in '
      'characters: half blocks, quadrants, sextants (Unicode 13), octants '
      '(Unicode 16), braille or plain ASCII. Left to detected, the default, '
      'it is sextants where the terminal is known to draw them itself '
      '(kitty, foot, Ghostty, WezTerm, Konsole, VTE and a few more) and half '
      'blocks elsewhere; TWK_IMAGE_BLOCKS names a mode for all images.',
  options: [
    _imagePicture,
    _imageFit,
    // where a contained picture sits in the room it leaves, and which
    // part of a covering one shows
    _imageAlignment,
    _imageMode,
    _imageWidth,
    _imageHeight,
  ],
  // the bytes of the file the Code reads
  build: (context, o) => Image.memory(
    pictureBytes[_pictures[o(_imagePicture)]!.$1]!,
    width: o(_imageWidth).toInt(),
    height: o(_imageHeight).toInt(),
    fit: ImageFit.values.byName(o(_imageFit)),
    alignment: _alignments[o(_imageAlignment)]!,
    blockMode: switch (o(_imageMode)) {
      'detected' || 'protocol' => null,
      final mode => BlockMode.values.byName(mode),
    },
    forceBlocks: o(_imageMode) != 'protocol',
  ),
  heightIn: (o, room) =>
      math.min(o(_imageHeight).toInt(), math.max(3, room.height)),
  code: (o) {
    final (file, w, h) = _pictures[o(_imagePicture)]!;
    return [
      '@override',
      'Widget build(BuildContext context) => Image.file(',
      "  'assets/$file', // $w × $h pixels",
      '  width: ${o.nameOf(_imageWidth)},',
      '  height: ${o.nameOf(_imageHeight)},',
      if (o.nameOf(_imageFit) != 'contain') '  fit: .${o.nameOf(_imageFit)},',
      if (o.nameOf(_imageAlignment) != 'center')
        '  alignment: .${o.nameOf(_imageAlignment)},',
      if (o.nameOf(_imageMode) case final mode
          when mode != 'detected' && mode != 'protocol')
        '  blockMode: .$mode,',
      if (o.nameOf(_imageMode) != 'protocol') ...[
        "  // in blocks wherever it runs; without it the terminal's graphics",
        '  // protocol where it has one: kitty, sixel or iTerm2',
        '  forceBlocks: true,',
      ],
      ');',
    ].join('\n');
  },
);
