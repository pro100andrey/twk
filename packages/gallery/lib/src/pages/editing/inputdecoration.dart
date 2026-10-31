// The InputDecoration page.
part of 'editing.dart';

final _inputdecorationPage = GalleryPage(
  group: 'Editing',
  title: 'InputDecoration',
  options: const [
    ChoiceOption(
      'border',
      'border',
      values: ['outline', 'underline', 'none'],
    ),
    SwitchOption('filled', 'filled'),
    SwitchOption('enabled', 'enabled', initial: true),
  ],
  build: (context, o) => _Decorated(
    border: switch (o.choice<String>('border')) {
      'outline' => const OutlineInputBorder(),
      'underline' => const UnderlineInputBorder(),
      _ => InputBorder.none,
    },
    filled: o.flag('filled'),
    enabled: o.flag('enabled'),
  ),
  code: (o) {
    final border = switch (o.choice<String>('border')) {
      'outline' => 'OutlineInputBorder()',
      'underline' => null,
      _ => 'InputBorder.none',
    };
    final on = o.flag('enabled');
    // the parts each decoration ends with, [pad] columns in (const where
    // the decoration is not)
    List<String> rest(String pad, {bool constant = true}) {
      final made = constant || border == null || border.startsWith('Input');
      return [
        if (border != null) '${pad}border: ${made ? '' : 'const '}$border,',
        if (o.flag('filled')) '${pad}filled: true,',
      ];
    }

    List<String> enabled(String pad) => [if (!on) '${pad}enabled: false,'];
    return [
      "var _theme = 'dark';",
      "var _password = '';",
      '',
      '@override',
      'Widget build(BuildContext context) {',
      '  return Row(',
      '    mainAxisSize: .min,',
      '    crossAxisAlignment: .start,',
      '    gap: 2,',
      '    children: [',
      '      SizedBox(',
      '        width: 24,',
      '        child: Column(',
      '          mainAxisSize: .min,',
      '          gap: 1,',
      '          children: [',
      '            Select<String>(',
      '              choices: const [',
      "                Choice('dark', 'Dark'),",
      "                Choice('light', 'Light'),",
      "                Choice('nord', 'Nord'),",
      '              ],',
      '              value: _theme,',
      if (on) _themeChangedLine else '              onChanged: null,',
      '              decoration: const InputDecoration(',
      "                icon: Text('◐'),",
      "                labelText: 'Theme',",
      "                helperText: 'Enter opens it',",
      ...rest('                '),
      '              ),',
      '            ),',
      '            TextField(',
      "              placeholder: 'twk',",
      ...enabled('              '),
      '              decoration: const InputDecoration(',
      "                labelText: 'Site',",
      "                prefixText: 'https://',",
      "                suffixText: '.dev',",
      "                helperText: 'where it lives',",
      ...rest('                '),
      '              ),',
      '            ),',
      '          ],',
      '        ),',
      '      ),',
      '      SizedBox(',
      '        width: 24,',
      '        child: Column(',
      '          mainAxisSize: .min,',
      '          gap: 1,',
      '          children: [',
      '            TextField(',
      "              placeholder: 'files, commands',",
      ...enabled('              '),
      '              decoration: const InputDecoration(',
      "                labelText: 'Search',",
      "                prefixIcon: Text('⌕'),",
      "                suffixIcon: Text('↵'),",
      "                helperText: 'by name',",
      ...rest('                '),
      '              ),',
      '            ),',
      '            // only the field builds again as its text changes',
      '            StatefulBuilder(',
      '              builder: (context, setState) => TextField(',
      "                placeholder: 'secret',",
      '                obscureText: true,',
      '                // counted in the decoration: 0/16',
      '                maxLength: 16,',
      ...enabled('                '),
      _passwordChangedLine,
      '                decoration: InputDecoration(',
      "                  labelText: 'Password',",
      _passwordLine,
      "                      ? 'at least 8 chars'",
      '                      : null,',
      ...rest('                  ', constant: false),
      '                ),',
      '              ),',
      '            ),',
      '          ],',
      '        ),',
      '      ),',
      '    ],',
      '  );',
      '}',
    ].join('\n');
  },
);

const _passwordLine =
    '                  errorText: _password.isNotEmpty && '
    '_password.characterCount < 8';

const _themeChangedLine =
    '              onChanged: (theme) => setState(() => _theme = theme),';

const _passwordChangedLine =
    '                onChanged: (text) => setState(() => _password = text),';

/// Four fields in [border], each decorated in its own way: a Select
/// with an icon and a helper, a prefix and a suffix, icons inside, and a
/// counter and an error, its field built again alone.
final class _Decorated extends StatefulWidget {
  const _Decorated({
    required this.border,
    required this.filled,
    required this.enabled,
  });

  final InputBorder border;
  final bool filled;
  final bool enabled;

  @override
  State<_Decorated> createState() => _DecoratedState();
}

final class _DecoratedState extends State<_Decorated> with KeptState {
  String get _theme => kept['theme'] as String? ?? 'dark';
  String get _password => kept['passwordText'] as String? ?? '';

  /// The field of [key], its text kept from visit to visit.
  TextEditingController _controller(String key) =>
      keptAt(context, key, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final border = widget.border;
    final filled = widget.filled;
    final enabled = widget.enabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 2,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              Select<String>(
                choices: const [
                  Choice('dark', 'Dark'),
                  Choice('light', 'Light'),
                  Choice('nord', 'Nord'),
                ],
                value: _theme,
                onChanged: enabled
                    ? (theme) => setState(() => kept['theme'] = theme)
                    : null,
                decoration: InputDecoration(
                  icon: const Text('◐'),
                  labelText: 'Theme',
                  helperText: 'Enter opens it',
                  border: border,
                  filled: filled,
                ),
              ),
              TextField(
                controller: _controller('site'),
                placeholder: 'twk',
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: 'Site',
                  prefixText: 'https://',
                  suffixText: '.dev',
                  helperText: 'where it lives',
                  border: border,
                  filled: filled,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            gap: 1,
            children: [
              TextField(
                controller: _controller('search'),
                placeholder: 'files, commands',
                enabled: enabled,
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Text('⌕'),
                  suffixIcon: const Text('↵'),
                  helperText: 'by name',
                  border: border,
                  filled: filled,
                ),
              ),
              StatefulBuilder(
                builder: (context, setState) {
                  final password = _password;
                  return TextField(
                    controller: _controller('password'),
                    placeholder: 'secret',
                    obscureText: true,
                    maxLength: 16,
                    enabled: enabled,
                    onChanged: (text) =>
                        setState(() => kept['passwordText'] = text),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      errorText:
                          password.isNotEmpty && password.characterCount < 8
                          ? 'at least 8 chars'
                          : null,
                      border: border,
                      filled: filled,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
