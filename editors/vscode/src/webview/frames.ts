// The frames panel's webview: the last frames the app drew as bars, the
// tallest as high as the panel, each a button that tells the extension
// which frame was clicked (the sequence log shows it); the median, the
// count and the slowest beside; time or bytes by a switch; cleared.
// Compiled with the terminal's webview (tsconfig.webview.json).
import { FramesState, FromFrames, isToFrames } from './frames_protocol.js';
import { formatValue } from '../core/frames.js';

declare function acquireVsCodeApi(): { postMessage(message: FromFrames): void };

const vscode = acquireVsCodeApi();
const bar = document.getElementById('bar')!;
const chart = document.getElementById('chart')!;

function element<K extends keyof HTMLElementTagNameMap>(tag: K, props: Partial<HTMLElementTagNameMap[K]> = {}, ...children: (Node | string)[]): HTMLElementTagNameMap[K] {
  const e = Object.assign(document.createElement(tag), props);
  e.append(...children);
  return e;
}

const choice = (label: string, value: 'time' | 'bytes') => {
  const radio = element('input', { type: 'radio', name: 'metric', value });
  radio.addEventListener('change', () => vscode.postMessage({ type: 'metric', metric: value }));
  return { radio, label: element('label', {}, radio, label) };
};
const time = choice('time', 'time');
const bytes = choice('bytes', 'bytes');
const clear = element('button', { textContent: 'Clear', title: 'Forget the frames kept' });
clear.addEventListener('click', () => vscode.postMessage({ type: 'clear' }));
const summary = element('span', { id: 'summary' });
bar.append(time.label, bytes.label, clear, summary);

function show(s: FramesState): void {
  time.radio.checked = s.metric === 'time';
  bytes.radio.checked = s.metric === 'bytes';
  const parts: string[] = [];
  if (s.bars.length > 0) {
    parts.push(`${s.summary.count} frames`);
    if (s.summary.total > s.summary.count) {
      parts.push(`of ${s.summary.total}`);
    }
    if (s.summary.median !== undefined) {
      parts.push(`median ${formatValue(s.summary.median, s.metric)}`);
    }
    if (s.summary.slowest) {
      parts.push(`${s.metric === 'time' ? 'slowest' : 'largest'} ${formatValue(s.summary.slowest.value, s.metric)} (frame ${s.summary.slowest.frame})`);
    }
  }
  if (s.note !== '') {
    parts.push(s.note);
  }
  summary.textContent = parts.join(' · ');
  if (s.bars.length === 0) {
    chart.replaceChildren(element('div', { className: 'message', textContent: s.message }));
    return;
  }
  const slowest = s.summary.slowest?.frame;
  chart.replaceChildren(
    ...s.bars.map((b) => {
      const fill = element('span', { className: `fill${b.value === null ? ' unknown' : ''}${b.frame === slowest ? ' slowest' : ''}` });
      fill.style.height = `${Math.max(b.value === null ? 2 : 4, Math.round(b.height * 100))}%`;
      const button = element('button', { className: 'bar', title: b.title }, fill);
      button.dataset.frame = String(b.frame);
      button.addEventListener('click', () => vscode.postMessage({ type: 'pick', frame: b.frame }));
      return button;
    }),
  );
}

window.addEventListener('message', (event: MessageEvent<unknown>) => {
  if (isToFrames(event.data)) {
    show(event.data.state);
  }
});

vscode.postMessage({ type: 'ready' });
