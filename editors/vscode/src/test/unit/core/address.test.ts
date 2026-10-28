// TWK_SHELL's value, as twk_core's LocalAddress.toVariable writes it and
// fromVariable reads it: the same strings as its test
// (packages/twk_core/test/terminal/socket_wire_test.dart).
import * as assert from 'node:assert/strict';

import { fromVariable, shellVariable, toVariable } from '../../../core/address';

describe('the address of a shell in TWK_SHELL', () => {
  it('the address, then the token after the last #', () => {
    assert.equal(shellVariable, 'TWK_SHELL');
    const unix = { where: 'unix:/run/a#b/x.sock', token: 'abc' };
    assert.equal(toVariable(unix), 'unix:/run/a#b/x.sock#abc');
    assert.deepEqual(fromVariable(toVariable(unix)), unix);
    const tcp = { where: 'tcp:127.0.0.1:4567', token: 'xyz' };
    assert.equal(toVariable(tcp), 'tcp:127.0.0.1:4567#xyz');
    assert.deepEqual(fromVariable(toVariable(tcp)), tcp);
  });

  it('nothing for what twk_core takes for none', () => {
    for (const nothing of [
      '',
      'unix:/run/x.sock',
      'unix:/run/x.sock#',
      '#abc',
      'unix:#abc',
      'tcp:127.0.0.1#abc',
      'tcp:nohost:1#abc',
      'unix:/run/x\n.sock#abc',
      'unix:/run/x.sock#ab\rc',
      '/run/x.sock#abc',
    ]) {
      assert.equal(fromVariable(nothing), undefined, JSON.stringify(nothing));
    }
  });
});
