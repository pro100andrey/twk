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
  // room for the dialog: the App's Overlay, which it shows in, is the
  // App's size
  build: (context, o) => SizedBox(
    width: 32,
    height: 9,
    child: App(
      theme: _appThemes[o(_appTheme)],
      // a context below the App: its Overlay is the one the dialog shows in
      child: Builder(
        builder: (context) => Center(
          child: Button(
            'Ask',
            onPressed: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (context) => Dialog(
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
    ),
  ),
  code: (o) => [
    '@override',
    'Widget build(BuildContext context) => SizedBox(',
    "  // room for the dialog: the Overlay it shows in is the App's size",
    '  width: 32,',
    '  height: 9,',
    '  child: App(',
    '    theme: ThemeData.${o.nameOf(_appTheme)},',
    '    // a context below the App: its Overlay is the one the dialog shows in',
    '    child: Builder(',
    '      builder: (context) => Center(',
    '        child: Button(',
    "          'Ask',",
    '          onPressed: () => unawaited(',
    '            showDialog<void>(',
    '              context: context,',
    '              builder: (context) => Dialog(',
    "                title: 'In the theme',",
    '                child: Button(',
    "                  'OK',",
    '                  autofocus: true,',
    '                  onPressed: () => closeDialog(context),',
    '                ),',
    '              ),',
    '            ),',
    '          ),',
    '        ),',
    '      ),',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);
