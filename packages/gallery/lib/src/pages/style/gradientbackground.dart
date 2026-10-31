// The GradientBackground page.
part of 'style.dart';

final _gradientbackgroundPage = GalleryPage(
  group: _group,
  title: 'GradientBackground',
  options: _gradientOptions('sunset'),
  build: (context, o) => _Flowing(
    options: o,
    sets: _sets,
    build: (context, gradient) => GradientBackground(
      gradient: gradient,
      child: SizedBox(
        width: _bgWidth,
        height: _bgHeight,
        child: Center(
          child: Box(
            style: Theme.of(context).surface,
            padding: const EdgeInsets.only(
              left: 2,
              top: 1,
              right: 2,
              bottom: 1,
            ),
            child: const Text(_bgText),
          ),
        ),
      ),
    ),
  ),
  code: (o) => _gradientCode(o, 'Backdrop', _sets, [
    'GradientBackground(',
    '  gradient: gradient,',
    '  child: SizedBox(',
    '    width: $_bgWidth,',
    '    height: $_bgHeight,',
    '    child: Center(',
    '      child: Box(',
    '        style: Theme.of(context).surface,',
    '        padding: const .only(left: 2, top: 1, right: 2, bottom: 1),',
    "        child: const Text('$_bgText'),",
    '      ),',
    '    ),',
    '  ),',
    ')',
  ]),
);

// --------------------------------------------------- the gradients' widgets

const _bgWidth = 44;

const _bgHeight = 9;

const _bgText = 'a box over a gradient';
