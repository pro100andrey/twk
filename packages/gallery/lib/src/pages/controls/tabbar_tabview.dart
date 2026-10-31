// The TabBar, TabView page.
part of 'controls.dart';

final _tabbarTabviewPage = GalleryPage(
  group: 'Controls',
  title: 'TabBar, TabView',
  options: const [
    ChoiceOption('tabs', 'tabs', values: [3, 7], initial: 3),
    ChoiceOption('look', 'look', values: ['plain', 'strip']),
  ],
  build: (context, o) => _Tabs(
    count: o.choice('tabs'),
    strip: o.choice<String>('look') == 'strip',
  ),
  code: (o) {
    final tabs = _tabNames.take(o.choice<int>('tabs')).toList();
    final made = o.choice<String>('look') == 'strip'
        ? 'TabBar.strip'
        : 'TabBar';
    final bar =
        '      $made(controller: _tabs, tabs: const '
        '[${tabs.map((t) => "'$t'").join(', ')}]),';
    return [
      'final _tabs = TabController(length: ${tabs.length});',
      'var _wrap = true;',
      'var _hidden = false;',
      "var _indent = 'spaces';",
      '',
      '@override',
      'void dispose() {',
      '  _tabs.dispose();',
      '  super.dispose();',
      '}',
      '',
      '@override',
      'Widget build(BuildContext context) => SizedBox(',
      '  width: 40,',
      '  height: 7,',
      '  child: Column(',
      '    crossAxisAlignment: .stretch,',
      '    children: [',
      if (bar.length <= 80)
        bar
      else ...[
        '      $made(',
        '        controller: _tabs,',
        '        tabs: const [',
        for (final t in tabs) "          '$t',",
        '        ],',
        '      ),',
      ],
      '      Expanded(',
      '        // the view, its border primary while the focus is in it',
      '        child: FocusBuilder(',
      '          builder: (context, hasFocus, view) => Box(',
      '            border: .all(',
      '              type: .rounded,',
      '              style: hasFocus',
      '                  ? Theme.of(context).primary',
      '                  : Theme.of(context).border,',
      '            ),',
      '            padding: const .x(1),',
      '            child: view,',
      '          ),',
      '          child: TabView(',
      '            controller: _tabs,',
      '            children: [',
      '              Column(',
      '                crossAxisAlignment: .start,',
      '                children: [',
      '                  Checkbox(',
      '                    value: _wrap,',
      "                    label: 'wrap lines',",
      '                    onChanged: (on) => setState(() => _wrap = on),',
      '                  ),',
      '                  Checkbox(',
      '                    value: _hidden,',
      "                    label: 'show hidden files',",
      '                    onChanged: (on) => setState(() => _hidden = on),',
      '                  ),',
      '                ],',
      '              ),',
      '              Column(',
      '                crossAxisAlignment: .start,',
      '                children: [',
      "                  const Text('Indent with'),",
      '                  RadioGroup<String>(',
      '                    choices: const [',
      "                      Choice('spaces', 'spaces'),",
      "                      Choice('tabs', 'tabs'),",
      '                    ],',
      '                    value: _indent,',
      '                    direction: .horizontal,',
      _indentLine,
      '                  ),',
      '                ],',
      '              ),',
      for (final t in tabs.skip(2)) _tabTextLine(t),
      '            ],',
      '          ),',
      '        ),',
      '      ),',
      '    ],',
      '  ),',
      ');',
    ].join('\n');
  },
);

const _tabNames = [
  'General',
  'Editor',
  'Keys',
  'Themes',
  'Plugins',
  'Terminal',
  'About',
];

const _indentLine =
    '                    onChanged: (value) => '
    'setState(() => _indent = value),';

/// The Code's line of the Text of tab [t].
String _tabTextLine(String t) {
  final text = _tabText[t]!.replaceAll('\n', r'\n');
  return "              const Text('$text'),";
}

/// What the tabs after General and Editor show.
const _tabText = {
  'Keys': 'ctrl+s saves the file.\nctrl+q quits.',
  'Themes': 'How the colours look.',
  'Plugins': 'What else is loaded.',
  'Terminal': 'The terminal it runs in.',
  'About': 'What this is.',
};

/// Tabs of settings, [count] of them, and the view of the one picked.
final class _Tabs extends StatefulWidget {
  const _Tabs({required this.count, required this.strip});

  final int count;

  /// Whether the bar is on a strip ([TabBar.strip]).
  final bool strip;

  @override
  State<_Tabs> createState() => _TabsState();
}

final class _TabsState extends State<_Tabs> with KeptState {
  /// The tabs, kept with the page: new ones, at the first, when their
  /// count changes.
  TabController get _tabs {
    final c = kept['tabs'] as TabController?;
    if (c != null && c.length == widget.count) {
      return c;
    }
    return kept['tabs'] = TabController(length: widget.count);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final names = _tabNames.take(widget.count).toList();
    return SizedBox(
      width: 40,
      height: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.strip)
            TabBar.strip(controller: tabs, tabs: names)
          else
            TabBar(controller: tabs, tabs: names),
          Expanded(
            // the view, its border primary while the focus is in it
            child: FocusBuilder(
              builder: (context, hasFocus, view) => Box(
                border: Border.all(
                  type: BorderType.rounded,
                  style: hasFocus
                      ? Theme.of(context).primary
                      : Theme.of(context).border,
                ),
                padding: const EdgeInsets.x(1),
                child: view,
              ),
              child: TabView(
                controller: tabs,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: keptOr('wrap', true),
                        label: 'wrap lines',
                        onChanged: (on) => keep('wrap', on),
                      ),
                      Checkbox(
                        value: keptOr('hidden', false),
                        label: 'show hidden files',
                        onChanged: (on) => keep('hidden', on),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Indent with'),
                      RadioGroup<String>(
                        choices: const [
                          Choice('spaces', 'spaces'),
                          Choice('tabs', 'tabs'),
                        ],
                        value: keptOr('indent', 'spaces'),
                        direction: Axis.horizontal,
                        onChanged: (value) => keep('indent', value),
                      ),
                    ],
                  ),
                  for (final t in names.skip(2)) Text(_tabText[t]!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
