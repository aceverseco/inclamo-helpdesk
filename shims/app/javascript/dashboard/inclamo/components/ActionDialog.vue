<script setup>
// The frame every order action shares: a confirmation that sends one action
// with one id, and says plainly how it ended.
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { newActionId } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  title: { type: String, required: true },
  confirmLabel: { type: String, required: true },
  canConfirm: { type: Boolean, default: true },
  // Returns { action_name, order_id, params, address } for the request.
  build: { type: Function, required: true },
});

const emit = defineEmits(['done', 'opened']);

const dialog = ref(null);
const actionId = ref('');
const busy = ref(false);
const message = ref('');
const settled = ref(false);

const open = () => {
  actionId.value = newActionId();
  busy.value = false;
  message.value = '';
  settled.value = false;
  emit('opened');
  dialog.value.open();
};

const explain = record => {
  if (record.outcome === 'running') return t('DIALOG.RUNNING');
  if (record.outcome === 'unknown' || record.outcome === 'pending') return t('DIALOG.UNKNOWN');
  if (record.refusal === 'not_allowed') return t('DIALOG.NOT_ALLOWED');
  if (record.store_message) return t('DIALOG.FAILED', { message: record.store_message });
  const key = `ORDER.WHY_NOT.${record.refusal}`;
  return t(key) === key ? t('DIALOG.FAILED_PLAIN') : t(key, { scopes: '' });
};

const submit = async () => {
  if (busy.value || settled.value) return;
  busy.value = true;
  message.value = '';
  try {
    const { data } = await InclamoAPI.performAction(props.conversationId, { ...props.build(), action_id: actionId.value });
    if (data.outcome === 'accepted') {
      dialog.value.close();
      emit('done', data);
      return;
    }
    message.value = explain(data);
    // Running and unknown are final for this dialog; a refusal may be corrected and sent with a new id.
    // Pending: an earlier send of this id is still at the store, so the same id may be sent again.
    settled.value = !['refused', 'pending'].includes(data.outcome);
    if (data.outcome === 'refused') actionId.value = newActionId();
    else emit('done', data);
  } catch (error) {
    // No answer at all: the same id is kept, so trying again cannot act twice.
    message.value = t('DIALOG.UNKNOWN');
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="title"
    :confirm-button-label="confirmLabel"
    :cancel-button-label="t('DIALOG.CLOSE')"
    :is-loading="busy"
    :disable-confirm-button="!canConfirm || settled"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-action-dialog">
      <slot />
      <p v-if="message" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-action-message">
        {{ message }}
      </p>
    </div>
  </Dialog>
</template>
