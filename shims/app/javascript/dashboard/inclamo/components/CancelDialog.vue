<script setup>
import { ref, reactive } from 'vue';
import ActionDialog from './ActionDialog.vue';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
});
const emit = defineEmits(['done']);

const REASONS = ['CUSTOMER', 'INVENTORY', 'FRAUD', 'DECLINED', 'STAFF', 'OTHER'];
const frame = ref(null);
const form = reactive({ reason: 'CUSTOMER', refund: true, restock: true, notify: false });

const reset = () => Object.assign(form, { reason: 'CUSTOMER', refund: true, restock: true, notify: false });
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
    @opened="reset"
    @done="record => emit('done', record)"
  >
    <p class="font-medium text-n-ruby-11" data-testid="inclamo-cancel-warning">{{ t('DIALOG.CANCEL.WARNING') }}</p>
    <label class="flex flex-col gap-1">
      <span>{{ t('DIALOG.CANCEL.REASON') }}</span>
      <select v-model="form.reason" class="rounded-[var(--inclamo-control-radius,0.375rem)] border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-cancel-reason">
        <option v-for="reason in REASONS" :key="reason" :value="reason">{{ t(`DIALOG.CANCEL.REASONS.${reason}`) }}</option>
      </select>
    </label>
    <label class="flex items-center gap-2"><input v-model="form.refund" type="checkbox" data-testid="inclamo-cancel-refund" />{{ t('DIALOG.CANCEL.REFUND') }}</label>
    <label class="flex items-center gap-2"><input v-model="form.restock" type="checkbox" />{{ t('DIALOG.CANCEL.RESTOCK') }}</label>
    <label class="flex items-center gap-2"><input v-model="form.notify" type="checkbox" />{{ t('DIALOG.CANCEL.NOTIFY') }}</label>
  </ActionDialog>
</template>
