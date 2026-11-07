// The SLA timers of conversations, shared by the sidebar's question whether
// to show the "SLA" section and by the section itself. A conversation is read
// when it is first asked about, and again when the answer is a minute old.
//
// A new conversation gets its timer in the background, a moment after it is
// created: while the server says one is on its way (`pending`), the store
// reads it again by itself, a few times, so the section appears without the
// sidebar having to ask.
import { reactive } from 'vue';
import InclamoAPI from './api';

const STALE_MS = 60_000;
const PENDING_WAITS_MS = [2_000, 4_000, 8_000, 15_000, 30_000, 60_000];

// conversation id -> { timer (null when none), readAt }
const read = reactive({});
const reading = new Map();
// conversation id -> the next read of a pending timer; how many were made
const retries = new Map();
const retried = new Map();

const stopRetrying = id => {
  clearTimeout(retries.get(id));
  retries.delete(id);
};

export const readTimer = id => {
  if (!reading.has(id)) {
    const request = InclamoAPI.getConversationSla(id)
      .then(({ data }) => {
        read[id] = { timer: data.timer, readAt: Date.now() };
        // eslint-disable-next-line no-use-before-define
        retryWhilePending(id, !data.timer && Boolean(data.pending));
        return read[id];
      })
      .finally(() => reading.delete(id));
    reading.set(id, request);
  }
  return reading.get(id);
};

const retryWhilePending = (id, pending) => {
  stopRetrying(id);
  if (!pending) {
    retried.delete(id);
    return;
  }
  const count = retried.get(id) || 0;
  if (count >= PENDING_WAITS_MS.length) return;
  retried.set(id, count + 1);
  retries.set(
    id,
    setTimeout(() => {
      retries.delete(id);
      readTimer(id).catch(() => {});
    }, PENDING_WAITS_MS[count])
  );
};

export const timerOf = id => read[id];

// For the sidebar seam: is there a timer to show? Asking starts a read of an
// unknown or old answer; the section appears when the read says so.
export const hasTimer = id => {
  const known = read[id];
  if ((!known || Date.now() - known.readAt > STALE_MS) && !reading.has(id)) {
    Promise.resolve().then(() => readTimer(id).catch(() => {}));
  }
  return Boolean(known?.timer);
};

// For the specs.
export const forgetTimers = () => {
  Object.keys(read).forEach(id => delete read[id]);
  reading.clear();
  [...retries.keys()].forEach(stopRetrying);
  retried.clear();
};
