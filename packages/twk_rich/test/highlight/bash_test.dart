// Bash: commands, keywords where a command starts, assignments and
// variables, comments, strings of every kind, substitutions, arithmetic,
// operators and redirections, case patterns, and the states that go on
// across lines: strings, substitutions and heredocs.
import 'package:test/test.dart';
import 'package:twk_rich/twk_rich.dart';

import 'tokens.dart';

String bash(String source) => lexed(bashLanguage, source);

void main() {
  test('the command of a command line', () {
    expect(bash('echo hello world'), 'function"echo" " hello world"');
    expect(
      bash('cat f 2>&1 | grep -v x && echo ok || exit 1; sleep 10&'),
      'function"cat" " f " number"2" operator">&" number"1" " " '
      'operator"|" " " function"grep" " -v x " operator"&&" " " '
      'function"echo" " ok " operator"||" " " function"exit" " " '
      'number"1" operator";" " " function"sleep" " " number"10" '
      'operator"&"',
    );
  });

  test('keywords where a command starts', () {
    expect(
      bash('if [ -f "\$f" ]; then\n  rm -f file1\nfi; echo done'),
      r'''
keyword"if" " " punctuation"[" " -f " string"\"" variable"$f" string"\"" " " punctuation"]" operator";" " " keyword"then"
"  " function"rm" " -f file1"
keyword"fi" operator";" " " function"echo" " done"''',
    );
    expect(
      bash(r'[[ -f $f && ! -L $f ]] && rm $f'),
      r'punctuation"[[" " -f " variable"$f" " " operator"&&" " " '
      r'operator"!" " -L " variable"$f" " " punctuation"]]" " " '
      r'operator"&&" " " function"rm" " " variable"$f"',
    );
    expect(
      bash('for f in *.txt; do ! test -d in; done'),
      'keyword"for" " f " keyword"in" " *.txt" operator";" " " '
      'keyword"do" " " operator"!" " " function"test" " -d in" '
      'operator";" " " keyword"done"',
    );
  });

  test('assignments and variables', () {
    expect(
      bash(r'NAME=value FOO+=1 cmd $HOME ${x:-${y}} $1 $@ $? $ local x=2'),
      'variable"NAME" operator"=" "value " variable"FOO" operator"+=" '
      r'number"1" " " function"cmd" " " variable"$HOME" " " '
      r'variable"${x:-${y}}" " " variable"$1" " " variable"$@" " " '
      r'variable"$?" " $ local " variable"x" operator"=" number"2"',
    );
  });

  test('comments start a word', () {
    expect(
      bash('#!/bin/bash\nls # list\necho a#b'),
      '''
comment"#!/bin/bash"
function"ls" " " comment"# list"
function"echo" " a#b"''',
    );
  });

  test('strings and escapes', () {
    expect(
      bash(r'''echo 'it''s' "a \"b\" \$c \x $d" $'x\ty' a\ b \'''),
      r'''function"echo" " " string"'it''s'" " " string"\"a " '''
      r'''escape"\\\"" string"b" escape"\\\"" string" " escape"\\$" '''
      r'''string"c \\x " variable"$d" string"\"" " " string"$'x" '''
      r'''escape"\\t" string"y'" " a" escape"\\ " "b " escape"\\"''',
    );
  });

  test('substitutions and arithmetic', () {
    expect(
      bash(r'x=$(date +%s) y=$((x + 1)) z=`pwd` w="$(id -u)"'),
      r'variable"x" operator"=" punctuation"$(" function"date" " +%s" '
      r'punctuation")" " " variable"y" operator"=" punctuation"$((" '
      'variable"x" " " operator"+" " " number"1" punctuation"))" " " '
      'variable"z" operator"=" punctuation"`" function"pwd" '
      r'punctuation"`" " " variable"w" operator"=" string"\"" '
      r'punctuation"$(" function"id" " -u" punctuation")" string"\""',
    );
    expect(
      bash('(( i++ ))'),
      'punctuation"((" " " variable"i" operator"++" " " punctuation"))"',
    );
  });

  test('functions, groups and case patterns', () {
    expect(
      bash('function deploy {\nbuild() { make; }'),
      '''
keyword"function" " " function"deploy" " " punctuation"{"
function"build" punctuation"()" " " punctuation"{" " " function"make" operator";" " " punctuation"}"''',
    );
    expect(
      bash(
        'case \$x in\n  start|up) run ;;\n  *) usage ;;\nesac',
      ),
      r'''
keyword"case" " " variable"$x" " " keyword"in"
"  start" operator"|" "up" punctuation")" " " function"run" " " operator";;"
"  *" punctuation")" " " function"usage" " " operator";;"
keyword"esac"''',
    );
  });

  group('across lines', () {
    test('strings go on to their closing quote', () {
      expect(
        bash("echo \"one\ntwo \$x\" 'three\nfour'"),
        r'''
function"echo" " " string"\"one"
string"two " variable"$x" string"\"" " " string"'three"
string"four'"''',
      );
    });

    test('a substitution goes on to its closing parenthesis', () {
      expect(
        bash(
          r'x=$('
          '\n  ls; (cd a)\n) "`b\nc`"',
        ),
        r'''
variable"x" operator"=" punctuation"$("
"  " function"ls" operator";" " " punctuation"(" function"cd" " a" punctuation")"
punctuation")" " " string"\"" punctuation"`" function"b"
function"c" punctuation"`" string"\""''',
      );
    });

    test('a heredoc goes on to its delimiter', () {
      expect(
        bash(
          'cat <<EOF > out\nHello \$USER \$(id)\n\\\$HOME "x"\nEOF\n'
          "cat <<-'END'\n\traw \$x\n\tEND\necho done",
        ),
        r'''
function"cat" " " operator"<<" string"EOF" " " operator">" " out"
string"Hello " variable"$USER" string" " punctuation"$(" function"id" punctuation")"
escape"\\$" string"HOME \"x\""
string"EOF"
function"cat" " " operator"<<-" string"'END'"
string"\traw $x"
string"\tEND"
function"echo" " done"''',
      );
    });
  });

  test('an edit that opens a heredoc lexes the lines down to its end', () {
    final code = Highlighter(
      bashLanguage,
      'a\nb\nc "x"\nEND\nd\ne',
    );
    expect(code.replaceLines(1, 2, ['cat <<END']), 3);
    expect(describe(code.tokens(2)), r'string"c \"x\""');
    expect(describe(code.tokens(4)), 'function"d"');
  });
}
