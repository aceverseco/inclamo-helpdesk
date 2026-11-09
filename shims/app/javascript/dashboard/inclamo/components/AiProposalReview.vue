<script setup>
import { ref, watch, onMounted, onBeforeUnmount } from 'vue';
import InclamoAPI from '../api';
import { t, has } from '../i18n';
import { money, dateTime } from '../format';
const props = defineProps({ conversationId: { type: [Number, String], required: true }, administrator: Boolean });
const emit = defineEmits(['changed']);
const proposals = ref([]);
const error = ref('');
const busy = ref(null);
const identityReview = ref(null);
let generation = 0;
const load = async () => {
  const ticket = ++generation;
  try {
    const { data } = await InclamoAPI.getAiProposals(props.conversationId);
    if (ticket === generation) { proposals.value = data.proposals; error.value = ''; }
  } catch { if (ticket === generation) error.value = t('AI_AUTHORITY.REVIEW_LOAD_FAILED'); }
};
const act = async (proposal, action) => {
  const conversation = props.conversationId;
  busy.value = proposal.id;
  error.value = '';
  try {
    await InclamoAPI.reviewAiProposal(conversation, proposal.id, action, { review_digest: proposal.review_digest });
    if (conversation !== props.conversationId) return;
    identityReview.value = null;
    await load();
    emit('changed');
  } catch (failure) {
    if (conversation !== props.conversationId) return;
    const code = failure.response?.data?.error;
    error.value = has(`AI_AUTHORITY.ERRORS.${code}`) ? t(`AI_AUTHORITY.ERRORS.${code}`) : t('AI_AUTHORITY.REVIEW_FAILED');
  } finally { if (conversation === props.conversationId) busy.value = null; }
};
const title = key => has(`AI_AUTHORITY.FIELDS.${key}`) ? t(`AI_AUTHORITY.FIELDS.${key}`) : key.replaceAll('_', ' ');
const internalFields = new Set(['id', 'variant_id', 'line_item_id', 'account_id', 'created_at', 'updated_at']);
// Product names and quantities explain the reviewed change; Shopify identifiers
// and internal database fields are not useful in the approval decision.
const enumFields = new Set(['reason', 'difference', 'refund', 'mode', 'delivery', 'kind', 'type', 'audience']);
const describe = (value, field) => {
  if (value === null || value === '') return t('AI_AUTHORITY.CLEAR');
  if (typeof value === 'boolean') return t(value ? 'AI_AUTHORITY.YES' : 'AI_AUTHORITY.NO');
  if (Array.isArray(value)) return value.map(item => describe(item, field)).join('; ');
  if (typeof value === 'object') {
    if (value.gateway && 'amount' in value) return `${value.gateway}: ${money(value.amount, value.currency)}`;
    if ('amount' in value && ('currency' in value || 'currencyCode' in value)) return money(value.amount, value.currency || value.currencyCode);
    if (value.title && 'quantity' in value) {
      const quantity = Object.hasOwn(value, 'quantity_before') ? `${value.quantity_before} → ${value.quantity}` : value.quantity;
      return `${value.title}${value.variant ? ` (${value.variant})` : ''} · ${t('AI_AUTHORITY.FIELDS.quantity')}: ${quantity}${value.unit_price ? ` · ${t('AI_AUTHORITY.FIELDS.unit_price')}: ${describe(value.unit_price)}` : ''}`;
    }
    return Object.entries(value).filter(([key]) => !internalFields.has(key)).map(([key, item]) => `${title(key)}: ${describe(item, key)}`).join(' · ');
  }
  if (enumFields.has(field) && typeof value === 'string' && has(`AI_AUTHORITY.VALUES.${value}`)) return t(`AI_AUTHORITY.VALUES.${value}`);
  return String(value);
};
const changes = proposal => Object.entries({ ...proposal.request.params, ...(proposal.request.address ? { address: proposal.request.address } : {}), ...(Object.hasOwn(proposal.request, 'note') ? { note: proposal.request.note } : {}) }).filter(([key]) => {
  if (proposal.summary.effect.lines && ['lines', 'additions'].includes(key)) return false;
  if (proposal.summary.effect.items && key === 'items') return false;
  return key !== 'preset_id';
});
const effects = proposal => Object.entries(proposal.summary.effect).filter(([key, value]) => !internalFields.has(key) && key !== 'currency' && (!Array.isArray(value) || value.length)).map(([key, value]) => {
  if (['amount', 'maximum'].includes(key)) return [key, { amount: value, currency: proposal.summary.effect.currency }];
  if (key === 'destinations') return [key, value.map(destination => ({ ...destination, currency: proposal.summary.effect.currency }))];
  return [key, value];
});
watch(() => props.conversationId, () => { proposals.value = []; busy.value = null; identityReview.value = null; load(); }, { immediate: true });
let timer;
onMounted(() => { timer = setInterval(() => { if (document.visibilityState === 'visible' && busy.value === null) load(); }, 15000); });
onBeforeUnmount(() => { clearInterval(timer); generation += 1; });
defineExpose({ reload: load });
</script>

<template>
  <section class="flex flex-col gap-3 pt-3" data-testid="inclamo-ai-proposals">
    <div class="flex items-center justify-between gap-2">
      <h4 class="font-medium">{{ t('AI_AUTHORITY.PROPOSALS') }}</h4>
      <button type="button" class="text-xs text-n-blue-text" :disabled="busy !== null" @click="load">{{ t('AI_AUTHORITY.RELOAD') }}</button>
    </div>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <p v-if="!proposals.length && !error" class="text-xs text-n-slate-11">{{ t('AI_AUTHORITY.NONE') }}</p>
    <details v-for="proposal in proposals" :open="['proposed', 'pending', 'running', 'unknown'].includes(proposal.state)" :key="proposal.id" class="flex flex-col gap-2 rounded-lg border border-n-weak p-3 text-sm break-words" :data-testid="`inclamo-ai-proposal-${proposal.id}`">
      <summary class="font-semibold cursor-pointer">{{ t(`ACTION_RIGHTS.${proposal.action}`) }} {{ proposal.summary.order_number }} · {{ t(`AI_AUTHORITY.OUTCOMES.${proposal.state}`) }}</summary>
      <div class="flex flex-col gap-2 pt-2">
      <p class="text-xs text-n-slate-11">{{ proposal.initiator.name }} · {{ t(`AI_AUTHORITY.OUTCOMES.${proposal.state}`) }}</p>
      <dl class="flex flex-col gap-1">
        <template v-for="[key, value] in changes(proposal)" :key="key"><dt class="font-medium">{{ title(key) }}</dt><dd class="whitespace-pre-wrap">{{ describe(value, key) }}</dd></template>
        <template v-if="proposal.summary.order_total"><dt>{{ t('AI_AUTHORITY.CURRENT_TOTAL') }}</dt><dd>{{ describe(proposal.summary.order_total) }}</dd></template>
        <template v-for="[key, value] in effects(proposal)" :key="`effect-${key}`"><dt>{{ title(key) }}</dt><dd>{{ describe(value, key) }}</dd></template>
      </dl>
      <p v-if="proposal.approver" class="text-xs">{{ t(proposal.state === 'rejected' ? 'AI_AUTHORITY.REJECTED_BY' : 'AI_AUTHORITY.APPROVED_BY', { name: proposal.approver.name }) }}</p>
      <p v-if="proposal.result?.refusal" class="text-n-ruby-11">{{ has(`ORDER.WHY_NOT.${proposal.result.refusal}`) ? t(`ORDER.WHY_NOT.${proposal.result.refusal}`) : proposal.result.refusal }}</p>
      <template v-if="proposal.state === 'proposed'">
        <p class="text-xs" :class="proposal.expired ? 'text-n-amber-11' : 'text-n-slate-11'">{{ proposal.expired ? t('AI_AUTHORITY.EXPIRED') : t('AI_AUTHORITY.EXPIRES', { time: dateTime(proposal.expires_at) }) }}</p>
        <p v-if="!proposal.can_approve" class="text-xs text-n-slate-11">{{ t('AI_AUTHORITY.NO_PERMISSION') }}</p>
        <div class="flex flex-wrap gap-2">
          <button type="button" class="px-2 py-1 rounded-md bg-n-brand text-white disabled:opacity-50" :disabled="busy !== null || !proposal.can_approve || proposal.expired" data-testid="ai-approve" @click="act(proposal, 'approve')">{{ t('AI_AUTHORITY.APPROVE') }}</button>
          <button type="button" class="px-2 py-1 rounded-md border border-n-weak" :disabled="busy !== null" data-testid="ai-refresh" @click="act(proposal, 'refresh')">{{ t('AI_AUTHORITY.REFRESH') }}</button>
          <button type="button" class="px-2 py-1 rounded-md border border-n-weak" :disabled="busy !== null" data-testid="ai-reject" @click="act(proposal, 'reject')">{{ t('AI_AUTHORITY.REJECT') }}</button>
        </div>
        <template v-if="administrator">
          <button v-if="identityReview !== proposal.id" type="button" class="text-xs text-n-blue-text text-left" @click="identityReview = proposal.id">{{ t('AI_AUTHORITY.VERIFY_IDENTITY') }}</button>
          <div v-else class="flex flex-col gap-2 text-xs p-2 rounded-md bg-n-amber-3">
            <p>{{ t('AI_AUTHORITY.VERIFY_HELP') }}</p>
            <button type="button" class="text-n-blue-text text-left" :disabled="busy !== null" @click="act(proposal, 'verify_identity')">{{ t('AI_AUTHORITY.VERIFY_CONFIRM') }}</button>
          </div>
        </template>
      </template>
      </div>
    </details>
  </section>
</template>
