<script setup>
import { ref, reactive } from 'vue';
import ActionDialog from './ActionDialog.vue';
import InclamoAPI from '../api';
import { money } from '../format';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
  canRefund: { type: Boolean, default: true },
});
const emit = defineEmits(['done']);

const REASONS = ['CUSTOMER', 'INVENTORY', 'FRAUD', 'DECLINED', 'STAFF', 'OTHER'];
const frame = ref(null);
const form = reactive({ reason: 'CUSTOMER', refund: true, restock: true, notify: false });

const preview = ref(null);
const loading = ref(false);
const failed = ref(false);
let generation = 0;
const loadPreview = async () => {
  const ticket = ++generation;
  preview.value = null;
  failed.value = false;
  loading.value = true;
  try {
    const { data } = await InclamoAPI.cancelPreview(props.conversationId, props.order.id, { refund: form.refund });
    if (ticket !== generation) return;
    preview.value = data;
    failed.value = !!data.refusal || data.refund === 'unknown';
  } catch { if (ticket === generation) failed.value = true; }
  finally { if (ticket === generation) loading.value = false; }
};
const reset = () => {
  Object.assign(form, { reason: 'CUSTOMER', refund: props.canRefund, restock: true, notify: false });
  loadPreview();
};
const build = () => ({ action_name: 'cancel', order_id: props.order.id, params: { ...form } });

defineExpose({ open: () => frame.value.open() });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('DIALOG.CANCEL.TITLE', { number: order.number })"
    :confirm-label="t('DIALOG.CANCEL.CONFIRM')"
    :build="build"
    :can-confirm="!loading && !failed && preview !== null"
    @opened="reset"
    @done="record => emit('done', record)"
  >
    <p class="font-medium text-n-ruby-11" data-testid="inclamo-cancel-warning">{{ t('DIALOG.CANCEL.WARNING') }}</p>
    <p v-if="loading" role="status">{{ t('DIALOG.CANCEL.CALCULATING') }}</p>
    <div v-else-if="failed" role="alert" class="text-n-ruby-11" data-testid="inclamo-cancel-preview-error">
      <p>{{ t('DIALOG.CANCEL.PREVIEW_FAILED') }}</p>
      <button type="button" class="text-n-blue-text" @click="loadPreview">{{ t('DIALOG.CANCEL.RETRY') }}</button>
    </div>
    <p v-else-if="preview" class="font-medium" data-testid="inclamo-cancel-amount">{{ form.refund && preview.amount ? t('DIALOG.CANCEL.AMOUNT', { amount: money(preview.amount, preview.currency) }) : t('DIALOG.CANCEL.NO_REFUND') }}</p>
    <label class="flex flex-col gap-1">
      <span>{{ t('DIALOG.CANCEL.REASON') }}</span>
      <select v-model="form.reason" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-cancel-reason">
        <option v-for="reason in REASONS" :key="reason" :value="reason">{{ t(`DIALOG.CANCEL.REASONS.${reason}`) }}</option>
      </select>
    </label>
    <label class="flex items-center gap-2"><input v-model="form.refund" type="checkbox" :disabled="!canRefund" data-testid="inclamo-cancel-refund" @change="loadPreview" />{{ t('DIALOG.CANCEL.REFUND') }}</label>
    <p v-if="!canRefund" class="text-xs text-n-slate-11">{{ t('SETTINGS.ORDER_ROLES.REFUND_REQUIRED') }}</p>
    <label class="flex items-center gap-2"><input v-model="form.restock" type="checkbox" />{{ t('DIALOG.CANCEL.RESTOCK') }}</label>
    <label class="flex items-center gap-2"><input v-model="form.notify" type="checkbox" />{{ t('DIALOG.CANCEL.NOTIFY') }}</label>
  </ActionDialog>
</template>
