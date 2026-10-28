/// What opens a file at a line for the console: [editorCommand], from
/// `TWK_EDITOR`, `VISUAL` or `EDITOR`.
library;

/// A command that opens a file: `executable` with `arguments`, run in the
/// app's terminal while the app waits (`inTerminal`: a terminal editor),
/// or apart from it (an editor with a window of its own).
typedef EditorCommand = ({
  String executable,
  List<String> arguments,
  bool inTerminal,
});

/// The command that opens [file] at [line] and [column] (from 1), as
/// [environment] asks:
///
/// * `TWK_EDITOR`, a command whose `{file}`, `{line}` and `{column}` are
///   put in (`code -g {file}:{line}:{column}`, `idea --line {line}
///   {file}`, `nvim +{line} {file}`); words in quotes keep their blanks;
/// * else `VISUAL`, else `EDITOR`, an editor's command, given the file
///   and line as that editor takes them: `+line file` for vi, Vim,
///   Neovim, nano, Emacs, micro and Kakoune, `file:line:column` for
///   Helix, Zed and Sublime Text, `-g file:line:column` for VS Code,
///   `--line line file` for the JetBrains IDEs, the file alone for
///   another.
///
/// It runs in the terminal when its executable is one of the terminal
/// editors above (Emacs with `-nw` or `-t`); else apart. Null where none
/// of the three is set.
EditorCommand? editorCommand(
  Map<String, String> environment,
  String file,
  int line,
  int column,
) {
  final template = environment['TWK_EDITOR'];
  if (template != null && template.trim().isNotEmpty) {
    final words = [
      for (final w in _words(template))
        w
            .replaceAll('{file}', file)
            .replaceAll('{line}', '$line')
            .replaceAll('{column}', '$column'),
    ];
    return (
      executable: words.first,
      arguments: words.sublist(1),
      inTerminal: _inTerminal(words),
    );
  }
  final editor = [
    environment['VISUAL'],
    environment['EDITOR'],
  ].firstWhere((e) => e != null && e.trim().isNotEmpty, orElse: () => null);
  if (editor == null) {
    return null;
  }
  final words = _words(editor);
  final name = _name(words.first);
  final at = switch (name) {
    'vi' ||
    'vim' ||
    'nvim' ||
    'nano' ||
    'emacs' ||
    'emacsclient' ||
    'micro' ||
    'kak' => ['+$line', file],
    'hx' || 'helix' || 'zed' || 'subl' => ['$file:$line:$column'],
    'code' || 'code-insiders' || 'codium' || 'cursor' => [
      '-g',
      '$file:$line:$column',
    ],
    'idea' || 'webstorm' || 'clion' || 'pycharm' || 'studio' => [
      '--line',
      '$line',
      file,
    ],
    _ => [file],
  };
  final all = [...words, ...at];
  return (
    executable: all.first,
    arguments: all.sublist(1),
    inTerminal: _inTerminal(all),
  );
}

/// Whether the command [words] is a terminal editor's.
bool _inTerminal(List<String> words) => switch (_name(words.first)) {
  'vi' ||
  'vim' ||
  'nvim' ||
  'nano' ||
  'micro' ||
  'kak' ||
  'hx' ||
  'helix' => true,
  'emacs' || 'emacsclient' => words.contains('-nw') || words.contains('-t'),
  _ => false,
};

/// The name of [executable], its directory and an `.exe` left out.
String _name(String executable) {
  final base = executable.split(RegExp(r'[/\\]')).last;
  return base.toLowerCase().endsWith('.exe')
      ? base.substring(0, base.length - 4)
      : base;
}

/// [command] in words: apart at blanks, but in single or double quotes.
List<String> _words(String command) {
  final out = <String>[];
  final word = StringBuffer();
  var inWord = false;
  String? quote;
  for (final ch in command.split('')) {
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        word.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) {
        out.add('$word');
        word.clear();
        inWord = false;
      }
    } else {
      word.write(ch);
      inWord = true;
    }
  }
  if (inWord) {
    out.add('$word');
  }
  return out;
}
