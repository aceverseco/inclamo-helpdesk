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
// The header has room for a summary only: the queues open below it.
const opened = ref(false);
const root = ref(null);
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
      // A queue counted only in part: overdue and soon are at least this many.
      text: shown(queue[level]) + (level !== 'other' && queue.capped ? '+' : ''),
      words: queue[level] === null ? '' : t(`SLA_OVERVIEW.${level.toUpperCase()}`, { count: queue[level] }),
    })),
  }))
);
const administrator = computed(() => role.value === 'administrator');
const totals = computed(() => overview.value?.totals || { overdue: 0, soon: 0 });
const summary = computed(() => t('SLA_OVERVIEW.SUMMARY', { overdue: totals.value.overdue, soon: totals.value.soon }));
// The header's widget dock scrolls and so clips what hangs out of it: the
// list is placed against the window, under the middle of the summary.
const place = ref({});
const toggle = () => {
  opened.value = !opened.value;
  const box = root.value?.getBoundingClientRect?.();
  if (opened.value && box) place.value = { top: `${box.bottom + 6}px`, left: `${box.left + box.width / 2}px` };
  // Opening shows numbers as fresh as the server gives them.
  if (opened.value) load();
};
const close = () => {
  opened.value = false;
};
const onOutside = event => {
  if (opened.value && root.value && !root.value.contains(event.target)) close();
};
const settings = computed(() => ({ name: SLA_POLICIES_ROUTE, params: { accountId: accountId.value } }));

onMounted(() => {
  load();
  refresher = setInterval(refresh, REFRESH_MS);
  document.addEventListener('visibilitychange', onVisible);
  document.addEventListener('click', onOutside);
});
onBeforeUnmount(() => {
  clearInterval(refresher);
  document.removeEventListener('visibilitychange', onVisible);
  document.removeEventListener('click', onOutside);
});
</script>

<template>
  <div ref="root" class="inclamo-sla-overview" data-testid="inclamo-sla-overview" @keydown.esc="close">
    <button
      type="button"
      class="summary"
      :aria-expanded="opened"
      aria-controls="inclamo-sla-overview-queues"
      :aria-label="loading || failed || !overview?.policies ? t('SLA_OVERVIEW.TITLE') : summary"
      :title="t('SLA_OVERVIEW.TITLE')"
      data-testid="inclamo-sla-overview-toggle"
      @click="toggle"
    >
      <span class="i-lucide-timer size-4" aria-hidden="true" />
      <span class="name">{{ t('SLA_OVERVIEW.SHORT') }}</span>
      <template v-if="!loading && !failed && overview?.policies">
        <span class="count overdue" :class="{ zero: !totals.overdue }" :title="t('SLA_OVERVIEW.OVERDUE', { count: totals.overdue })" data-total="overdue" aria-hidden="true">{{
          totals.overdue
        }}</span>
        <span class="count soon" :class="{ zero: !totals.soon }" :title="t('SLA_OVERVIEW.SOON', { count: totals.soon })" data-total="soon" aria-hidden="true">{{
          totals.soon
        }}</span>
      </template>
    </button>
    <div v-if="opened" id="inclamo-sla-overview-queues" class="queues" :style="place" role="group" :aria-label="t('SLA_OVERVIEW.TITLE')" data-testid="inclamo-sla-overview-queues">
      <span v-if="loading" class="note" data-testid="inclamo-sla-overview-loading">{{ t('SLA_OVERVIEW.LOADING') }}</span>
      <span v-else-if="failed" class="note" data-testid="inclamo-sla-overview-failed">
        {{ t('SLA_OVERVIEW.FAILED') }}
        <button type="button" class="link" @click="load">{{ t('SLA_OVERVIEW.RETRY') }}</button>
      </span>
      <span v-else-if="!overview.policies" class="note" data-testid="inclamo-sla-overview-no-policies">
        {{ t('SLA_OVERVIEW.NO_POLICIES') }}
        <RouterLink v-if="administrator" class="link" :to="settings" data-testid="inclamo-sla-overview-set-up" @click="close">{{ t('SLA_OVERVIEW.SET_UP') }}</RouterLink>
      </span>
      <template v-else>
        <div class="legend" aria-hidden="true">
          <span />
          <span>{{ t('SLA_OVERVIEW.COLUMNS.OVERDUE') }}</span>
          <span>{{ t('SLA_OVERVIEW.COLUMNS.SOON') }}</span>
          <span>{{ t('SLA_OVERVIEW.COLUMNS.OTHER') }}</span>
        </div>
        <RouterLink
          v-for="queue in queues"
          :key="queue.id"
          :to="queue.to"
          class="queue"
          :aria-label="queue.label"
          :data-queue="queue.key || queue.id"
          data-testid="inclamo-sla-overview-queue"
          @click="close"
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
  </div>
</template>

<style scoped>
.inclamo-sla-overview { position:relative; font-size:12px; line-height:16px; white-space:nowrap; }
.summary { display:inline-flex; align-items:center; gap:5px; height:36px; padding:0 10px; border-radius:10px; border:1px solid rgb(var(--slate-6)); color:rgb(var(--slate-12)); background:rgb(var(--slate-1, 255 255 255)); }
.summary:hover, .summary[aria-expanded='true'] { background:rgb(var(--slate-3)); }
.summary:focus-visible, .queue:focus-visible { outline:2px solid currentColor; outline-offset:2px; }
.queues { position:fixed; transform:translateX(-50%); z-index:60; display:flex; flex-direction:column; gap:2px; min-width:280px; padding:8px; border-radius:12px; border:1px solid rgb(var(--slate-6)); background:rgb(var(--slate-1, 255 255 255)); box-shadow:0 10px 30px rgba(0,0,0,.12); }
.legend, .queue { display:grid; grid-template-columns:minmax(0,1fr) 52px 52px 52px; align-items:center; gap:6px; padding:5px 8px; }
.legend { color:rgb(var(--slate-11)); font-size:11px; text-align:center; }
.queue { border-radius:8px; color:rgb(var(--slate-12)); }
.queue:hover { background:rgb(var(--slate-3)); }
.note { padding:6px 8px; color:rgb(var(--slate-11)); white-space:normal; max-width:320px; }
.link { color:rgb(var(--blue-11, 8 109 224)); text-decoration:underline; margin-inline-start:4px; }
.name { overflow:hidden; text-overflow:ellipsis; }
.count { min-width:22px; padding:0 5px; border-radius:6px; text-align:center; font-variant-numeric:tabular-nums; justify-self:center; }
.count.overdue { background:rgb(var(--ruby-3)); color:rgb(var(--ruby-11)); font-weight:600; }
.count.soon { background:rgb(var(--amber-3)); color:rgb(var(--amber-11)); }
.count.other { background:rgb(var(--slate-3)); color:rgb(var(--slate-11)); }
/* Zero is shown, subdued: the table keeps its shape. */
.count.zero { background:transparent; color:rgb(var(--slate-9)); font-weight:400; }
</style>
