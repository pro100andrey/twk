/// The languages this package highlights, and finding one by name.
library;

import 'lang/bash.dart';
import 'lang/dart.dart';
import 'lang/diff.dart';
import 'lang/go.dart';
import 'lang/javascript.dart';
import 'lang/json.dart';
import 'lang/python.dart';
import 'lang/rust.dart';
import 'lang/yaml.dart';
import 'lexer.dart';

export 'lang/bash.dart';
export 'lang/dart.dart';
export 'lang/diff.dart';
export 'lang/go.dart';
export 'lang/javascript.dart';
export 'lang/json.dart';
export 'lang/python.dart';
export 'lang/rust.dart';
export 'lang/yaml.dart';

/// The languages this package highlights, by name: a language is added
/// here, its file imported and exported above.
const List<Language> languages = [
  bashLanguage,
  dartLanguage,
  diffLanguage,
  goLanguage,
  javascriptLanguage,
  jsonLanguage,
  pythonLanguage,
  rustLanguage,
  typescriptLanguage,
  yamlLanguage,
];

/// The language of [among] that is [name] or goes by it, in any case, such
/// as the language of a Markdown code fence; [Language.plain] when none
/// does.
Language languageNamed(String name, {List<Language> among = languages}) {
  for (final language in among) {
    if (language.isNamed(name)) {
      return language;
    }
  }
  return Language.plain;
}
