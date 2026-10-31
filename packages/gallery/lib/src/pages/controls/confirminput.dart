// The ConfirmInput page.
part of 'controls.dart';

final _confirminputPage = GalleryPage(
  group: 'Controls',
  title: 'ConfirmInput',
  options: const [
    ChoiceOption(
      'default',
      'default',
      values: [true, false],
      labels: ['yes', 'no'],
    ),
    ChoiceOption('labels', 'answers', values: ['Yes, No', 'Delete, Keep']),
  ],
  build: (context, o) => _Confirm(
    defaultValue: o.choice('default'),
    answers: _answers[o.choice<String>('labels')]!,
  ),
  code: (o) {
    final (yes, no) = _answers[o.choice<String>('labels')]!;
    return [
      'bool? _answer;',
      '',
      '@override',
      'Widget build(BuildContext context) => Column(',
      '  mainAxisSize: .min,',
      '  crossAxisAlignment: .start,',
      '  gap: 1,',
      '  children: [',
      '    ConfirmInput(',
      "      'Delete 3 files?',",
      '      // it reads defaultValue once: another is a new input',
      '      key: const ValueKey(${o['default']}),',
      '      defaultValue: ${o['default']},',
      if (yes != 'Yes') ...["      yes: '$yes',", "      no: '$no',"],
      '      onConfirmed: (yes) => setState(() => _answer = yes),',
      '    ),',
      '    Text.rich([',
      "      Span('answer: ', Theme.of(context).muted),",
      '      switch (_answer) {',
      "        null => Span('nothing', Theme.of(context).muted),",
      "        true => const Span('yes'),",
      "        false => const Span('no'),",
      '      },',
      '    ]),',
      '  ],',
      ');',
    ].join('\n');
  },
);

/// The answers of the ConfirmInput page, yes and no, by the option's value.
const _answers = {
  'Yes, No': ('Yes', 'No'),
  'Delete, Keep': ('Delete', 'Keep'),
};

/// A question answered yes or no, and the answer.
final class _Confirm extends StatefulWidget {
  const _Confirm({required this.defaultValue, required this.answers});

  final bool defaultValue;
  final (String, String) answers;

  @override
  State<_Confirm> createState() => _ConfirmState();
}

final class _ConfirmState extends State<_Confirm> with KeptState {
  @override
  Widget build(BuildContext context) {
    final answer = keptOr<bool?>('answer', null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      gap: 1,
      children: [
        ConfirmInput(
          'Delete 3 files?',
          // it reads defaultValue once: another is a new input
          key: ValueKey(widget.defaultValue),
          defaultValue: widget.defaultValue,
          yes: widget.answers.$1,
          no: widget.answers.$2,
          onConfirmed: (yes) => keep('answer', yes),
        ),
        LitLine([
          ('answer: ', true),
          switch (answer) {
            null => ('nothing', true),
            true => ('yes', false),
            false => ('no', false),
          },
        ], serial: serial),
      ],
    );
  }
}
