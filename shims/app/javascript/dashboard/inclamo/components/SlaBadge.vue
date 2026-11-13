<script setup>
// The SLA badge of a conversation, on its row in a list and in its header
// (capability sla-badge): the one target that needs attention, as words and
// a look (calm, soon, overdue). Nothing when there is nothing to watch.
//
// The timers are read in batches by the shared store; the badge counts down
// from the last read and asks again when the answer can have changed: after a
// minute, when business hours open or close, and when the row's conversation
// changes (a reply, a resolution).
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { t } from '../i18n';
import { duration } from '../sla';
import { timerOf, wantTimer } from '../slaTimers';
import { badgeOf, nextReadIn } from '../slaBadge';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // The conversation's status and last activity, as the list has them: a
  // change of either means the timer may have changed.
  status: { type: String, default: '' },
  activity: { type: [Number, String], default: null },
  // The header's badge: pointing at it, or focusing it, lists every target.
  detailed: { type: Boolean, default: false },
});

const now = ref(Date.now());
const shownDetails = ref(false);
let ticker = null;
let refresher = null;
let follower = null;
// A reply or a resolution reaches the timer in the background, a moment after
// the list hears of it: the timer is read at once and once more shortly after.
const FOLLOW_UP_MS = 5_000;

const known = computed(() => timerOf(props.conversationId));
const badge = computed(() => badgeOf(known.value, { now: now.value, resolved: props.status === 'resolved' }));

// Whole minutes once a minute or more is left, so a row does not flicker
// with seconds; seconds only within the last minute.
const brief = seconds => duration(seconds >= 60 ? Math.floor(seconds / 60) * 60 : seconds);

const key = computed(() => {
  if (!badge.value) return null;
  if (badge.value.look === 'overdue') return 'OVERDUE';
  return badge.value.paused ? 'PAUSED' : 'LEFT';
});
const words = computed(() => ({ target: t(`SLA.BADGE.TARGETS.${badge.value.target}`), time: brief(badge.value.seconds) }));
const text = computed(() => t(`SLA.BADGE.${key.value}`, words.value));
const label = computed(() => t(`SLA.BADGE.LABEL_${key.value}`, words.value));

const moment = value => (value ? new Date(value).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' }) : '');
// Every target of the timer, for the header's details.
const details = computed(() => {
  const timer = known.value?.timer;
  if (!timer) return [];
  const passed = Math.max(0, Math.floor((now.value - (known.value.readAt || now.value)) / 1000));
  return ['first_response', 'resolution']
    .filter(name => timer[name])
    .map(name => {
      const target = timer[name];
      const moved = target.counting ? passed : 0;
      let state;
      if (target.state === 'met') state = t('SLA.MET', { time: duration(target.took_seconds) });
      else if (target.state === 'stopped') state = t('SLA.STOPPED');
      else if (target.state === 'paused') state = t('SLA.PAUSED', { time: duration(target.remaining_seconds) });
      else if (target.state === 'missed') state = t('SLA.MISSED', { time: duration((target.over_seconds || 0) + (target.took_seconds == null ? moved : 0)) });
      else if (target.remaining_seconds - moved <= 0) state = t('SLA.MISSED', { time: duration(moved - target.remaining_seconds) });
      else state = t('SLA.LEFT', { time: duration(target.remaining_seconds - moved) });
      return { name, label: t(`SLA.TARGETS.${name}`), state, due: target.deadline_at ? t('SLA.BADGE.DUE', { when: moment(target.deadline_at) }) : '' };
    });
});

const stopClocks = () => {
  clearInterval(ticker);
  clearTimeout(refresher);
  ticker = null;
  refresher = null;
};

// Ticks while a badge is shown, and asks for the timer again when it is due.
const schedule = () => {
  stopClocks();
  const wait = nextReadIn(known.value);
  if (wait === null) return;
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 1000);
  refresher = setTimeout(() => wantTimer(props.conversationId), wait);
};

watch(known, schedule);
watch(
  () => [props.conversationId, props.status, props.activity],
  () => {
    wantTimer(props.conversationId);
    clearTimeout(follower);
    follower = setTimeout(() => wantTimer(props.conversationId), FOLLOW_UP_MS);
  }
);
onMounted(() => {
  if (known.value) schedule();
  wantTimer(props.conversationId);
});
onBeforeUnmount(() => {
  stopClocks();
  clearTimeout(follower);
});
</script>

<template>
  <span
    v-if="badge"
    class="inclamo-sla-badge relative inline-flex items-center gap-1 rounded whitespace-nowrap shrink-0"
    :class="{
      // A row's bottom line is 15px high and clips what does not fit.
      'px-1.5 py-0.5 text-xs leading-4': detailed,
      'px-1 text-[10px] leading-[13px]': !detailed,
      'bg-n-alpha-2 text-n-slate-11': badge.look === 'calm',
      'bg-n-amber-3 text-n-amber-11': badge.look === 'soon',
      'bg-n-ruby-3 text-n-ruby-11 font-medium': badge.look === 'overdue',
    }"
    :data-look="badge.look"
    :data-target="badge.target"
    :data-paused="badge.paused"
    :aria-label="label"
    :title="detailed ? undefined : label"
    :tabindex="detailed ? 0 : undefined"
    data-testid="inclamo-sla-badge"
    @mouseenter="shownDetails = true"
    @mouseleave="shownDetails = false"
    @focus="shownDetails = true"
    @blur="shownDetails = false"
    @keydown.esc="shownDetails = false"
  >
    <span :class="badge.paused ? 'i-lucide-pause' : badge.look === 'overdue' ? 'i-lucide-alarm-clock' : 'i-lucide-timer'" class="size-3" aria-hidden="true" />
    <span>{{ text }}</span>
    <span
      v-if="detailed && shownDetails"
      role="tooltip"
      class="absolute top-full ltr:right-0 rtl:left-0 z-50 mt-1 flex flex-col gap-1 p-2 rounded-lg border border-n-weak bg-n-solid-1 shadow-lg text-xs font-normal text-n-slate-12 whitespace-nowrap"
      data-testid="inclamo-sla-badge-details"
    >
      <span class="text-n-slate-11">{{ t('SLA.BADGE.DETAILS', { policy: known.timer.policy_name }) }}</span>
      <span v-for="row in details" :key="row.name" :data-testid="`inclamo-sla-badge-${row.name}`">
        {{ row.label }}: {{ row.state }}<template v-if="row.due"> · {{ row.due }}</template>
      </span>
    </span>
  </span>
</template>
