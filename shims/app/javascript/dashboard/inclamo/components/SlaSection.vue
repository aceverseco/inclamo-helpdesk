<script setup>
// The "SLA" section of the conversation sidebar: the policy applied to the
// conversation and, per target, the time left, the time it took or by how
// much it was missed. Counts down locally between reads of the timer.
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { t } from '../i18n';
import { duration } from '../sla';
import { readTimer, timerOf } from '../slaTimers';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: [Number, String], default: undefined },
});

// Read again at most this often, and when a target runs out or the business
// hours open or close.
const REFRESH_MS = 60_000;

const loading = ref(true);
const failed = ref(false);
// The last read of this conversation's timer, shared with the sidebar seam.
const known = computed(() => timerOf(props.conversationId));
const timer = computed(() => known.value?.timer || null);
const readAt = computed(() => known.value?.readAt || Date.now());
const now = ref(Date.now());
let ticker = null;
let refresher = null;

const stopClocks = () => {
  clearInterval(ticker);
  clearTimeout(refresher);
};

const sinceRead = computed(() => Math.max(0, Math.floor((now.value - readAt.value) / 1000)));

const schedule = data => {
  stopClocks();
  if (!data || data.stopped) return;
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 1000);
  const waits = [REFRESH_MS];
  if (data.next_change_at) waits.push(new Date(data.next_change_at).getTime() - Date.now() + 1000);
  ['first_response', 'resolution'].forEach(name => {
    const target = data[name];
    if (target?.counting && target.state === 'running') waits.push(target.remaining_seconds * 1000 + 1000);
  });
  // eslint-disable-next-line no-use-before-define
  refresher = setTimeout(load, Math.max(1000, Math.min(...waits)));
};

const load = async () => {
  failed.value = false;
  try {
    const { timer: data } = await readTimer(props.conversationId);
    now.value = Date.now();
    schedule(data);
  } catch (error) {
    failed.value = true;
    stopClocks();
  } finally {
    loading.value = false;
  }
};

const shown = name => {
  const target = timer.value?.[name];
  if (!target) return null;
  const passed = target.counting ? sinceRead.value : 0;
  if (target.state === 'running') {
    const left = target.remaining_seconds - passed;
    if (left <= 0) return { state: 'missed', text: t('SLA.MISSED', { time: duration(-left) }) };
    return { state: 'running', text: t('SLA.LEFT', { time: duration(left) }) };
  }
  if (target.state === 'paused') return { state: 'paused', text: t('SLA.PAUSED', { time: duration(target.remaining_seconds) }) };
  if (target.state === 'met') return { state: 'met', text: t('SLA.MET', { time: duration(target.took_seconds) }) };
  if (target.state === 'missed') return { state: 'missed', text: t('SLA.MISSED', { time: duration(target.over_seconds + passed) }) };
  return { state: 'stopped', text: t('SLA.STOPPED') };
};

const rows = computed(() =>
  ['first_response', 'resolution']
    .map(name => ({ name, label: t(`SLA.TARGETS.${name}`), shown: shown(name) }))
    .filter(row => row.shown)
);

watch(
  () => props.conversationId,
  () => {
    loading.value = true;
    load();
  },
  { immediate: true }
);

onBeforeUnmount(stopClocks);
</script>

<template>
  <div class="px-4 py-3 text-sm text-n-slate-12" data-testid="inclamo-sla-section">
    <p v-if="loading" class="text-n-slate-11">{{ t('SLA.LOADING') }}</p>
    <p v-else-if="failed" class="text-n-ruby-11" data-testid="inclamo-sla-failed">
      {{ t('SLA.FAILED') }}
      <button type="button" class="text-n-blue-text" @click="load">{{ t('SLA.RETRY') }}</button>
    </p>
    <p v-else-if="!timer" class="text-n-slate-11" data-testid="inclamo-sla-none">{{ t('SLA.NONE') }}</p>
    <div v-else class="flex flex-col gap-2" data-testid="inclamo-sla-timer">
      <span class="text-xs text-n-slate-11">
        <span data-testid="inclamo-sla-policy">{{ timer.policy_name }}</span>
        <template v-if="timer.business_hours_only"> · {{ t('SLA.BUSINESS_HOURS') }}</template>
        <template v-if="timer.stopped"> · {{ t('SLA.POLICY_DELETED') }}</template>
      </span>
      <div v-for="row in rows" :key="row.name" class="flex items-center justify-between gap-2" :data-testid="`inclamo-sla-${row.name}`" :data-state="row.shown.state">
        <span>{{ row.label }}</span>
        <span
          :class="{
            'text-n-ruby-11': row.shown.state === 'missed',
            'text-n-teal-11': row.shown.state === 'met',
            'text-n-slate-11': row.shown.state === 'paused' || row.shown.state === 'stopped',
          }"
        >
          {{ row.shown.text }}
        </span>
      </div>
    </div>
  </div>
</template>
