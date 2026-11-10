// The keys of a recording, for typing into a live app: the recording's `i`
// events hold both what the person typed and what the terminal answered to
// the app's queries (nothing in an event tells them apart, and one event can
// hold both), so they are told by their shape, as twk_dev's `InputSplitter`
// does for `twk record --replay` (packages/twk_dev/lib/src/replay.dart,
// documented in packages/twk_dev/doc/record-play.md): a sequence a person's
// keys never make is an answer (`CSI ? … c`, `CSI > … c`, `CSI = … c`,
// `CSI … $ y`, `CSI ? … u`, `CSI ? … R`, `CSI … n`, `CSI … t`, a string up to
// its terminator), everything else is a key, a paste's content whatever it
// holds; `CSI row ; column R` is an answer only once the output has the query
// (`CSI 6 n`) and none was answered since. The cutting into sequences is
// core/sequences.ts's [SequenceReader], the sequence log's. Pure: no node
// beyond Buffer, no DOM.
import { Cast } from './cast';
import { SequenceReader, Token } from './sequences';

/** Keys typed at one time of a recording. */
export interface ReplayStep {
  /** Seconds from the recording's start. */
  readonly time: number;
  /** The keys, as the recording has them (answers taken out). */
  readonly keys: string;
  /** Whether the app wrote something after them and before the next keys, in the recording's order of events. */
  readonly reacts: boolean;
}

/** How much of an unfinished sequence is waited for before it is keys. */
const maxPending = 4096;

const latin1Bytes = (raw: string): Buffer => Buffer.from(raw, 'latin1');

const pasteEnd = '\x1b[201~';

/** How many characters at the end of [raw] are the start of the paste's end marker, not all of it. */
function markerPrefix(raw: string): number {
  for (let n = Math.min(pasteEnd.length - 1, raw.length); n > 0; n--) {
    if (raw.endsWith(pasteEnd.slice(0, n))) {
      return n;
    }
  }
  return 0;
}

/** Whether [t], the last token of a read, is the start of a sequence only: the rest may come in the next event. */
function unfinished(t: Token): boolean {
  switch (t.kind) {
    case 'esc':
      // a lone ESC, ESC with intermediates, ESC [ without its final, ESC O alone
      return t.raw === '\x1b' || (t.raw.startsWith('\x1b[') && t.final === '[') || (t.final === '' && t.raw[0] === '\x1b') || (t.final === 'O' && t.raw === '\x1bO');
    case 'osc':
      return !(t.raw.endsWith('\x07') || t.raw.endsWith('\x1b\\'));
    case 'dcs':
    case 'apc':
    case 'pm':
    case 'sos':
      return !t.raw.endsWith('\x1b\\');
    default:
      return false;
  }
}

/**
 * The tokens of [data], as a terminal's parser cuts them: an Escape inside a
 * string that does not start its ST ends the string there (the reader of the
 * sequence log keeps it in, for tmux's passthrough), so the string's opener
 * was a key (an Alt+letter) and what follows is read afresh.
 */
function tokensOf(data: Buffer): Token[] {
  const out: Token[] = [];
  for (const t of new SequenceReader(true).read(data)) {
    const isString = t.kind === 'osc' || t.kind === 'dcs' || t.kind === 'apc' || t.kind === 'pm' || t.kind === 'sos';
    if (!isString || !hasInnerEscape(t.raw)) {
      out.push(t);
      continue;
    }
    out.push({ kind: 'esc', raw: t.raw.slice(0, 2), intermediates: '', final: t.raw[1] });
    out.push(...tokensOf(latin1Bytes(t.raw.slice(2))));
  }
  return out;
}

/** Whether the string [raw] has an Escape that no backslash follows, before its end. */
function hasInnerEscape(raw: string): boolean {
  for (let j = 2; j + 1 < raw.length; j++) {
    if (raw[j] === '\x1b' && raw[j + 1] !== '\\') {
      return true;
    }
  }
  return false;
}

/**
 * Cuts the recording's input into keys and answers, as `InputSplitter`:
 * [sawOutput] is given what the app wrote, in order, [add] what was sent.
 */
class InputSplitter {
  private readonly output = new SequenceReader(false);
  private positionAsked = 0;
  private carry: Buffer = Buffer.alloc(0);
  private inPaste = false;

  /** The app wrote [text]: each cursor-position query in it makes a `CSI row ; column R` an answer, until a key is typed. */
  sawOutput(text: string): void {
    for (const t of this.output.read(Buffer.from(text, 'utf8'))) {
      if (t.kind === 'csi' && t.final === 'n' && t.intermediates === '' && (t.prefix === '' || t.prefix === '?') && t.params === '6') {
        this.positionAsked++;
      }
    }
  }

  /** The keys in [text], after what was kept of the event before; a start of a sequence is kept for the next call. */
  add(text: string): string {
    return this.split(Buffer.concat([this.carry, Buffer.from(text, 'utf8')]), false);
  }

  /** What [add] kept, as keys. */
  flush(): string {
    const keys = this.split(this.carry, true);
    // the recording is over: a paste it left open is not the next one's
    this.inPaste = false;
    return keys;
  }

  private split(data: Buffer, flush: boolean): string {
    this.carry = Buffer.alloc(0);
    const tokens = tokensOf(data);
    const last = tokens.at(-1);
    // The last token may be the start of a sequence the next event finishes; whether it is waited for depends on the paste state
    // when it comes, so it is told apart from the rest and decided on after them.
    const parkable = !flush && last !== undefined && unfinished(last);
    const count = parkable ? tokens.length - 1 : tokens.length;
    const bytes = data.toString('latin1');
    let keys = Buffer.alloc(0);
    let keyed = false;
    let at = 0;
    const key = (raw: string) => {
      keyed = true;
      keys = Buffer.concat([keys, latin1Bytes(raw)]);
    };
    for (let k = 0; k < count; k++) {
      const t = tokens[k];
      if (!bytes.startsWith(t.raw, at)) {
        // A control inside a CSI is put before its token, so these pieces are not the bytes read, in this order:
        // the controls and the CSI are keys as they were typed, the bytes at their place, and it is no sequence of the
        // paste's or the answers' (as in InputSplitter, which reads it as the keys they are). The tokens after it are told as usual.
        let end = k;
        while (tokens[end].kind === 'control' && end + 1 < count) {
          end++;
        }
        let length = 0;
        for (let j = k; j <= end; j++) {
          length += tokens[j].raw.length;
        }
        key(bytes.slice(at, at + length));
        at += length;
        k = end;
        continue;
      }
      at += t.raw.length;
      if (!this.isAnswer(t)) {
        key(t.raw);
      }
    }
    if (parkable && last !== undefined) {
      // inside a paste only the start of its end marker is waited for: the rest is the person's, at its own time
      const keep = this.inPaste ? markerPrefix(last.raw) : last.raw.length <= maxPending ? last.raw.length : 0;
      if (keep > 0) {
        this.carry = latin1Bytes(last.raw.slice(last.raw.length - keep));
      }
      if (keep < last.raw.length) {
        if (this.inPaste) {
          key(last.raw.slice(0, last.raw.length - keep));
        } else if (!this.isAnswer(last)) {
          key(last.raw);
        }
      }
    }
    if (keyed) {
      // the queries before a key are given up
      this.positionAsked = 0;
    }
    return keys.toString('utf8');
  }

  private isAnswer(t: Token): boolean {
    if (this.inPaste) {
      // an Escape before the marker is a key and the marker is still one
      this.inPaste = !(t.kind === 'csi' && t.final === '~' && t.params === '201' && t.prefix === '' && t.intermediates === '');
      return false;
    }
    switch (t.kind) {
      case 'osc':
      case 'dcs':
      case 'apc':
      case 'pm':
      case 'sos':
        // an unterminated one (an Alt+letter that opens a string, flushed) is keys
        return t.kind === 'osc' ? t.raw.endsWith('\x07') || t.raw.endsWith('\x1b\\') : t.raw.endsWith('\x1b\\');
      case 'csi': {
        if (t.alt) {
          return false;
        }
        const { prefix, params, intermediates, final } = t;
        if (final === '~' && params === '200' && prefix === '' && intermediates === '') {
          this.inPaste = true;
          return false;
        }
        switch (final) {
          case 'c':
            return prefix === '?' || prefix === '>' || prefix === '=';
          case 'y':
            return intermediates === '$';
          case 'u':
            return prefix === '?';
          case 'R':
            if (prefix === '?') {
              if (this.positionAsked > 0 && params.includes(';')) {
                this.positionAsked--;
              }
              return true;
            }
            if (prefix === '' && this.positionAsked > 0 && /^\d+;\d+$/.test(params)) {
              this.positionAsked--;
              return true;
            }
            return false;
          case 'n':
          case 't':
            return intermediates === '';
          default:
            return false;
        }
      }
      default:
        return false;
    }
  }
}

/**
 * The keys of [cast], its input events with the terminal's answers taken
 * out, each at its time; the events that were answers only are left out.
 */
export function replaySteps(cast: Cast): ReplayStep[] {
  const splitter = new InputSplitter();
  const steps: ReplayStep[] = [];
  let reacts = false;
  const close = () => {
    if (steps.length > 0 && reacts) {
      steps[steps.length - 1] = { ...steps[steps.length - 1], reacts: true };
    }
    reacts = false;
  };
  for (const e of cast.events) {
    if (e.code === 'o') {
      splitter.sawOutput(e.data);
      // by the order of the events, not their times (rounded: a reaction can carry its key's time)
      if (steps.length > 0) {
        reacts = true;
      }
    } else if (e.code === 'i') {
      const keys = splitter.add(e.data);
      if (keys !== '') {
        close();
        steps.push({ time: e.time, keys, reacts: false });
      }
    }
  }
  const rest = splitter.flush();
  close();
  if (rest !== '') {
    steps.push({ time: cast.events.at(-1)?.time ?? 0, keys: rest, reacts: false });
  }
  return steps;
}
