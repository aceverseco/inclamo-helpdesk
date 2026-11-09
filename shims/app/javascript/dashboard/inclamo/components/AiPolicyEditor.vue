<script setup>
import { ref, onMounted } from 'vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
const emit = defineEmits(['loaded', 'changed', 'dirty']);
const rows = ref([]);
const states = ref([]);
const currency = ref('');
const loading = ref(true);
const busy = ref('');
const error = ref('');
const saved = ref('');
const dirty = ref(new Set());
const markDirty = action => { dirty.value.add(action); saved.value = ''; emit('dirty'); };
const orderActions = ['address', 'edit_items', 'cancel', 'refund', 'replacement', 'order_tags', 'order_note'];
const moneyActions = [...orderActions, 'new_order', 'discount'];
const modes = ['forbidden', 'propose', 'autonomous'];
const apply = data => {
  currency.value = data.currency || '';
  states.value = data.allowed_states || [];
  rows.value = data.policies.map(row => ({ ...row, limits: { currency: currency.value, max_amount: '', max_percentage: '', allowed_states: [], ...row.limits } }));
};
const load = async () => {
  error.value = '';
  loading.value = true;
  try { const { data } = await InclamoAPI.getAiPolicies(); apply(data); emit('loaded'); }
  catch { error.value = t('AI_AUTHORITY.LOAD_FAILED'); }
  finally { loading.value = false; }
};
const save = async row => {
  busy.value = row.action;
  error.value = '';
  saved.value = '';
  const limits = {};
  if (row.mode === 'autonomous') {
    if (moneyActions.includes(row.action)) Object.assign(limits, { currency: currency.value, max_amount: row.limits.max_amount });
    if (orderActions.includes(row.action)) limits.allowed_states = row.limits.allowed_states;
    if (row.action === 'discount') limits.max_percentage = row.limits.max_percentage;
  }
  try {
    const { data } = await InclamoAPI.setAiPolicy(row.action, { mode: row.mode, limits });
    const persisted = data.policies.find(entry => entry.action === row.action);
    Object.assign(row, persisted, { limits: { ...row.limits, ...persisted.limits } });
    saved.value = row.action;
    dirty.value.delete(row.action);
    emit('changed');
    if (dirty.value.size) emit('dirty');
  } catch (failure) { error.value = failure.response?.data?.message || t('AI_AUTHORITY.SAVE_FAILED'); }
  finally { busy.value = ''; }
};
onMounted(load);
defineExpose({ reload: load });
</script>

<template>
  <section class="flex flex-col gap-3" data-testid="inclamo-ai-policies">
    <h3 class="font-semibold">{{ t('AI_AUTHORITY.TITLE') }}</h3>
    <p class="text-sm text-n-slate-11">{{ t('AI_AUTHORITY.INTRO') }}</p>
    <p v-if="loading" role="status">{{ t('AI_AUTHORITY.LOADING') }}</p>
    <p v-if="error" role="alert" class="text-n-ruby-11" data-testid="inclamo-ai-policy-error">{{ error }}</p>
    <button v-if="error && !rows.length" type="button" class="text-n-blue-text" @click="load">{{ t('AI_AUTHORITY.RETRY') }}</button>
    <form v-for="row in rows" :key="row.action" class="p-3 border border-n-weak rounded-lg flex flex-col gap-3" :data-testid="`inclamo-ai-policy-${row.action}`" @submit.prevent="save(row)" @change="markDirty(row.action)">
      <label class="flex flex-wrap items-center justify-between gap-2">
        <span class="font-medium">{{ t(`ACTION_RIGHTS.${row.action}`) }}</span>
        <select v-model="row.mode" :disabled="!!busy" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" :aria-label="t(`ACTION_RIGHTS.${row.action}`)">
          <option v-for="mode in modes" :key="mode" :value="mode">{{ t(`AI_AUTHORITY.MODES.${mode}`) }}</option>
        </select>
      </label>
      <template v-if="row.mode === 'autonomous'">
        <p class="text-xs text-n-slate-11">{{ t('AI_AUTHORITY.IDENTITY') }}</p>
        <template v-if="moneyActions.includes(row.action)">
          <p class="text-xs text-n-slate-11">{{ t(row.action === 'discount' ? 'AI_AUTHORITY.DISCOUNT_LIMIT_HELP' : 'AI_AUTHORITY.AMOUNT_HELP') }}</p>
          <label class="flex flex-col gap-1">
            <span>{{ t('AI_AUTHORITY.MAX_AMOUNT', { currency }) }}</span>
            <input v-model="row.limits.max_amount" type="number" required min="0.01" step="0.01" :disabled="!!busy" data-testid="ai-max-amount" />
          </label>
          <p v-if="!currency" class="text-n-amber-11">{{ t('AI_AUTHORITY.CONNECT_FIRST') }}</p>
        </template>
        <label v-if="row.action === 'discount'" class="flex flex-col gap-1">
          <span>{{ t('AI_AUTHORITY.MAX_PERCENTAGE') }}</span>
          <input v-model="row.limits.max_percentage" type="number" required min="0" max="100" step="0.01" :disabled="!!busy" />
        </label>
        <fieldset v-if="orderActions.includes(row.action)" class="flex flex-wrap gap-3">
          <legend class="mb-2 text-sm">{{ t('AI_AUTHORITY.STATES') }}</legend>
          <label v-for="state in states" :key="state" class="flex items-center gap-1 text-xs">
            <input v-model="row.limits.allowed_states" type="checkbox" :value="state" :disabled="!!busy" />
            {{ t(`AI_AUTHORITY.STATES_TEXT.${state}`) }}
          </label>
        </fieldset>
      </template>
      <div class="flex items-center gap-3">
        <button type="submit" class="rounded-md bg-n-brand px-3 py-1.5 text-white disabled:opacity-50" :disabled="!!busy || (row.mode === 'autonomous' && moneyActions.includes(row.action) && !currency)">{{ t(busy === row.action ? 'AI_AUTHORITY.SAVING' : 'AI_AUTHORITY.SAVE') }}</button>
        <span v-if="saved === row.action" role="status" class="text-sm text-n-teal-11">{{ t('AI_AUTHORITY.SAVED') }}</span>
      </div>
    </form>
  </section>
</template>
