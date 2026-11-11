import { computed, reactive, watch, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { productLayout } from './registry';

const states = new Map();
export const layoutURL = accountId => `/api/v1/accounts/${accountId}/inclamo/workspace_layout`;

export function stateFor(accountId, userId) {
  const key = `${accountId}:${userId}`;
  if (!states.has(key)) states.set(key, reactive({
    layout: productLayout(), revision: null, source: 'product', unavailable: [],
    error: false, denied: false, busy: false, users: 0, generation: 0,
  }));
  return states.get(key);
}

export async function refreshLayout(accountId, state) {
  if (state.busy || !accountId) return;
  state.busy = true;
  const generation = state.generation;
  try {
    const { data } = await axios.get(layoutURL(accountId));
    if (generation === state.generation) Object.assign(state, data, { error: false, denied: false });
  } catch (error) {
    state.error = true;
    if ([401, 403, 404].includes(error.response?.status)) {
      Object.assign(state, { layout: productLayout(), revision: null, denied: true, unavailable: [] });
    }
  } finally { state.busy = false; }
}

export function useWorkspaceLayout() {
  const route = useRoute();
  const user = useMapGetter('getCurrentUser');
  const accountId = computed(() => route.params.accountId);
  const state = computed(() => stateFor(accountId.value, user.value?.id));
  let release = () => {};
  watch([accountId, () => user.value?.id], ([account, userId]) => {
    release();
    if (!account || !userId) return;
    const current = state.value;
    const refresh = () => { if (!document.hidden) refreshLayout(account, current); };
    current.users += 1;
    if (current.users === 1) {
      refresh();
      current.timer = setInterval(refresh, 15000);
      current.focusHandler = refresh;
      window.addEventListener('focus', refresh);
    }
    release = () => {
      current.users -= 1;
      if (!current.users) {
        clearInterval(current.timer);
        window.removeEventListener('focus', current.focusHandler);
      }
    };
  }, { immediate: true });
  onUnmounted(() => release());
  const save = async (layout, revision, reset = false) => {
    const account = accountId.value;
    const current = state.value;
    current.generation += 1;
    const response = reset
      ? await axios.delete(layoutURL(account), { data: { revision } })
      : await axios.put(layoutURL(account), { layout, revision });
    Object.assign(current, response.data, { error: false });
    return response.data;
  };
  return { state, accountId, save, refresh: () => refreshLayout(accountId.value, state.value) };
}
