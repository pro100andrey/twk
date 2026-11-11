// Following the log of an app (core/log_follow.ts) over a fake address file
// and socket and a fake clock, as `twk logs` does: waits for an address,
// connects, tells the lines, waits for the next app when one ends; and node's
// endpoints (core/log_socket.ts) over a real local socket and file.
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as net from 'node:net';
import * as os from 'node:os';
import * as path from 'node:path';

import { LogFollower, LogFollowing } from '../../../core/log_follow';
import { Lines, nodeLogEndpoints } from '../../../core/log_socket';
import { FakeClock, FakeLogEndpoints, until } from '../fakes';

describe('LogFollower', () => {
  let endpoints: FakeLogEndpoints;
  let clock: FakeClock;
  let told: string[];
  const following: LogFollowing = {
    connected: () => told.push('connected'),
    line: (t) => told.push(`line ${t}`),
    ended: () => told.push('ended'),
  };
  const followers: LogFollower[] = [];
  const follow = () => {
    const f = new LogFollower('/p', endpoints, clock, following);
    followers.push(f);
    return f;
  };

  beforeEach(() => {
    endpoints = new FakeLogEndpoints();
    clock = new FakeClock();
    told = [];
  });
  afterEach(() => followers.splice(0).forEach((f) => f.dispose()));

  it('waits for the address file every 200 ms, then connects and tells the lines', async () => {
    follow();
    clock.elapse(199);
    assert.equal(endpoints.connected.length, 0);
    endpoints.serve('/p', 'one');
    clock.elapse(1);
    await until('the connection', () => told.length > 0);
    assert.deepEqual(endpoints.connected.map((a) => a.token), ['one']);
    endpoints.connections[0].line('a');
    endpoints.connections[0].line('b');
    assert.deepEqual(told, ['connected', 'line a', 'line b']);
    assert.equal(clock.pending, 0, 'no polling while connected');
  });

  it('waits for the next app when one ends, and does not connect again to the address that ended', async () => {
    endpoints.serve('/p', 'one');
    follow();
    await until('the connection', () => told.length > 0);
    endpoints.connections[0].end();
    assert.deepEqual(told, ['connected', 'ended']);
    clock.elapse(200);
    clock.elapse(200);
    assert.equal(endpoints.connected.length, 1);
    endpoints.serve('/p', 'two');
    clock.elapse(200);
    await until('the second connection', () => endpoints.connected.length === 2);
    assert.deepEqual(told, ['connected', 'ended', 'connected']);
  });

  it('tries again when no one listens at the address (an app that did not stop left it)', async () => {
    endpoints.serve('/p', 'stale');
    endpoints.refused.add('stale');
    follow();
    await new Promise((r) => setImmediate(r));
    clock.elapse(200);
    await new Promise((r) => setImmediate(r));
    assert.deepEqual(told, []);
    endpoints.refused.clear();
    clock.elapse(200);
    await until('the connection', () => told.length > 0);
    assert.deepEqual(told, ['connected']);
  });

  it('closes the connection and stops waiting once disposed', async () => {
    endpoints.serve('/p', 'one');
    const f = follow();
    await until('the connection', () => told.length > 0);
    f.dispose();
    assert.equal(endpoints.connections[0].closed, true);
    assert.equal(clock.pending, 0);
    const g = follow();
    g.dispose();
    assert.equal(clock.pending, 0);
  });

  it('is disposed while a connection is being made: it is closed', async () => {
    endpoints.serve('/p', 'one');
    const f = follow();
    f.dispose();
    await until('the connection', () => endpoints.connections.length > 0);
    await new Promise((r) => setImmediate(r));
    assert.equal(endpoints.connections[0].closed, true);
    assert.deepEqual(told, []);
  });
});

describe('Lines', () => {
  it('cuts what is read into lines, a character and a line cut between reads put together', () => {
    const lines = new Lines();
    const bytes = Buffer.from('é1\r\nsecond\nth', 'utf8');
    assert.deepEqual(lines.push(bytes.subarray(0, 1)), []);
    assert.deepEqual(lines.push(bytes.subarray(1)), ['é1', 'second']);
    assert.deepEqual(lines.push(Buffer.from('ird\n')), ['third']);
  });
});

describe('the endpoints of node', () => {
  let dir: string;
  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), 'twk-logs-'));
  });
  afterEach(() => fs.rmSync(dir, { recursive: true, force: true }));

  it('read the address file of a project, and none where there is none or it is garbled', () => {
    assert.equal(nodeLogEndpoints.address(dir), undefined);
    fs.mkdirSync(path.join(dir, '.dart_tool', 'twk'), { recursive: true });
    fs.writeFileSync(path.join(dir, '.dart_tool', 'twk', 'logs'), 'garbage');
    assert.equal(nodeLogEndpoints.address(dir), undefined);
    fs.writeFileSync(path.join(dir, '.dart_tool', 'twk', 'logs'), 'unix:/tmp/x.sock\ntok\n');
    assert.deepEqual(nodeLogEndpoints.address(dir), { where: 'unix:/tmp/x.sock', token: 'tok' });
  });

  it('connect to a socket, send the token and a line feed first, and tell the lines and the end', async () => {
    const socketPath = path.join(dir, 'logs.sock');
    const received: string[] = [];
    let serverSide: net.Socket | undefined;
    const server = net.createServer((s) => {
      serverSide = s;
      s.on('data', (b) => {
        received.push(b.toString('utf8'));
        s.write('{"a":1}\n{"b"');
      });
    });
    await new Promise<void>((r) => server.listen(socketPath, r));
    try {
      const connection = await nodeLogEndpoints.connect({ where: `unix:${socketPath}`, token: 'secret' });
      const lines: string[] = [];
      let ended = false;
      connection.onLine((l) => lines.push(l));
      connection.onEnd(() => (ended = true));
      await until('the first line', () => lines.length === 1);
      assert.deepEqual(received, ['secret\n']);
      serverSide!.end(':2}\n');
      await until('the end', () => ended);
      assert.deepEqual(lines, ['{"a":1}', '{"b":2}']);
    } finally {
      await new Promise((r) => server.close(r));
    }
  });

  it('reject where no one listens', async () => {
    await assert.rejects(nodeLogEndpoints.connect({ where: `unix:${path.join(dir, 'none.sock')}`, token: 't' }));
  });
});
