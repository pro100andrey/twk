// The Stepper page.
part of 'navigation.dart';

/// The packages the wizard offers.
const _offered = ['args', 'http', 'path'];

final _stepper = GalleryPage(
  group: 'Navigation',
  title: 'Stepper',
  options: const [
    ChoiceOption(
      'direction',
      'direction',
      values: ['horizontal', 'vertical'],
    ),
    SwitchOption('linear', 'linear', initial: true),
    // Back and Next under the content; without them PageDown and PageUp
    // still move it, and a click on a header
    SwitchOption('controls', 'back and next', initial: true),
    // the Packages step disabled: passed by, muted
    SwitchOption('disabled', 'packages disabled'),
  ],
  build: (context, o) => _Wizard(
    direction: Axis.values.byName(o.choice('direction')),
    linear: o.flag('linear'),
    showControls: o.flag('controls'),
    packagesDisabled: o.flag('disabled'),
  ),
  code: (o) => [
    "final _name = TextEditingController(text: 'my_app');",
    "final _packages = {'args'};",
    "var _created = '';",
    '',
    '@override',
    'void dispose() {',
    '  _name.dispose();',
    '  super.dispose();',
    '}',
    '',
    'Widget _package(String name) => Checkbox(',
    '  value: _packages.contains(name),',
    '  label: name,',
    '  onChanged: (on) => setState(() {',
    '    if (!on) {',
    '      _packages.remove(name);',
    '    } else {',
    '      _packages.add(name);',
    '    }',
    '  }),',
    ');',
    '',
    '@override',
    'Widget build(BuildContext context) {',
    '  final theme = Theme.of(context);',
    '  return Column(',
    '    mainAxisSize: .min,',
    '    crossAxisAlignment: .start,',
    '    gap: 1,',
    '    children: [',
    '      SizedBox(',
    '        width: 50,',
    '        child: Stepper(',
    if (o.choice<String>('direction') == 'vertical')
      '          direction: .vertical,',
    if (!o.flag('linear')) '          linear: false,',
    if (!o.flag('controls')) '          showControls: false,',
    '          steps: [',
    '            Step(',
    "              title: 'Name',",
    "              subtitle: 'What the package is called',",
    '              content: TextField(',
    '                controller: _name,',
    "                semanticsLabel: 'Name',",
    '              ),',
    '              validate: () =>',
    "                  _name.text.isEmpty ? 'The package needs a name' : null,",
    '            ),',
    '            Step(',
    "              title: 'Packages',",
    "              subtitle: 'What it depends on',",
    if (o.flag('disabled')) '              state: .disabled,',
    '              content: Column(',
    '                mainAxisSize: .min,',
    '                crossAxisAlignment: .start,',
    '                children: [',
    for (final p in _offered) "                  _package('$p'),",
    '                ],',
    '              ),',
    '              // as a server that looks them up would',
    '              validate: () async {',
    '                await Future<void>.delayed(',
    '                  const Duration(milliseconds: 800),',
    '                );',
    "                return _packages.isEmpty ? 'Pick one at least' : null;",
    '              },',
    '            ),',
    '            Step(',
    "              title: 'Confirm',",
    '              content: Text(',
    r"                'Create ${_name.text} with ${_packages.join(', ')}?',",
    '              ),',
    '            ),',
    '          ],',
    '          onFinished: () => setState(() => _created = _name.text),',
    '        ),',
    '      ),',
    '      Text.rich([',
    "        Span('created: ', theme.muted),",
    '        if (_created.isEmpty)',
    "          Span('nothing', theme.muted)",
    '        else',
    '          Span(_created),',
    '      ]),',
    '    ],',
    '  );',
    '}',
  ].join('\n'),
);

/// A wizard that makes a package, and the package it made last.
final class _Wizard extends StatefulWidget {
  const _Wizard({
    required this.direction,
    required this.linear,
    required this.showControls,
    required this.packagesDisabled,
  });

  final Axis direction;
  final bool linear;
  final bool showControls;
  final bool packagesDisabled;

  @override
  State<_Wizard> createState() => _WizardState();
}

final class _WizardState extends State<_Wizard> {
  final _name = TextEditingController(text: 'my_app');
  final _packages = {'args'};
  var _created = '';
  var _serial = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _package(String name) => Checkbox(
    value: _packages.contains(name),
    label: name,
    onChanged: (on) => setState(() {
      if (!on) {
        _packages.remove(name);
      } else {
        _packages.add(name);
      }
    }),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    gap: 1,
    children: [
      SizedBox(
        width: 50,
        child: Stepper(
          direction: widget.direction,
          linear: widget.linear,
          showControls: widget.showControls,
          steps: [
            Step(
              title: 'Name',
              subtitle: 'What the package is called',
              content: TextField(controller: _name, semanticsLabel: 'Name'),
              validate: () =>
                  _name.text.isEmpty ? 'The package needs a name' : null,
            ),
            Step(
              title: 'Packages',
              subtitle: 'What it depends on',
              state: widget.packagesDisabled ? StepState.disabled : null,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final p in _offered) _package(p)],
              ),
              validate: () async {
                await Future<void>.delayed(const Duration(milliseconds: 800));
                return _packages.isEmpty ? 'Pick one at least' : null;
              },
            ),
            Step(
              title: 'Confirm',
              content: Text(
                'Create ${_name.text} with ${_packages.join(', ')}?',
              ),
            ),
          ],
          onFinished: () => setState(() {
            _created = _name.text;
            _serial++;
          }),
        ),
      ),
      LitLine([
        ('created: ', true),
        if (_created.isEmpty) ('nothing', true) else (_created, false),
      ], serial: _serial),
    ],
  );
}
