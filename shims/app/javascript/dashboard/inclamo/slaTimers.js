// The SLA timers of conversations, shared by the sidebar's question whether
// to show the "SLA" section and by the section itself. A conversation is read
// when it is first asked about, and again when the answer is a minute old.
import { reactive } from 'vue';
import InclamoAPI from './api';

const STALE_MS = 60_000;

// conversation id -> { timer (null when none), readAt }
const read = reactive({});
const reading = new Map();

export const readTimer = id => {
  if (!reading.has(id)) {
    const request = InclamoAPI.getConversationSla(id)
      .then(({ data }) => {
        read[id] = { timer: data.timer, readAt: Date.now() };
        return read[id];
      })
      .finally(() => reading.delete(id));
    reading.set(id, request);
  }
  return reading.get(id);
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
};
