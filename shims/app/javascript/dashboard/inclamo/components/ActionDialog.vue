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
  // What a refusal for want of the right says; by default, the order-actions role.
  notAllowedText: { type: String, default: '' },
});

const emit = defineEmits(['done', 'opened', 'refused']);

const dialog = ref(null);
const actionId = ref('');
const busy = ref(false);
const message = ref('');
const settled = ref(false);
// The request sent with this id, while how it ended is not known. It may
// have reached the store, so it is sent again exactly as it was, and the
// form cannot be changed meanwhile: a change would not be what the store did.
const sent = ref(null);

const open = () => {
  actionId.value = newActionId();
  busy.value = false;
  message.value = '';
  settled.value = false;
  sent.value = null;
  emit('opened');
  dialog.value.open();
};

const explain = record => {
  if (record.outcome === 'running') return t('DIALOG.RUNNING');
  if (record.outcome === 'unknown' || record.outcome === 'pending') return t('DIALOG.UNKNOWN');
  if (record.refusal === 'not_allowed') return props.notAllowedText || t('DIALOG.NOT_ALLOWED');
  if (record.store_message) return t('DIALOG.FAILED', { message: record.store_message });
  const key = `ORDER.WHY_NOT.${record.refusal}`;
  return t(key) === key ? t('DIALOG.FAILED_PLAIN') : t(key, { scopes: '' });
};

const submit = async () => {
  if (busy.value || settled.value || !props.canConfirm) return;
  busy.value = true;
  message.value = '';
  sent.value = sent.value || { ...props.build(), action_id: actionId.value };
  try {
    const { data } = await InclamoAPI.performAction(props.conversationId, sent.value);
    if (data.outcome === 'accepted') {
      dialog.value.close();
      emit('done', data);
      return;
    }
    message.value = explain(data);
    // Running and unknown are final for this dialog; a refusal may be corrected and sent with a new id.
    // Pending: an earlier send of this id is still at the store, so the same id may be sent again.
    settled.value = !['refused', 'pending'].includes(data.outcome);
    if (data.outcome === 'refused') {
      actionId.value = newActionId();
      sent.value = null;
      emit('refused', data);
    } else emit('done', data);
  } catch (error) {
    // No answer at all: the same request is kept, so trying again cannot act twice.
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
      <fieldset class="flex min-w-0 flex-col gap-3" :disabled="Boolean(sent)" data-testid="inclamo-action-form">
        <slot />
      </fieldset>
      <p v-if="message" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-action-message">
        {{ message }}
      </p>
      <p v-if="sent && !busy && !settled" class="text-xs text-n-slate-11" data-testid="inclamo-action-sent-as-is">
        {{ t('DIALOG.SENT_AS_IS') }}
      </p>
    </div>
  </Dialog>
</template>
