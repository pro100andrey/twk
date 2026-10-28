// What the twk terminal switches on in an app (core/switches.ts): the
// settings' values checked, the variables of the welcome, the pick.
import * as assert from 'node:assert/strict';

import { debugAids, describeSwitches, noSwitches, switchEnvironment, switchItems, switchesOf, switchesPicked } from '../../../core/switches';

describe('switches', () => {
  it("of the settings' values: the reader on for true only, the aids known in their order, each once", () => {
    assert.deepEqual(switchesOf(true, ['frames', 'overlay', 'frames', 'mine', 3]), { screenReader: true, debug: ['overlay', 'frames'] });
    assert.deepEqual(switchesOf('yes', 'overlay'), noSwitches);
    assert.deepEqual(switchesOf(undefined, undefined), noSwitches);
  });

  it('set in the welcome only what they turn on, TWK_DEBUG with keys, as it takes the place of the app’s', () => {
    assert.deepEqual(switchEnvironment(noSwitches), {});
    assert.deepEqual(switchEnvironment({ screenReader: true, debug: [] }), { TWK_SCREEN_READER: '1' });
    assert.deepEqual(switchEnvironment({ screenReader: false, debug: ['overlay', 'logs'] }), { TWK_DEBUG: 'keys,overlay,logs' });
  });

  it('are described for a title, and picked from items that show those on', () => {
    assert.equal(describeSwitches(noSwitches), '');
    assert.equal(describeSwitches({ screenReader: true, debug: ['console'] }), 'screen reader, console');
    const items = switchItems({ screenReader: true, debug: ['timeline'] });
    assert.deepEqual(
      items.map((i) => i.label),
      ['screen reader', ...debugAids.map((a) => a.aid)],
    );
    assert.deepEqual(
      items.filter((i) => i.picked).map((i) => i.label),
      ['screen reader', 'timeline'],
    );
    assert.deepEqual(switchesPicked(['timeline', 'screen reader', 'rainbow']), { screenReader: true, debug: ['timeline', 'rainbow'] });
    assert.deepEqual(switchesPicked([]), noSwitches);
  });
});
