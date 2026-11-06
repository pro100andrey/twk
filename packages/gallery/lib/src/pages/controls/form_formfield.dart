// The Form, FormField page.
part of 'controls.dart';

/// The Form, FormField page's `validate` option.
const _formFormfieldValidate = ChoiceOption<String>(
  'validate',
  'validate',
  values: ['disabled', 'always', 'onUserInteraction', 'onUnfocus'],
);

final _formFormfieldPage = GalleryPage(
  group: _group,
  title: 'Form, FormField',
  options: const [
    _formFormfieldValidate,
  ],
  build: (context, o) => _Signup(
    validate: AutovalidateMode.values.byName(o(_formFormfieldValidate)),
  ),
  code: (o) => [
    'final _form = GlobalKey<FormState>();',
    'String? _submitted;',
    "var _name = '';",
    '',
    '@override',
    'Widget build(BuildContext context) => Form(',
    '  key: _form,',
    if (o(_formFormfieldValidate) != 'disabled')
      '  autovalidateMode: .${o.nameOf(_formFormfieldValidate)},',
    '  onSubmitted: () => setState(() => _submitted = _name),',
    '  child: SizedBox(',
    '    width: 40,',
    '    child: Column(',
    '      mainAxisSize: .min,',
    '      crossAxisAlignment: .stretch,',
    '      spacing: 1,',
    '      children: [',
    '        TextFormField(',
    "          placeholder: 'name',",
    "          validator: (name) => name!.isEmpty ? 'a name, please' : null,",
    '          onSaved: (name) => _name = name!,',
    '        ),',
    '        TextFormField(',
    "          placeholder: 'email',",
    '          validator: (email) =>',
    "              email!.contains('@') ? null : 'an email has an @ in it',",
    '        ),',
    '        FormField<bool>(',
    '          initialValue: false,',
    '          validator: (accepted) =>',
    "              accepted! ? null : 'the terms are to be accepted',",
    '          builder: (field) => Checkbox(',
    '            value: field.value!,',
    '            onChanged: field.didChange,',
    "            label: 'I accept the terms',",
    '          ),',
    '        ),',
    '        Row(',
    '          spacing: 2,',
    '          children: [',
    _submitLine,
    _resetLine,
    '            Expanded(',
    '              child: Text.rich(',
    '                [',
    "                  Span(' submitted: ', Theme.of(context).muted),",
    '                  if (_submitted case final submitted?)',
    '                    Span(submitted)',
    '                  else',
    "                    Span('nothing', Theme.of(context).muted),",
    '                ],',
    '                wrap: .none,',
    '                overflow: .ellipsis,',
    '              ),',
    '            ),',
    '          ],',
    '        ),',
    '      ],',
    '    ),',
    '  ),',
    ');',
  ].join('\n'),
);

const _submitLine =
    "            Button('Submit', onPressed: () => "
    '_form.currentState!.submit()),';

const _resetLine =
    "            Button('Reset', onPressed: () => "
    '_form.currentState!.reset()),';

/// A form of a name, an email and the terms, submitted or reset together.
final class _Signup extends StatefulWidget {
  const _Signup({required this.validate});

  final AutovalidateMode validate;

  @override
  State<_Signup> createState() => _SignupState();
}

final class _SignupState extends State<_Signup> with KeptState {
  final _form = GlobalKey<FormState>();
  var _name = '';

  @override
  Widget build(BuildContext context) {
    final submitted = keptOr<String?>('submitted', null);
    return Form(
      key: _form,
      autovalidateMode: widget.validate,
      onSubmitted: () => keep('submitted', _name),
      child: SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 1,
          children: [
            TextFormField(
              placeholder: 'name',
              validator: (name) => name!.isEmpty ? 'a name, please' : null,
              onSaved: (name) => _name = name!,
            ),
            TextFormField(
              placeholder: 'email',
              validator: (email) =>
                  email!.contains('@') ? null : 'an email has an @ in it',
            ),
            FormField<bool>(
              initialValue: false,
              validator: (accepted) =>
                  accepted! ? null : 'the terms are to be accepted',
              builder: (field) => Checkbox(
                value: field.value!,
                onChanged: field.didChange,
                label: 'I accept the terms',
              ),
            ),
            Row(
              spacing: 2,
              children: [
                Button(
                  'Submit',
                  onPressed: () => _form.currentState!.submit(),
                ),
                Button('Reset', onPressed: () => _form.currentState!.reset()),
                Expanded(
                  child: LitLine(
                    [
                      (' submitted: ', true),
                      if (submitted == null)
                        ('nothing', true)
                      else
                        (submitted, false),
                    ],
                    serial: serial,
                    wrap: TextWrap.none,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
