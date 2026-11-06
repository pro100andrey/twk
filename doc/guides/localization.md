---
title: "Words in another language"
about: "TwkStrings and Localizations: the words twk writes itself, in your language, from slang or anything else."
order: 9
---
# Words in another language

twk writes a few words of its own: the `ETA` of a progress list, `Y/n` after
a question, `answer y or n` when the answer was neither. They are English
until you give others. They are one plain class, `TwkStrings`, with English
defaults and no dependencies: twk has no localization package and no
generator, and no global to set. Your translations, from whatever holds
them, become a `TwkStrings` that you pass at the root.

```text
const german = TwkStrings(
  eta: _eta,
  yes: 'ja',
  no: 'nein',
  yesLabel: 'Ja',
  noLabel: 'Nein',
);
String _eta(String time) => 'noch $time';
```

A message with a number or a time in it is a function of that value, so a
language puts it where it belongs.

## An app

`Localizations(strings:, child:)` at the top of the app. Widgets read the
words with `TwkStrings.of(context)`; changing the object builds again those
that read it, as it does for a `Theme`.

```text
runApp(
  Localizations(
    strings: german,
    child: const App(),
  ),
);
```

## A console

A `Cli` has no `BuildContext` in its plain text, so it takes the words
itself: `Cli(strings:)`, or `strings:` of `Cli.run` and `Cli.runWithArgs`.
What it shows or asks in its inline session is wrapped in `Localizations`
for you, as it is in your `Theme`.

```text
Cli.runWithArgs(args, strings: german, (cli, rest) async {
  if (!await cli.confirm('Weiter?')) return;
});
```

On a plain terminal a yes or no is read as `y`, `yes`, `n` and `no`
whatever the language, and as the `yes` and `no` of the strings, or their
first letters, too.

## With slang

[slang](https://pub.dev/packages/slang) generates a `Translations` class
from files; a function from it to `TwkStrings` is the whole of the glue. Put
the words in a `twk` section of the strings file:

```text
# strings.i18n.yaml (en); the other languages have the same keys
twk:
  eta: ETA $time
  tookIn: ' in $took'
  moreTasks: '+$count more'
  yes: 'yes'
  no: 'no'
  none: none
  yesLabel: 'Yes'
  noLabel: 'No'
  confirmHint: y/n
  confirmHintYes: Y/n
  confirmHintNo: y/N
  answerYesOrNo: answer y or n
  enterNumber: Enter a number
  enterNumbers: Enter numbers separated by commas
  answerNumber: answer a number from 1 to $count
  answerNumbers: answer numbers from 1 to $count
  chooseAtLeast: choose at least $min
  chooseAtMost: choose at most $max
  typeToFilter: type to filter
  spaceToToggle: space to toggle
  typeToFilterAndToggle: type to filter, space to toggle
```

```text
TwkStrings twkStrings(Translations t) => TwkStrings(
  eta: (time) => t.twk.eta(time: time),
  tookIn: (took) => t.twk.tookIn(took: took),
  moreTasks: (count) => t.twk.moreTasks(count: count),
  yes: t.twk.yes,
  no: t.twk.no,
  none: t.twk.none,
  yesLabel: t.twk.yesLabel,
  noLabel: t.twk.noLabel,
  confirmHint: t.twk.confirmHint,
  confirmHintYes: t.twk.confirmHintYes,
  confirmHintNo: t.twk.confirmHintNo,
  answerYesOrNo: t.twk.answerYesOrNo,
  enterNumber: t.twk.enterNumber,
  enterNumbers: t.twk.enterNumbers,
  answerNumber: (count) => t.twk.answerNumber(count: count),
  answerNumbers: (count) => t.twk.answerNumbers(count: count),
  chooseAtLeast: (min) => t.twk.chooseAtLeast(min: min),
  chooseAtMost: (max) => t.twk.chooseAtMost(max: max),
  typeToFilter: t.twk.typeToFilter,
  spaceToToggle: t.twk.spaceToToggle,
  typeToFilterAndToggle: t.twk.typeToFilterAndToggle,
);
```

A console passes the translations explicitly, with no global locale:

```text
final t = AppLocale.ru.build();
await Cli.runWithArgs(args, strings: twkStrings(t), body);
```

An app puts `Localizations(strings: twkStrings(t), child: ...)` at its
root, and builds it again with another `t` when the language changes.
