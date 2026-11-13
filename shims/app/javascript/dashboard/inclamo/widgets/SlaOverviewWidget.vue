<script setup>
// The "SLA overview" widget of the workspace header (capability
// sla-urgency-widget): per visible team queue, how many of its open
// conversations are overdue against their SLA, due soon, or neither. The
// numbers are the server's, for this staff member, by the rule of the SLA
// badge; a queue's entry opens the queue.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { FOLDER_ROUTE, SLA_POLICIES_ROUTE } from '../routes';
import { teamQueueRouteId } from '../teamQueues';

// As often as the list's badges: a passed deadline shows within about a minute.
const REFRESH_MS = 60_000;
const LEVELS = ['overdue', 'soon', 'other'];

const accountId = useMapGetter('getCurrentAccountId');
const role = useMapGetter('getCurrentRole');
const loading = ref(true);
const failed = ref(false);
const overview = ref(null);
let refresher = null;
let asked = 0;

const load = async () => {
  asked += 1;
  const mine = asked;
  try {
    const { data } = await InclamoAPI.getSlaOverview();
    // An older answer must not replace a newer one.
    if (mine !== asked) return;
    overview.value = data;
    failed.value = false;
  } catch (error) {
    // What was shown stays; a first load that fails says so.
    if (mine === asked) failed.value = overview.value === null;
  } finally {
    if (mine === asked) loading.value = false;
  }
};

// Not while the tab is hidden; at once when it is shown again.
const refresh = () => {
  if (typeof document === 'undefined' || document.visibilityState !== 'hidden') load();
};
const onVisible = () => {
  if (document.visibilityState === 'visible') load();
};

const shown = count => (count === null || count === undefined ? t('SLA_OVERVIEW.UNKNOWN') : String(count));
const queues = computed(() =>
  (overview.value?.queues || []).map(queue => ({
    ...queue,
    to: { name: FOLDER_ROUTE, params: { accountId: accountId.value, id: teamQueueRouteId(queue) } },
    label:
      queue.total === null
        ? t('SLA_OVERVIEW.QUEUE_UNKNOWN', { name: queue.name })
        : t('SLA_OVERVIEW.QUEUE', { name: queue.name, overdue: queue.overdue, soon: queue.soon, other: queue.other }),
    levels: LEVELS.map(level => ({
      level,
      count: queue[level],
      text: shown(queue[level]) + (level === 'other' && queue.capped ? '+' : ''),
      words: queue[level] === null ? '' : t(`SLA_OVERVIEW.${level.toUpperCase()}`, { count: queue[level] }),
    })),
  }))
);
const administrator = computed(() => role.value === 'administrator');
const settings = computed(() => ({ name: SLA_POLICIES_ROUTE, params: { accountId: accountId.value } }));

onMounted(() => {
  load();
  refresher = setInterval(refresh, REFRESH_MS);
  document.addEventListener('visibilitychange', onVisible);
});
onBeforeUnmount(() => {
  clearInterval(refresher);
  document.removeEventListener('visibilitychange', onVisible);
});
</script>

<template>
  <div class="inclamo-sla-overview" role="group" :aria-label="t('SLA_OVERVIEW.TITLE')" data-testid="inclamo-sla-overview">
    <span v-if="loading" class="note" data-testid="inclamo-sla-overview-loading">{{ t('SLA_OVERVIEW.LOADING') }}</span>
    <span v-else-if="failed" class="note" data-testid="inclamo-sla-overview-failed">
      {{ t('SLA_OVERVIEW.FAILED') }}
      <button type="button" class="link" @click="load">{{ t('SLA_OVERVIEW.RETRY') }}</button>
    </span>
    <span v-else-if="!overview.policies" class="note" data-testid="inclamo-sla-overview-no-policies">
      {{ t('SLA_OVERVIEW.NO_POLICIES') }}
      <RouterLink v-if="administrator" class="link" :to="settings" data-testid="inclamo-sla-overview-set-up">{{
        t('SLA_OVERVIEW.SET_UP')
      }}</RouterLink>
    </span>
    <template v-else>
      <RouterLink
        v-for="queue in queues"
        :key="queue.id"
        :to="queue.to"
        class="queue"
        :aria-label="queue.label"
        :data-queue="queue.key || queue.id"
        data-testid="inclamo-sla-overview-queue"
      >
        <span class="name">{{ queue.name }}</span>
        <span
          v-for="one in queue.levels"
          :key="one.level"
          class="count"
          :class="[one.level, { zero: !one.count }]"
          :title="one.words"
          :data-level="one.level"
          :data-count="one.count ?? ''"
          aria-hidden="true"
          >{{ one.text }}</span
        >
      </RouterLink>
    </template>
  </div>
</template>

<style scoped>
.inclamo-sla-overview { display:flex; align-items:center; gap:6px; min-width:0; font-size:12px; line-height:16px; white-space:nowrap; }
.note { color:rgb(var(--slate-11)); }
.link { color:rgb(var(--blue-11, 0 102 204)); text-decoration:underline; margin-inline-start:4px; }
.queue { display:inline-flex; align-items:center; gap:4px; padding:3px 8px; border-radius:8px; border:1px solid rgb(var(--slate-6)); color:rgb(var(--slate-12)); }
.queue:hover { background:rgb(var(--slate-3)); }
.queue:focus-visible { outline:2px solid currentColor; outline-offset:2px; }
.name { max-width:120px; overflow:hidden; text-overflow:ellipsis; }
.count { min-width:18px; padding:0 4px; border-radius:6px; text-align:center; font-variant-numeric:tabular-nums; }
.count.overdue { background:rgb(var(--ruby-3)); color:rgb(var(--ruby-11)); font-weight:600; }
.count.soon { background:rgb(var(--amber-3)); color:rgb(var(--amber-11)); }
.count.other { background:rgb(var(--slate-3)); color:rgb(var(--slate-11)); }
/* Zero is shown, subdued: the strip keeps its shape. */
.count.zero { background:transparent; color:rgb(var(--slate-9)); font-weight:400; }
</style>
