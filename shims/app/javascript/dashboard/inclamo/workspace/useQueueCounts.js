import { ref, watch } from 'vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { useStore } from 'dashboard/composables/store';
import { getMetaDebounceKey } from 'dashboard/store/modules/conversationStats';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { loadTeamQueues, resetTeamQueues } from '../teamQueues';

// Navigation describes the account's open work, independently of list filters.
export function useQueueCounts(accountId) {
  const counts = ref(null);
  const store = useStore();

  watch(
    accountId,
    (id, previous, onCleanup) => {
      counts.value = null;
      // Only another account's queues are forgotten: on a first load the
      // route guard may have read this account's queues already.
      if (previous !== undefined && previous !== id) resetTeamQueues();
      if (!id) return;

      let active = true;
      let inFlight = false;
      let refreshAgain = false;
      let timer;
      let refresh;

      function scheduleRefresh() {
        if (!active || timer) return;
        const delays = { default: 1000, long: 7500, superLong: 15000 };
        const key = getMetaDebounceKey(counts.value?.allCount || 0);
        timer = setTimeout(() => {
          timer = undefined;
          refresh();
        }, delays[key]);
      }

      refresh = async () => {
        if (!active) return;
        if (inFlight) {
          refreshAgain = true;
          return;
        }
        inFlight = true;
        // Team queues ride the same triggers; they keep their own last answer.
        loadTeamQueues();
        try {
          const { data } = await ConversationApi.meta({ status: 'open' });
          if (active) {
            counts.value = {
              allCount: data.meta.all_count,
              mineCount: data.meta.mine_count,
              unAssignedCount: data.meta.unassigned_count,
            };
          }
        } catch {
          // Preserve the last successful counts; unknown is not zero.
        } finally {
          inFlight = false;
          if (refreshAgain && active) {
            refreshAgain = false;
            scheduleRefresh();
          }
        }
      };

      const unsubscribe = store.subscribeAction({
        after: ({ type }) => {
          if (type === 'deleteConversation') scheduleRefresh();
        },
      });
      emitter.on('fetch_conversation_stats', scheduleRefresh);
      emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, scheduleRefresh);
      window.addEventListener('focus', scheduleRefresh);
      onCleanup(() => {
        active = false;
        clearTimeout(timer);
        unsubscribe();
        emitter.off('fetch_conversation_stats', scheduleRefresh);
        emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, scheduleRefresh);
        window.removeEventListener('focus', scheduleRefresh);
      });
      refresh();
    },
    { immediate: true }
  );

  return counts;
}
