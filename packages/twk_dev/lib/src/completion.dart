/// `twk completion`: the completion script of a shell for the `twk` command.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

/// The shells `twk completion` writes a script for.
enum CompletionShell {
  /// bash, for `source <(twk completion bash)`.
  bash,

  /// zsh, for a file `_twk` in the `fpath`.
  zsh,

  /// fish, for `twk completion fish | source`.
  fish,
}

/// What a command's positional arguments are completed with.
enum PositionalKind {
  /// None: the command takes no positional argument.
  none,

  /// Files, those matching [Positionals.glob] when it is set.
  files,

  /// Directories.
  directories,
}

/// The positional arguments a command takes, for its completion.
final class Positionals {
  /// No positional argument.
  const Positionals.none() : kind = PositionalKind.none, glob = null;

  /// Files, any or only those matching [glob] (`*.cast`).
  const Positionals.files({this.glob}) : kind = PositionalKind.files;

  /// Directories.
  const Positionals.directories()
    : kind = PositionalKind.directories,
      glob = null;

  /// What the arguments are.
  final PositionalKind kind;

  /// The pattern of the files taken, null for any file.
  final String? glob;
}

/// What the value of an option is completed with, when it is not free text
/// or one of its `allowed` values.
enum OptionPath {
  /// A directory.
  directory,

  /// A file.
  file,
}

/// A command that says what its arguments are completed with: every command
/// of `twk` has it, so a new one cannot be completed wrongly unnoticed.
mixin Completes on Command<int> {
  /// What the positional arguments of the command are.
  Positionals get positionals;

  /// The options whose value is a path, by name; the others are free text or
  /// have `allowed` values.
  Map<String, OptionPath> get optionPaths => const {};
}

Positionals _positionalsOf(Command<Object?> c) =>
    c is Completes ? c.positionals : const Positionals.none();

/// The script of [shell] that completes `twk`'s subcommands, the options of
/// each (`--no-` forms of the negatable flags, the allowed values of an
/// option, directories for `--directory`, files for `--out`) and, by
/// command, the files its arguments take (`.cast` for `play`, `.tape` for
/// `tape`, `.dart` for `run`).
///
/// It is written from [runner]'s commands and their parsers, so a command or
/// option added there is in it.
String completionScript(CommandRunner<Object?> runner, CompletionShell shell) {
  final commands = [
    for (final c in runner.commands.values)
      if (!c.hidden) c,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return switch (shell) {
    CompletionShell.bash => _bash(runner, commands),
    CompletionShell.zsh => _zsh(runner, commands),
    CompletionShell.fish => _fish(runner, commands),
  };
}

/// What an option's value is: a directory, a file, a fixed set, or free.
enum _Value { free, directory, file, allowed }

_Value _valueOf(Command<Object?> c, Option o) {
  if (o.allowed != null && o.allowed!.isNotEmpty) {
    return _Value.allowed;
  }
  final path = c is Completes ? c.optionPaths[o.name] : null;
  return switch (path) {
    OptionPath.directory => _Value.directory,
    OptionPath.file => _Value.file,
    null => _Value.free,
  };
}

String _firstLine(String? text) {
  final line = (text ?? '').split('\n').first.trim();
  return line;
}

/// The options of [parser], the `help` flag included, `hide`-den ones left.
List<Option> _options(ArgParser parser) => [
  for (final o in parser.options.values)
    if (!o.hide) o,
];

String _sq(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// Every spelling of [o] on a command line.
List<String> _spellings(Option o) => [
  '--${o.name}',
  if (o.abbr != null) '-${o.abbr}',
  if (o.isFlag && (o.negatable ?? false)) '--no-${o.name}',
];

// --- bash ---

/// [template] with each `@key@` replaced by its value in [values].
String _fill(String template, Map<String, String> values) => template
    .replaceAllMapped(RegExp(r'@(\w+)@'), (m) => values[m[1]!] ?? m[0]!);

String _bash(CommandRunner<Object?> runner, List<Command<Object?>> commands) {
  final b = StringBuffer(
    _fill(
      r'''
# bash completion for twk: source <(twk completion bash)
_twk_lines() {
  local line
  COMPREPLY=()
  while IFS= read -r line; do COMPREPLY+=("$line"); done
}
_twk() {
  local cur prev opt cmd i
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  opt=$prev
  if [[ $cur == = ]]; then cur=; fi
  if [[ $prev == = ]]; then opt=${COMP_WORDS[COMP_CWORD-2]}; fi
  cmd=
  for ((i = 1; i < COMP_CWORD; i++)); do
    case ${COMP_WORDS[i]} in
      -*) ;;
      *) cmd=${COMP_WORDS[i]}; break ;;
    esac
  done
  if [[ -z $cmd ]]; then
    _twk_lines < <(compgen -W "@top@" -- "$cur")
    return
  fi
  case $cmd in
''',
      {
        'top': [
          for (final c in commands) c.name,
          'help',
          for (final o in _options(runner.argParser)) ..._spellings(o),
        ].join(' '),
      },
    ),
  );
  for (final c in commands) {
    final opts = _options(c.argParser);
    b.writeln('    ${c.name})');
    final valued = [
      for (final o in opts)
        if (!o.isFlag) o,
    ];
    if (valued.isNotEmpty) {
      b.writeln(r'      case $opt in');
      for (final o in valued) {
        final names = _spellings(o).join('|');
        b.writeln(
          _fill(
            switch (_valueOf(c, o)) {
              _Value.allowed =>
                r'        @n@) _twk_lines < <(compgen -W "@w@" -- "$cur"); '
                    'return ;;',
              _Value.directory =>
                '        @n@) compopt -o filenames 2>/dev/null; '
                    r'_twk_lines < <(compgen -d -- "$cur"); return ;;',
              _Value.file =>
                '        @n@) compopt -o filenames 2>/dev/null; '
                    r'_twk_lines < <(compgen -f -- "$cur"); return ;;',
              _Value.free => '        @n@) return ;;',
            },
            {'n': names, 'w': (o.allowed ?? const []).join(' ')},
          ),
        );
      }
      b.writeln('      esac');
    }
    b.writeln(
      _fill(
        r'      if [[ $cur == -* ]]; then _twk_lines < <(compgen -W "@w@" '
        r'-- "$cur"); return; fi',
        {
          'w': [for (final o in opts) ..._spellings(o)].join(' '),
        },
      ),
    );
    final pos = _positionalsOf(c);
    if (pos.kind != PositionalKind.none) {
      b.writeln('      compopt -o filenames 2>/dev/null');
      if (pos.kind == PositionalKind.directories) {
        b.writeln(r'      _twk_lines < <(compgen -d -- "$cur")');
      } else if (pos.glob == null) {
        b.writeln(r'      _twk_lines < <(compgen -f -- "$cur")');
      } else {
        b.writeln(
          _fill(
            r'      _twk_lines < <(compgen -f -X @x@ -- "$cur"; '
            r'compgen -d -- "$cur")',
            {'x': _sq('!${pos.glob}')},
          ),
        );
      }
    }
    b.writeln('      ;;');
  }
  b
    ..writeln('  esac')
    ..writeln('}')
    ..writeln('complete -F _twk twk');
  return b.toString();
}

// --- zsh ---

String _zshText(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"'\''")
    .replaceAll('[', r'\[')
    .replaceAll(']', r'\]');

String _zshDescribe(String s) =>
    s.replaceAll(':', r'\:').replaceAll("'", r"'\''");

String _zsh(CommandRunner<Object?> runner, List<Command<Object?>> commands) {
  final b = StringBuffer()
    ..writeln('#compdef twk')
    ..writeln('# zsh completion for twk: twk completion zsh > ~/.zfunc/_twk')
    ..writeln('_twk() {')
    ..writeln('  local -a commands')
    ..writeln('  commands=(');
  for (final c in commands) {
    final name = _zshDescribe(c.name);
    final text = _zshDescribe(_firstLine(c.description));
    b.writeln("    '$name:$text'");
  }
  b
    ..writeln("    'help:Display help information for twk.'")
    ..writeln('  )')
    ..writeln("  _arguments -C '1: :->command' '*:: :->args' && return")
    ..writeln(r'  case $state in')
    ..writeln("    command) _describe -t commands 'twk command' commands ;;")
    ..writeln('    args)')
    ..writeln(r'      case $words[1] in');
  for (final c in commands) {
    b
      ..writeln('        ${c.name})')
      ..writeln(r'          _arguments \');
    for (final o in _options(c.argParser)) {
      b.writeln('            ${_zshOption(c, o)} \\');
    }
    final pos = _positionalsOf(c);
    if (pos.kind == PositionalKind.none) {
      b.writeln("            '*: :'");
    } else if (pos.kind == PositionalKind.directories) {
      b.writeln("            '*:directory:_files -/'");
    } else if (pos.glob == null) {
      b.writeln("            '*:argument:_files'");
    } else {
      b.writeln("            '*:file:_files -g \"${pos.glob}\"'");
    }
    b.writeln('          ;;');
  }
  b
    ..writeln('      esac')
    ..writeln('      ;;')
    ..writeln('  esac')
    ..writeln('}')
    ..writeln(r'if [[ $funcstack[1] == _twk ]]; then _twk "$@"; fi');
  return b.toString();
}

String _zshOption(Command<Object?> c, Option o) {
  final help = _zshText(_firstLine(o.help));
  if (o.isFlag) {
    final names = [
      if (o.abbr != null) '-${o.abbr}',
      '--${o.name}',
      if (o.negatable ?? false) '--no-${o.name}',
    ];
    return names.length == 1
        ? "'${names.single}[$help]'"
        : "{${names.join(',')}}'[$help]'";
  }
  final value = _zshText(o.valueHelp ?? 'value').replaceAll(':', r'\:');
  final action = switch (_valueOf(c, o)) {
    _Value.allowed => '(${o.allowed!.join(' ')})',
    _Value.directory => '_files -/',
    _Value.file => '_files',
    _Value.free => ' ',
  };
  final tail = "'[$help]:$value:$action'";
  return o.abbr != null
      ? '{-${o.abbr},--${o.name}=}$tail'
      : "'--${o.name}='$tail";
}

// --- fish ---

String _fishText(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

String _fish(CommandRunner<Object?> runner, List<Command<Object?>> commands) {
  final b = StringBuffer()
    ..writeln('# fish completion for twk: twk completion fish | source')
    ..writeln('complete -c twk -f')
    ..writeln(
      'complete -c twk -n __fish_use_subcommand -a help '
      "-d 'Display help information for twk.'",
    );
  for (final c in commands) {
    b.writeln(
      'complete -c twk -n __fish_use_subcommand -a ${c.name} '
      '-d ${_fishText(_firstLine(c.description))}',
    );
  }
  for (final c in commands) {
    final cond = "-n '__fish_seen_subcommand_from ${c.name}'";
    for (final o in _options(c.argParser)) {
      final sb = StringBuffer('complete -c twk $cond');
      if (o.abbr != null) {
        sb.write(' -s ${o.abbr}');
      }
      sb.write(' -l ${o.name}');
      if (!o.isFlag) {
        switch (_valueOf(c, o)) {
          case _Value.allowed:
            sb.write(" -x -a '${o.allowed!.join(' ')}'");
          case _Value.directory:
            sb.write(" -r -a '(__fish_complete_directories)'");
          case _Value.file:
            sb.write(' -r -F');
          case _Value.free:
            sb.write(' -x');
        }
      }
      sb.write(' -d ${_fishText(_firstLine(o.help))}');
      b.writeln(sb);
      if (o.isFlag && (o.negatable ?? false)) {
        b.writeln(
          'complete -c twk $cond -l no-${o.name} '
          '-d ${_fishText(_firstLine(o.help))}',
        );
      }
    }
    final pos = _positionalsOf(c);
    if (pos.kind != PositionalKind.none) {
      if (pos.kind == PositionalKind.directories) {
        b.writeln(
          "complete -c twk $cond -a '(__fish_complete_directories)'",
        );
      } else if (pos.glob == null) {
        b.writeln('complete -c twk $cond -F');
      } else {
        final suffix = pos.glob!.substring(1);
        b.writeln(
          "complete -c twk $cond -a '(__fish_complete_suffix $suffix)'",
        );
      }
    }
  }
  return b.toString();
}

/// `twk completion <shell>`: writes the completion script of a shell.
final class CompletionCommand extends Command<int> with Completes {
  @override
  Positionals get positionals => const Positionals.none();

  @override
  String get name => 'completion';

  @override
  String get invocation => 'twk completion <bash|zsh|fish>';

  @override
  String get description =>
      'Print the completion script of a shell for twk.\n\n'
      'bash: source <(twk completion bash)\n'
      'zsh: twk completion zsh > ~/.zfunc/_twk (a directory in fpath, '
      'then compinit)\n'
      'fish: twk completion fish > ~/.config/fish/completions/twk.fish';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Name one shell: bash, zsh or fish.');
    }
    final shell = CompletionShell.values
        .where((s) => s.name == rest.single)
        .firstOrNull;
    if (shell == null) {
      usageException('Unknown shell "${rest.single}": bash, zsh or fish.');
    }
    stdout.write(completionScript(runner!, shell));
    return 0;
  }
}
