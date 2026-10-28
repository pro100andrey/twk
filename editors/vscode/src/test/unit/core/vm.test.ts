// What the VM service client takes from the service's messages, and its
// connect bounded on a fake clock.
import * as assert from 'node:assert/strict';
import * as net from 'node:net';

import { VmClient, parseMessage } from '../../../core/vm';
import { FakeClock, until } from '../fakes';

describe('parseMessage', () => {
  it("a stream's event, with the fields hot reload reads", () => {
    const m = parseMessage(
      JSON.stringify({
        jsonrpc: '2.0',
        method: 'streamNotify',
        params: { streamId: 'Isolate', event: { kind: 'ServiceExtensionAdded', isolate: { id: 'i/1' }, extensionRPC: 'ext.twk.reassemble', other: 1 } },
      }),
    );
    assert.deepEqual(m, { kind: 'event', stream: 'Isolate', event: { kind: 'ServiceExtensionAdded', isolate: { id: 'i/1' }, extensionRPC: 'ext.twk.reassemble' } });
  });

  it('an answer: its result, or its error', () => {
    assert.deepEqual(parseMessage('{"id":"3","result":{"type":"Success"}}'), { kind: 'result', id: '3', result: { type: 'Success' } });
    assert.deepEqual(parseMessage('{"id":"4","error":{"code":-32601,"message":"Method not found","data":{"x":1}}}'), {
      kind: 'error',
      id: '4',
      code: -32601,
      message: 'Method not found',
      data: { x: 1 },
    });
  });

  it('nothing for what is neither', () => {
    for (const text of ['', 'nope', '[]', '7', '{"result":{}}', '{"method":"streamNotify","params":{"streamId":1}}']) {
      assert.equal(parseMessage(text), undefined, text);
    }
  });
});

describe('VmClient.connect', () => {
  const sockets: net.Socket[] = [];
  let server: net.Server;

  beforeEach(async () => {
    sockets.length = 0;
    server = net.createServer((s) => sockets.push(s));
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  });

  // here, not in the test: a test that fails waiting leaves nothing open
  afterEach(async () => {
    sockets.forEach((s) => s.destroy());
    await new Promise((r) => server.close(r));
  });

  it('to a service that neither answers nor fails: fails once its patience is out', async () => {
    const address = server.address();
    assert.ok(typeof address === 'object' && address !== null);
    const clock = new FakeClock();
    const connecting = VmClient.connect(`http://127.0.0.1:${address.port}/x=/`, clock, 1000);
    let failed: unknown;
    connecting.catch((e: unknown) => (failed = e));
    await until('the connection', () => sockets.length === 1);
    clock.elapse(999);
    await new Promise((r) => setImmediate(r));
    assert.equal(failed, undefined, 'waiting still');
    clock.elapse(1);
    await assert.rejects(connecting, /no answer from the VM service at http:\/\/127\.0\.0\.1:\d+\/x=\/ in 1000 ms/);
  });
});
