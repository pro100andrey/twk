// The log an app serves as the extension reads it (core/app_log.ts): the
// address file as twk_core's LocalAddress writes it, a record as
// LogRecord.toJson writes it, the frames of a stack and the packages that
// make them places of code, the levels and word that filter.
import * as assert from 'node:assert/strict';

import { Level, formatTime, matchesFilter, parseAddressFile, parseFrames, parsePackages, parseRecord, resolveUri } from '../../../core/app_log';

describe('the address file of an app\'s log', () => {
  it('holds the place and the token on a line each', () => {
    assert.deepEqual(parseAddressFile('unix:/tmp/twk-1/logs-7-0.sock\nabc123\n'), { where: 'unix:/tmp/twk-1/logs-7-0.sock', token: 'abc123' });
    assert.deepEqual(parseAddressFile('tcp:127.0.0.1:4040\r\nabc\r\n'), { where: 'tcp:127.0.0.1:4040', token: 'abc' });
  });

  it('is nothing for anything else', () => {
    for (const text of ['', 'unix:/tmp/x\n', 'file:/tmp/x\ntoken\n', 'tcp:host:1\ntoken\n', '\ntoken']) {
      assert.equal(parseAddressFile(text), undefined, JSON.stringify(text));
    }
  });
});

describe('a record of the log', () => {
  it('is what LogRecord.toJson writes: time, level, message, and the error and stack where there are', () => {
    const r = parseRecord(
      JSON.stringify({ time: '2026-01-01T09:05:07.042', level: 'warning', message: 'retrying', error: 'timeout', stack: '#0 f (file:///a.dart:1:2)' }),
      5,
    );
    assert.equal(r.level, 'warning');
    assert.equal(r.message, 'retrying');
    assert.equal(r.error, 'timeout');
    assert.equal(r.stack, '#0 f (file:///a.dart:1:2)');
    assert.equal(formatTime(r.time), '09:05:07.042');
    assert.equal(parseRecord(JSON.stringify({ time: '2026-01-01T09:05:07', level: 'info', message: 'm' }), 5).error, undefined);
  });

  it('is the line itself, at the time it came, where the line is no record (a text, another level, no time)', () => {
    for (const line of ['plain text', '{"level":"info","message":"m"}', '{"time":"2026-01-01T00:00:00","level":"loud","message":"m"}', '[1]', '{']) {
      assert.deepEqual(parseRecord(line, 77), { time: 77, level: 'info', message: line }, line);
    }
  });
});

describe('the frames of a stack', () => {
  it('give the place of the VM\'s lines and of package:stack_trace\'s, from 1', () => {
    const frames = parseFrames(
      [
        '#0      main (file:///home/me/app/bin/main.dart:10:5)',
        '#1      _run (package:app/src/run.dart:3)',
        '#2      _rootRun (dart:async/zone.dart:1399:13)',
        'package:app/util.dart 7:9  helper',
        '',
        '#3      win (file:///C:/app/lib/x.dart:4:1)',
      ].join('\n'),
    );
    assert.deepEqual(
      frames.map((f) => f.place),
      [
        { uri: 'file:///home/me/app/bin/main.dart', line: 10, column: 5 },
        { uri: 'package:app/src/run.dart', line: 3, column: 1 },
        undefined,
        { uri: 'package:app/util.dart', line: 7, column: 9 },
        { uri: 'file:///C:/app/lib/x.dart', line: 4, column: 1 },
      ],
    );
    assert.equal(frames[0].text, '#0      main (file:///home/me/app/bin/main.dart:10:5)');
  });
});

describe('the packages of a package configuration', () => {
  const config = JSON.stringify({
    configVersion: 2,
    packages: [
      { name: 'app', rootUri: '../', packageUri: 'lib/' },
      { name: 'dep', rootUri: '../../dep', packageUri: 'lib' },
      { name: 'abs', rootUri: 'file:///opt/abs/', packageUri: 'src/' },
    ],
  });
  const packages = parsePackages(config, 'file:///home/me/app/.dart_tool/package_config.json');

  it('are resolved against the file, relative or not', () => {
    assert.equal(resolveUri('package:app/src/run.dart', packages), 'file:///home/me/app/lib/src/run.dart');
    assert.equal(resolveUri('package:dep/d.dart', packages), 'file:///home/me/dep/lib/d.dart');
    assert.equal(resolveUri('package:abs/a.dart', packages), 'file:///opt/abs/src/a.dart');
  });

  it('leave a file: as it is, and an unknown package or a text that is no configuration unresolved', () => {
    assert.equal(resolveUri('file:///x/y.dart', packages), 'file:///x/y.dart');
    assert.equal(resolveUri('package:nope/x.dart', packages), undefined);
    assert.equal(resolveUri('dart:core/x.dart', packages), undefined);
    assert.equal(parsePackages('not json', 'file:///a/b.json').size, 0);
  });
});

describe('what the levels and the word show', () => {
  const row = { level: 'warning' as Level, message: 'Retrying', error: 'Timeout', stack: [{ text: '#0 Fetch (file:///a.dart:1:1)' }] };
  const all = new Set<Level>(['debug', 'info', 'warning', 'error']);

  it('is a record of a level on', () => {
    assert.equal(matchesFilter(row, all, ''), true);
    assert.equal(matchesFilter(row, new Set<Level>(['error']), ''), false);
  });

  it('is one with the word (lowercase) in its message, error or stack', () => {
    for (const word of ['retry', 'timeout', 'fetch']) {
      assert.equal(matchesFilter(row, all, word), true, word);
    }
    assert.equal(matchesFilter(row, all, 'absent'), false);
  });
});
