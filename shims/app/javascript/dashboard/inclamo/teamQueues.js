// Team queues: the account's shared conversation queues (capability
// team-queues). The server holds one definition per account; a queue opens on
// Chatwoot's own folder route under an id no native folder can have, and the
// three seams of the conversation list ask this module about such an id.
import { computed, reactive } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import InclamoAPI from './api';
import { t } from './i18n';

const PREFIX = 'q-';
// queues: null until the first answer. Unknown is not "none".
const state = reactive({ queues: null });
let inFlight = null;
// One object per open queue for as long as its name and conditions stay the
// same: the conversation list reloads whenever its folder object changes.
const resolved = new Map();

export const isTeamQueueId = id => typeof id === 'string' && id.startsWith(PREFIX);
export const teamQueueRouteId = queue => `${PREFIX}${queue.id}`;

// The queues every staff member sees in the navigation, in the account's order.
export const teamQueues = computed(() => state.queues || []);
export const teamQueuesKnown = computed(() => state.queues !== null);

// Reads the visible queues with their counts. A failed refresh keeps what the
// last successful one showed.
export function loadTeamQueues() {
  if (inFlight) return inFlight;
  inFlight = Promise.resolve()
    .then(() => InclamoAPI.getTeamQueues())
    .then(({ data }) => {
      state.queues = data.queues.filter(queue => !queue.hidden);
    })
    .catch(() => {})
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

// The folder the conversation list shows for a team-queue id, or nothing.
export function resolveTeamQueue(routeId) {
  if (!isTeamQueueId(routeId)) return undefined;
  const queue = teamQueues.value.find(one => teamQueueRouteId(one) === routeId);
  if (!queue) {
    resolved.delete(routeId);
    return undefined;
  }
  const signature = JSON.stringify([queue.name, queue.query]);
  const kept = resolved.get(routeId);
  if (kept?.signature === signature) return kept.folder;
  const folder = { id: routeId, name: queue.name, query: queue.query, teamQueue: true };
  resolved.set(routeId, { signature, folder });
  return folder;
}

export const notifyTeamQueueUnavailable = () =>
  emitter.emit('newToastMessage', { message: t('TEAM_QUEUES.NOT_AVAILABLE'), action: null });

// For the folder route guard: a hidden or unknown queue is refused, and the
// native redirect to the main list follows.
export async function teamQueueAvailable(routeId) {
  if (!teamQueuesKnown.value) await loadTeamQueues();
  if (resolveTeamQueue(routeId)) return true;
  notifyTeamQueueUnavailable();
  return false;
}

// Another account's queues must not outlive the switch.
export function resetTeamQueues() {
  state.queues = null;
  resolved.clear();
}
