// The text of a webview's HTML (core/html.ts).
import * as assert from 'node:assert/strict';

import { escapeHtml } from '../../../core/html';

describe('escapeHtml', () => {
  it('& < > and both quotes, so it is safe in text and in an attribute', () => {
    assert.equal(escapeHtml(`<a href="x" onclick='y'>&</a>`), '&#60;a href=&#34;x&#34; onclick=&#39;y&#39;&#62;&#38;&#60;/a&#62;');
    assert.equal(escapeHtml('plain'), 'plain');
  });
});
