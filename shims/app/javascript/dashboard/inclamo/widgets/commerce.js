import { computed, reactive, ref, watch, onUnmounted } from 'vue';
import InclamoAPI from '../api';
import { notePanel, invalidateKnownOrder } from '../orderState';

const entries = new Map();
const currentContexts = new Map();
const epoch = ref(0);
const FRESHNESS_MS = 60000;
export function commerceEntry(account, conversationId, contactId) {
  const contextEpoch = epoch.value;
  const key = `${account}:${conversationId}:${contactId ?? ''}`;
  const conversationKey = `${account}:${conversationId}`;
  if (currentContexts.get(conversationKey) !== key) {
    currentContexts.set(conversationKey, key);
    invalidateKnownOrder(conversationId, account);
  }
  if (!entries.has(key)) entries.set(key, reactive({
    key, account, conversationId, contactId, contextEpoch, panel: null, loading: false, failed: false, updatedAt: 0, generation: 0, pending: null,
  }));
  // Bound memory; currently displayed entries stay referenced by their owners.
  if (entries.size > 100) entries.delete(entries.keys().next().value);
  return entries.get(key);
}
export function acceptPanel(entry, data) {
  entry.panel = data;
  entry.updatedAt = Date.now();
  entry.failed = false;
  if (entry.contextEpoch === epoch.value && currentContexts.get(`${entry.account}:${entry.conversationId}`) === entry.key) {
    notePanel(entry.conversationId, data, entry.account);
  }
}
export async function readCommerce(entry, force = false) {
  if (entry.pending) return entry.pending;
  if (!force && entry.panel && Date.now() - entry.updatedAt < FRESHNESS_MS) return entry.panel;
  const generation = ++entry.generation;
  // A refresh reads as many orders as are shown and replaces them at once: an
  // order further down the list, and a dialog its card opened, stay in place.
  const shown = entry.panel?.orders?.length || 0;
  entry.loading = entry.panel === null;
  entry.failed = false;
  // Capture the account URL before awaiting. An account switch cannot retarget it.
  const { account, conversationId } = entry;
  const read = async () => {
    const { data } = await InclamoAPI.getPanel(conversationId, undefined, account);
    let list = data.orders || [];
    let page = data.page;
    while (list.length < shown && page?.has_more && generation === entry.generation) {
      // eslint-disable-next-line no-await-in-loop
      const next = (await InclamoAPI.getPanel(conversationId, page.cursor, account)).data;
      list = [...list, ...(next.orders || [])];
      page = next.page;
    }
    return list === data.orders ? data : { ...data, orders: list, page };
  };
  entry.pending = read().then(data => {
    if (generation === entry.generation) acceptPanel(entry, data);
    return data;
  }).catch(() => { if (generation === entry.generation) entry.failed = true; }).finally(() => {
    if (generation === entry.generation) { entry.loading = false; entry.pending = null; }
  });
  return entry.pending;
}
export function useCommerce(context) {
  const entry = computed(() => {
    const value = context();
    return commerceEntry(InclamoAPI.url || '', value.conversationId, value.contactId);
  });
  watch(entry, current => { if (current.conversationId) readCommerce(current); }, { immediate: true });
  const timer = setInterval(() => {
    if (!document.hidden && entry.value.conversationId) readCommerce(entry.value);
  }, FRESHNESS_MS);
  onUnmounted(() => clearInterval(timer));
  return { entry, panel: computed(() => entry.value.panel), load: () => readCommerce(entry.value, true) };
}
export function clearCommerce() { entries.clear(); currentContexts.clear(); epoch.value += 1; }
