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
    return this.split(this.carry, true);
  }

  private split(data: Buffer, flush: boolean): string {
    this.carry = Buffer.alloc(0);
    const tokens = new SequenceReader(true).read(data);
    // the pieces cut and put together again are the bytes read; where they are not (a control inside a CSI is put before it), all are keys
    if (tokens.map((t) => t.raw).join('') !== data.toString('latin1')) {
      this.positionAsked = 0;
      return data.toString('utf8');
    }
    const last = tokens.at(-1);
    if (!flush && last && unfinished(last)) {
      const rest = latin1Bytes(last.raw);
      if (rest.length <= maxPending) {
        this.carry = rest;
        tokens.pop();
      }
    }
    let keys = Buffer.alloc(0);
    let keyed = false;
    for (const t of tokens) {
      if (!this.isAnswer(t)) {
        keyed = true;
        keys = Buffer.concat([keys, latin1Bytes(t.raw)]);
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
      this.inPaste = !(t.kind === 'csi' && t.final === '~' && t.params === '201' && t.prefix === '' && !t.alt);
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
