// The Image page.
part of 'images.dart';

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

/// The Image page's `picture` option.
const _imagePicture = ChoiceOption<String>(
  'picture',
  'picture',
  values: ['lake', 'logo'],
  labels: ['lake.jpg', 'logo.png'],
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

/// The Image page's `mode` option.
const _imageMode = ChoiceOption<String>(
  'mode',
  'blocks',
  values: ['half', 'quadrant'],
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
      'A PNG or JPEG fitted to its cells. Where the terminal has a graphics '
      'protocol (kitty, sixel, iTerm2) its pixels are placed over the cells; '
      'where it has none, or with forceBlocks, as here, it is drawn in half '
      'blocks or quadrants.',
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
    blockMode: BlockMode.values.byName(o(_imageMode)),
    forceBlocks: true,
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
      if (o.nameOf(_imageMode) != 'half') '  blockMode: .quadrant,',
      "  // in blocks wherever it runs; without it the terminal's graphics",
      '  // protocol where it has one: kitty, sixel or iTerm2',
      '  forceBlocks: true,',
      ');',
    ].join('\n');
  },
);
