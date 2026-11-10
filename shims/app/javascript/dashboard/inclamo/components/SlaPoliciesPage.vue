<script setup>
// Settings → SLA: policies with a first-response and a resolution target, the
// inboxes they cover, their order, and a summary for the last 7 or 30 days.
// Administrators only.
import { ref, reactive, computed, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { UNITS, MAX_TARGET_SECONDS, toSeconds, fromSeconds, duration } from '../sla';

const policies = ref([]);
const inboxes = ref([]);
const summary = ref({});
const days = ref(7);
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const actionError = ref(false);
const editing = ref(null); // null, 'new' or a policy id
const deleting = ref(null);
const errors = ref([]);
const form = reactive({});

const unitNames = Object.keys(UNITS);

// Only the answer to the last question is shown: a slower answer for the
// other period must not replace it.
let summaryAsked = 0;
const loadSummary = async () => {
  summaryAsked += 1;
  const asked = summaryAsked;
  try {
    const { data } = await InclamoAPI.getSlaSummary(days.value);
    if (asked === summaryAsked) summary.value = Object.fromEntries(data.policies.map(row => [row.id, row]));
  } catch (error) {
    if (asked === summaryAsked) summary.value = {};
  }
};

const load = async () => {
  try {
    const { data } = await InclamoAPI.getSlaPolicies();
    policies.value = data.policies;
    inboxes.value = data.inboxes;
    await loadSummary();
  } catch (error) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const chooseDays = async value => {
  days.value = value;
  await loadSummary();
};

const open = policy => {
  const first = fromSeconds(policy?.first_response_seconds);
  const resolution = fromSeconds(policy?.resolution_seconds);
  Object.assign(form, {
    name: policy?.name || '',
    firstValue: first.value,
    firstUnit: first.unit,
    resolutionValue: resolution.value,
    resolutionUnit: resolution.unit,
    businessHoursOnly: policy?.business_hours_only || false,
    allInboxes: policy ? policy.all_inboxes : true,
    // An inbox deleted since it was chosen has no box to untick: leave it out.
    inboxIds: (policy?.inbox_ids || []).filter(id => inboxes.value.some(inbox => inbox.id === id)),
  });
  errors.value = [];
  deleting.value = null;
  editing.value = policy ? policy.id : 'new';
};

const close = () => {
  editing.value = null;
  errors.value = [];
};

const payload = computed(() => ({
  name: form.name.trim(),
  first_response_seconds: toSeconds(form.firstValue, form.firstUnit),
  resolution_seconds: toSeconds(form.resolutionValue, form.resolutionUnit),
  business_hours_only: form.businessHoursOnly,
  all_inboxes: form.allInboxes,
  inbox_ids: form.allInboxes ? [] : form.inboxIds,
}));

const problems = () => {
  const found = [];
  const { name, first_response_seconds: first, resolution_seconds: resolution } = payload.value;
  if (!name) found.push(t('SETTINGS.SLA.ERRORS.NAME_NEEDED'));
  if (Number.isNaN(first) || Number.isNaN(resolution)) found.push(t('SETTINGS.SLA.ERRORS.TARGET_POSITIVE'));
  else if (first === null && resolution === null) found.push(t('SETTINGS.SLA.ERRORS.TARGET_NEEDED'));
  else if (first > MAX_TARGET_SECONDS || resolution > MAX_TARGET_SECONDS) found.push(t('SETTINGS.SLA.ERRORS.TARGET_TOO_LONG'));
  if (!form.allInboxes && form.inboxIds.length === 0) found.push(t('SETTINGS.SLA.ERRORS.INBOXES_NEEDED'));
  return found;
};

const save = async () => {
  errors.value = problems();
  if (errors.value.length) return;
  busy.value = true;
  try {
    if (editing.value === 'new') await InclamoAPI.createSlaPolicy(payload.value);
    else await InclamoAPI.updateSlaPolicy(editing.value, payload.value);
    close();
    await load();
  } catch (error) {
    errors.value = error.response?.data?.messages || [t('SETTINGS.SLA.ERRORS.NOT_SAVED')];
  } finally {
    busy.value = false;
  }
};

const move = async (index, step) => {
  const ids = policies.value.map(policy => policy.id);
  const [moved] = ids.splice(index, 1);
  ids.splice(index + step, 0, moved);
  busy.value = true;
  actionError.value = false;
  try {
    const { data } = await InclamoAPI.reorderSlaPolicies(ids);
    policies.value = data.policies;
  } catch (error) {
    actionError.value = true;
  } finally {
    busy.value = false;
  }
};

const remove = async policy => {
  busy.value = true;
  actionError.value = false;
  try {
    await InclamoAPI.deleteSlaPolicy(policy.id);
    deleting.value = null;
    await load();
  } catch (error) {
    actionError.value = true;
  } finally {
    busy.value = false;
  }
};

const targets = policy =>
  [
    policy.first_response_seconds ? t('SETTINGS.SLA.LIST.FIRST_RESPONSE', { time: duration(policy.first_response_seconds) }) : null,
    policy.resolution_seconds ? t('SETTINGS.SLA.LIST.RESOLUTION', { time: duration(policy.resolution_seconds) }) : null,
  ]
    .filter(Boolean)
    .join(' · ');

const covered = policy => {
  if (policy.all_inboxes) return t('SETTINGS.SLA.LIST.ALL_INBOXES');
  return policy.inbox_ids.map(id => inboxes.value.find(inbox => inbox.id === id)?.name).filter(Boolean).join(', ');
};

const share = target => {
  if (!target) return t('SETTINGS.SLA.SUMMARY.NO_TARGET');
  if (!target.total) return t('SETTINGS.SLA.SUMMARY.NOTHING_YET');
  return t('SETTINGS.SLA.SUMMARY.MET', { percent: target.met_percent, met: target.met, missed: target.missed, running: target.running });
};

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.SLA.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.SLA.TITLE')" :description="t('SETTINGS.SLA.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-sla-failed">{{ t('SETTINGS.SLA.FAILED') }}</p>
      <div v-else class="flex flex-col gap-4 text-sm text-n-slate-12" data-testid="inclamo-sla-page">
        <p v-if="actionError" role="alert" class="text-sm text-n-ruby-11" data-testid="inclamo-sla-action-error">{{ t('SETTINGS.SLA.ACTION_FAILED') }}</p>
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-2">
            <span class="text-n-slate-11">{{ t('SETTINGS.SLA.SUMMARY.PERIOD') }}</span>
            <button
              v-for="value in [7, 30]"
              :key="value"
              type="button"
              class="rounded-md border px-2 py-1"
              :class="days === value ? 'border-n-blue-border text-n-blue-text' : 'border-n-weak'"
              :data-testid="`inclamo-sla-days-${value}`"
              @click="chooseDays(value)"
            >
              {{ t('SETTINGS.SLA.SUMMARY.DAYS', { days: value }) }}
            </button>
          </div>
          <button v-if="editing === null" type="button" class="rounded-md border border-n-weak px-3 py-1.5" data-testid="inclamo-sla-add" @click="open(null)">
            {{ t('SETTINGS.SLA.ADD') }}
          </button>
        </div>

        <form v-if="editing !== null" class="flex flex-col gap-3 p-3 rounded-md border border-n-weak" data-testid="inclamo-sla-form" @submit.prevent="save">
          <label class="flex flex-col gap-1">
            <span>{{ t('SETTINGS.SLA.FORM.NAME') }}</span>
            <input v-model="form.name" type="text" maxlength="120" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-sla-name" />
          </label>
          <div class="flex flex-col gap-1">
            <span>{{ t('SETTINGS.SLA.FORM.FIRST_RESPONSE') }}</span>
            <div class="flex gap-2">
              <input v-model="form.firstValue" type="number" min="0" step="any" class="w-24 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-sla-first-value" />
              <select v-model="form.firstUnit" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-sla-first-unit">
                <option v-for="unit in unitNames" :key="unit" :value="unit">{{ t(`SETTINGS.SLA.UNITS.${unit}`) }}</option>
              </select>
            </div>
          </div>
          <div class="flex flex-col gap-1">
            <span>{{ t('SETTINGS.SLA.FORM.RESOLUTION') }}</span>
            <div class="flex gap-2">
              <input v-model="form.resolutionValue" type="number" min="0" step="any" class="w-24 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-sla-resolution-value" />
              <select v-model="form.resolutionUnit" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-sla-resolution-unit">
                <option v-for="unit in unitNames" :key="unit" :value="unit">{{ t(`SETTINGS.SLA.UNITS.${unit}`) }}</option>
              </select>
            </div>
            <span class="text-xs text-n-slate-11">{{ t('SETTINGS.SLA.FORM.TARGET_HINT') }}</span>
          </div>
          <label class="flex items-center gap-2">
            <input v-model="form.businessHoursOnly" type="checkbox" data-testid="inclamo-sla-business-hours" />
            {{ t('SETTINGS.SLA.FORM.BUSINESS_HOURS') }}
          </label>
          <div class="flex flex-col gap-1">
            <label class="flex items-center gap-2">
              <input v-model="form.allInboxes" type="radio" :value="true" data-testid="inclamo-sla-all-inboxes" />
              {{ t('SETTINGS.SLA.FORM.ALL_INBOXES') }}
            </label>
            <label class="flex items-center gap-2">
              <input v-model="form.allInboxes" type="radio" :value="false" data-testid="inclamo-sla-chosen-inboxes" />
              {{ t('SETTINGS.SLA.FORM.CHOSEN_INBOXES') }}
            </label>
            <div v-if="!form.allInboxes" class="flex flex-col gap-1 pl-6">
              <label v-for="inbox in inboxes" :key="inbox.id" class="flex items-center gap-2" :data-testid="`inclamo-sla-inbox-${inbox.id}`">
                <input v-model="form.inboxIds" type="checkbox" :value="inbox.id" />
                {{ inbox.name }}
              </label>
            </div>
          </div>
          <ul v-if="errors.length" class="text-n-ruby-11" data-testid="inclamo-sla-form-error">
            <li v-for="message in errors" :key="message">{{ message }}</li>
          </ul>
          <div class="flex gap-2">
            <button type="submit" class="rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-50" :disabled="busy" data-testid="inclamo-sla-save">{{ t('SETTINGS.SLA.FORM.SAVE') }}</button>
            <button type="button" class="px-3 py-1.5 text-n-slate-11" data-testid="inclamo-sla-cancel" @click="close">{{ t('SETTINGS.SLA.FORM.CANCEL') }}</button>
          </div>
        </form>

        <p v-if="policies.length === 0" class="text-n-slate-11" data-testid="inclamo-sla-empty">{{ t('SETTINGS.SLA.EMPTY') }}</p>
        <ol class="flex flex-col divide-y divide-n-weak">
          <li v-for="(policy, index) in policies" :key="policy.id" class="flex flex-col gap-1 py-3" :data-testid="`inclamo-sla-policy-${policy.id}`">
            <div class="flex items-center justify-between gap-2">
              <span class="font-medium" data-testid="inclamo-sla-policy-name">{{ policy.name }}</span>
              <span class="flex items-center gap-3">
                <button type="button" class="text-n-blue-text disabled:opacity-40" :disabled="busy || index === 0" :aria-label="t('SETTINGS.SLA.LIST.UP')" :data-testid="`inclamo-sla-up-${policy.id}`" @click="move(index, -1)">↑</button>
                <button type="button" class="text-n-blue-text disabled:opacity-40" :disabled="busy || index === policies.length - 1" :aria-label="t('SETTINGS.SLA.LIST.DOWN')" :data-testid="`inclamo-sla-down-${policy.id}`" @click="move(index, 1)">↓</button>
                <button type="button" class="text-n-blue-text" :data-testid="`inclamo-sla-edit-${policy.id}`" @click="open(policy)">{{ t('SETTINGS.SLA.LIST.EDIT') }}</button>
                <button type="button" class="text-n-ruby-11" :data-testid="`inclamo-sla-delete-${policy.id}`" @click="deleting = policy.id">{{ t('SETTINGS.SLA.LIST.DELETE') }}</button>
              </span>
            </div>
            <span data-testid="inclamo-sla-policy-targets">{{ targets(policy) }}</span>
            <span class="text-xs text-n-slate-11">
              {{ covered(policy) }}<template v-if="policy.business_hours_only"> · {{ t('SETTINGS.SLA.LIST.BUSINESS_HOURS') }}</template>
            </span>
            <span v-if="summary[policy.id]" class="text-xs text-n-slate-11" :data-testid="`inclamo-sla-summary-${policy.id}`">
              {{ t('SETTINGS.SLA.SUMMARY.CONVERSATIONS', { count: summary[policy.id].conversations }) }}
              · {{ t('SETTINGS.SLA.SUMMARY.FIRST_RESPONSE') }} {{ share(summary[policy.id].first_response) }}
              · {{ t('SETTINGS.SLA.SUMMARY.RESOLUTION') }} {{ share(summary[policy.id].resolution) }}
            </span>
            <span v-if="deleting === policy.id" class="flex items-center gap-3 text-xs" :data-testid="`inclamo-sla-delete-ask-${policy.id}`">
              {{ t('SETTINGS.SLA.LIST.DELETE_ASK') }}
              <button type="button" class="text-n-ruby-11" :disabled="busy" :data-testid="`inclamo-sla-delete-confirm-${policy.id}`" @click="remove(policy)">{{ t('SETTINGS.SLA.LIST.DELETE_YES') }}</button>
              <button type="button" class="text-n-slate-11" @click="deleting = null">{{ t('SETTINGS.SLA.LIST.DELETE_NO') }}</button>
            </span>
          </li>
        </ol>
      </div>
    </template>
  </SettingsLayout>
</template>
