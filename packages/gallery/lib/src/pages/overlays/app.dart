// The App page.
part of 'overlays.dart';

/// The themes the App page gives its App, by name.
const Map<String, ThemeData> _appThemes = {
  'nord': ThemeData.nord,
  'light': ThemeData.light,
  'dark': ThemeData.dark,
};

/// The App page's `theme` option.
const _appTheme = ChoiceOption<String>(
  'theme',
  'theme',
  values: ['nord', 'light', 'dark'],
);

final _appPage = GalleryPage(
  group: _group,
  title: 'App',
  options: [_appTheme],
  build: (context, o) => App(
    theme: _appThemes[o(_appTheme)],
    // a context below the App: its Overlay is the one the dialog shows in
    child: Builder(
      builder: (context) => Button(
        'Ask',
        onPressed: () => unawaited(
          showDialog<void>(
            context,
            (context) => Dialog(
              title: 'In the theme',
              child: Button(
                'OK',
                autofocus: true,
                onPressed: () => closeDialog(context),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
  code: (o) => [
    '@override',
    'Widget build(BuildContext context) => App(',
    '  theme: ThemeData.${o.nameOf(_appTheme)},',
    '  // a context below the App: its Overlay is the one the dialog shows in',
    '  child: Builder(',
    '    builder: (context) => Button(',
    "      'Ask',",
    '      onPressed: () => unawaited(',
    '        showDialog<void>(',
    '          context,',
    '          (context) => Dialog(',
    "            title: 'In the theme',",
    '            child: Button(',
    "              'OK',",
    '              autofocus: true,',
    '              onPressed: () => closeDialog(context),',
    '            ),',
    '          ),',
    '        ),',
    '      ),',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);
