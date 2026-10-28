// The states an app sets on a HeadlessTerminal (TerminalStateBackend):
// written as set, put back when the terminal is handed over or closed.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

void main() {
  /// What [term] wrote, from frame [from] on, as one string.
  String written(HeadlessTerminal term, [int from = 0]) =>
      term.frames.skip(from).map(ascii.decode).join();

  test('a state set is written; closing puts the states back, the last '
      'set first', () async {
    final term = HeadlessTerminal()
      ..setTerminalState(#title, '<title>', '</title>')
      ..setTerminalState(#cursor, '<cursor>', '</cursor>');
    expect(written(term), '<title><cursor>');
    await term.close();
    expect(written(term, 2), '</cursor></title>');
  });

  test('a state restored is put back at once and forgotten', () async {
    final term = HeadlessTerminal()
      ..setTerminalState(#title, '<title>', '</title>')
      ..restoreTerminalState(#title)
      ..restoreTerminalState(#title);
    expect(written(term), '<title></title>');
    await term.close();
    expect(written(term), '<title></title>');
  });

  test('handed over, the states are put back; taken back, set again in '
      'the order they were first set', () async {
    final term = HeadlessTerminal()
      ..setTerminalState(#a, '<a>', '</a>')
      ..setTerminalState(#b, '<b>', '</b>');
    await term.suspend();
    expect(written(term, 2), '</b></a>');
    await term.resume();
    expect(written(term, 3), '<a><b>');
  });

  test('while handed over a state set waits for the terminal to be taken '
      'back, and one restored is not written', () async {
    final term = HeadlessTerminal()..setTerminalState(#a, '<a>', '</a>');
    await term.suspend();
    final before = term.frames.length;
    term
      ..setTerminalState(#b, '<b>', '</b>')
      ..restoreTerminalState(#a);
    expect(term.frames.length, before);
    await term.resume();
    expect(written(term, before), '<b>');
  });

  test('closed while handed over, nothing is put back again', () async {
    final term = HeadlessTerminal()..setTerminalState(#a, '<a>', '</a>');
    await term.suspend();
    await term.close();
    expect(written(term), '<a></a>');
  });

  test('once closed, setting or restoring a state writes nothing', () async {
    final term = HeadlessTerminal()..setTerminalState(#a, '<a>', '</a>');
    await term.close();
    final before = term.frames.length;
    term
      ..setTerminalState(#b, '<b>', '</b>')
      ..restoreTerminalState(#a)
      ..restoreTerminalState(#b);
    expect(term.frames.length, before);
  });
}
