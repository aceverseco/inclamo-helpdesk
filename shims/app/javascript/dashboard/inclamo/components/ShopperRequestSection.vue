<script setup>
// The card of a ticket about one shopper's data, in the conversation sidebar
// (sidebarSections): what Shopify or the shopper asked, the shopper's email
// and phone while the request is open, the contacts that match them now with
// links, the date of automatic deletion, a hold with its author, time and
// reason, and how it was done. Its actions are the administrators': "Delete"
// (after a confirmation that names the numbers), "Hold" (with a reason),
// "Lift hold" and "Mark answered".
import { ref, computed, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { t } from '../i18n';
import { dateTime } from '../format';
import { shopperRequestsApi, shopperRequestIdOf } from '../shopperRequests';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: [Number, String], default: undefined },
});

const store = useStore();
const requestId = computed(() => shopperRequestIdOf(store?.getters?.getConversationById?.(props.conversationId)));
const accountId = computed(() => store?.getters?.getCurrentAccountId);

const card = ref(null);
const loading = ref(true);
const failed = ref('');
const busy = ref(false);
const message = ref('');
const reason = ref('');
const dialogs = { delete: ref(null), hold: ref(null), lift: ref(null), answered: ref(null) };
const deleteDialog = dialogs.delete;
const holdDialog = dialogs.hold;
const liftDialog = dialogs.lift;
const answeredDialog = dialogs.answered;

const errorText = error => {
  const code = error?.response?.data?.error;
  return ['forbidden', 'wrong_state', 'reason_missing', 'not_done'].includes(code) ? t(`SHOPPER_REQUEST.ERRORS.${code}`) : t('SHOPPER_REQUEST.ERRORS.failed');
};

const load = async () => {
  if (!requestId.value) return;
  loading.value = true;
  failed.value = '';
  try {
    const { data } = await shopperRequestsApi.read(requestId.value);
    card.value = data;
  } catch (error) {
    failed.value = errorText(error);
  } finally {
    loading.value = false;
  }
};

watch(requestId, () => load(), { immediate: true });

const erasure = computed(() => card.value?.kind === 'shopper_erasure');
const done = computed(() => card.value?.state === 'done');
const contacts = computed(() => card.value?.contacts || []);
const conversationsFound = computed(() => contacts.value.reduce((sum, contact) => sum + contact.conversations, 0));
const datePassed = computed(() => Boolean(card.value?.delete_after) && new Date(card.value.delete_after).getTime() <= Date.now());

const actions = computed(() => {
  if (!card.value || done.value) return [];
  if (!erasure.value) return ['answered'];
  return card.value.state === 'held' ? ['delete', 'lift'] : ['delete', 'hold'];
});

const doneText = computed(() => {
  const finished = card.value?.done;
  if (!finished) return '';
  const time = dateTime(finished.at);
  if (finished.by === 'automatic') return t('SHOPPER_REQUEST.DONE_AUTOMATICALLY', { time });
  if (finished.by === 'store_erasure') return t('SHOPPER_REQUEST.DONE_WITH_STORE', { time });
  return t('SHOPPER_REQUEST.DONE_BY', { name: finished.user?.name || t('SHOPPER_REQUEST.SOMEONE'), time });
});

const contactPath = contact => `/app/accounts/${accountId.value}/contacts/${contact.id}`;

const open = action => {
  message.value = '';
  reason.value = '';
  dialogs[action].value?.open();
};

const act = async (action, payload = {}) => {
  if (busy.value) return;
  if (action === 'hold' && !reason.value.trim()) return;
  busy.value = true;
  message.value = '';
  try {
    const { data } = await shopperRequestsApi.act(requestId.value, action, payload);
    card.value = data;
    dialogs[action].value?.close();
  } catch (error) {
    message.value = errorText(error);
    if (error?.response?.data?.error === 'wrong_state') load();
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <div v-if="requestId" class="px-4 py-3 text-sm text-n-slate-12 flex flex-col gap-2" data-testid="inclamo-shopper-request">
    <p v-if="loading && !card" class="text-n-slate-11">{{ t('SHOPPER_REQUEST.LOADING') }}</p>
    <p v-else-if="failed && !card" class="text-n-ruby-11" data-testid="inclamo-shopper-request-failed">
      {{ failed }}
      <button type="button" class="text-n-blue-text" @click="load">{{ t('SHOPPER_REQUEST.RETRY') }}</button>
    </p>
    <template v-else-if="card">
      <span class="font-medium" data-testid="inclamo-shopper-request-kind">{{ t(`SHOPPER_REQUEST.KIND.${card.kind}`) }}</span>
      <span class="text-xs text-n-slate-11">{{ t('SHOPPER_REQUEST.ONLY_ADMINISTRATORS', { inbox: t('SHOPPER_REQUEST.INBOX') }) }}</span>
      <div class="flex items-start justify-between gap-3" data-testid="inclamo-shopper-request-state">
        <span class="text-n-slate-11 shrink-0">{{ t('SHOPPER_REQUEST.STATE_LABEL') }}</span>
        <span class="text-right">{{ t(`SHOPPER_REQUEST.STATE.${card.state}`) }}</span>
      </div>
      <div class="flex items-start justify-between gap-3" data-testid="inclamo-shopper-request-received">
        <span class="text-n-slate-11 shrink-0">{{ t('SHOPPER_REQUEST.RECEIVED') }}</span>
        <span class="text-right">{{ dateTime(card.received_at) }}</span>
      </div>
      <template v-if="!done">
        <div class="flex items-start justify-between gap-3" data-testid="inclamo-shopper-request-email">
          <span class="text-n-slate-11 shrink-0">{{ t('SHOPPER_REQUEST.EMAIL') }}</span>
          <span class="text-right break-all min-w-0">{{ card.email || t('SHOPPER_REQUEST.NONE_GIVEN') }}</span>
        </div>
        <div class="flex items-start justify-between gap-3" data-testid="inclamo-shopper-request-phone">
          <span class="text-n-slate-11 shrink-0">{{ t('SHOPPER_REQUEST.PHONE') }}</span>
          <span class="text-right break-all min-w-0">{{ card.phone || t('SHOPPER_REQUEST.NONE_GIVEN') }}</span>
        </div>
        <div v-if="erasure && card.delete_after" class="flex items-start justify-between gap-3" data-testid="inclamo-shopper-request-date">
          <span class="text-n-slate-11 shrink-0">{{ card.state === 'held' ? t('SHOPPER_REQUEST.DATE_HELD') : t('SHOPPER_REQUEST.DATE') }}</span>
          <span class="text-right">{{ dateTime(card.delete_after) }}</span>
        </div>
        <p v-if="card.overdue" class="text-n-ruby-11" data-testid="inclamo-shopper-request-overdue">{{ t('SHOPPER_REQUEST.OVERDUE') }}</p>
        <div class="flex flex-col gap-1" data-testid="inclamo-shopper-request-contacts">
          <span class="text-n-slate-11">{{ t('SHOPPER_REQUEST.CONTACTS') }}</span>
          <p v-if="contacts.length === 0" class="text-n-slate-11">{{ t('SHOPPER_REQUEST.NO_CONTACTS') }}</p>
          <router-link
            v-for="contact in contacts"
            :key="contact.id"
            :to="contactPath(contact)"
            class="text-n-blue-text"
            :data-testid="`inclamo-shopper-request-contact-${contact.id}`"
          >
            {{ t('SHOPPER_REQUEST.CONTACT', { name: contact.name || `#${contact.id}`, count: contact.conversations }) }}
          </router-link>
        </div>
      </template>
      <div v-if="card.hold" class="flex flex-col gap-1 rounded-md bg-n-amber-3 p-2" data-testid="inclamo-shopper-request-held">
        <span>{{ t('SHOPPER_REQUEST.HELD', { name: card.hold.held_by?.name || t('SHOPPER_REQUEST.SOMEONE'), time: dateTime(card.hold.held_at) }) }}</span>
        <span class="break-words" data-testid="inclamo-shopper-request-held-reason">{{ t('SHOPPER_REQUEST.HELD_REASON', { reason: card.hold.reason }) }}</span>
        <span class="text-xs text-n-slate-11">{{ t('SHOPPER_REQUEST.HELD_NOTE') }}</span>
      </div>
      <p v-if="done" data-testid="inclamo-shopper-request-done">{{ doneText }}</p>
      <div v-if="actions.length" class="flex flex-wrap gap-2 pt-1">
        <Button
          v-for="action in actions"
          :key="action"
          type="button"
          :color="action === 'delete' ? 'ruby' : 'slate'"
          variant="outline"
          size="xs"
          :disabled="busy"
          :data-testid="`inclamo-shopper-request-${action}`"
          @click="open(action)"
        >
          {{ t(`SHOPPER_REQUEST.ACTIONS.${action}`) }}
        </Button>
      </div>
      <p v-if="message && !busy" class="text-n-ruby-11" data-testid="inclamo-shopper-request-message">{{ message }}</p>
    </template>

    <Dialog
      ref="deleteDialog"
      type="alert"
      :title="t('SHOPPER_REQUEST.DELETE_DIALOG.TITLE')"
      :confirm-button-label="t('SHOPPER_REQUEST.ACTIONS.delete')"
      :cancel-button-label="t('SHOPPER_REQUEST.CLOSE')"
      :is-loading="busy"
      @confirm="act('delete')"
    >
      <div class="flex flex-col gap-2 text-sm text-n-slate-12" data-testid="inclamo-shopper-request-delete-dialog">
        <p>{{ t('SHOPPER_REQUEST.DELETE_DIALOG.BODY', { contacts: contacts.length, conversations: conversationsFound }) }}</p>
        <p class="text-n-ruby-11">{{ t('SHOPPER_REQUEST.DELETE_DIALOG.WARNING') }}</p>
        <p v-if="message" class="text-n-ruby-11">{{ message }}</p>
      </div>
    </Dialog>
    <Dialog
      ref="holdDialog"
      :title="t('SHOPPER_REQUEST.HOLD_DIALOG.TITLE')"
      :confirm-button-label="t('SHOPPER_REQUEST.ACTIONS.hold')"
      :cancel-button-label="t('SHOPPER_REQUEST.CLOSE')"
      :is-loading="busy"
      :disable-confirm-button="!reason.trim()"
      @confirm="act('hold', { reason: reason.trim() })"
    >
      <div class="flex flex-col gap-2 text-sm text-n-slate-12" data-testid="inclamo-shopper-request-hold-dialog">
        <p>{{ t('SHOPPER_REQUEST.HOLD_DIALOG.BODY') }}</p>
        <label class="flex flex-col gap-1">
          <span>{{ t('SHOPPER_REQUEST.HOLD_DIALOG.REASON') }}</span>
          <textarea v-model="reason" rows="3" maxlength="1000" class="!mb-0" data-testid="inclamo-shopper-request-reason" />
        </label>
        <p v-if="message" class="text-n-ruby-11">{{ message }}</p>
      </div>
    </Dialog>
    <Dialog
      ref="liftDialog"
      :title="t('SHOPPER_REQUEST.LIFT_DIALOG.TITLE')"
      :confirm-button-label="t('SHOPPER_REQUEST.ACTIONS.lift')"
      :cancel-button-label="t('SHOPPER_REQUEST.CLOSE')"
      :is-loading="busy"
      @confirm="act('lift')"
    >
      <div class="flex flex-col gap-2 text-sm text-n-slate-12" data-testid="inclamo-shopper-request-lift-dialog">
        <p v-if="datePassed">{{ t('SHOPPER_REQUEST.LIFT_DIALOG.AFTER') }}</p>
        <p v-else>{{ t('SHOPPER_REQUEST.LIFT_DIALOG.BEFORE', { time: dateTime(card?.delete_after) }) }}</p>
        <p v-if="message" class="text-n-ruby-11">{{ message }}</p>
      </div>
    </Dialog>
    <Dialog
      ref="answeredDialog"
      :title="t('SHOPPER_REQUEST.ANSWERED_DIALOG.TITLE')"
      :confirm-button-label="t('SHOPPER_REQUEST.ACTIONS.answered')"
      :cancel-button-label="t('SHOPPER_REQUEST.CLOSE')"
      :is-loading="busy"
      @confirm="act('answered')"
    >
      <div class="flex flex-col gap-2 text-sm text-n-slate-12" data-testid="inclamo-shopper-request-answered-dialog">
        <p>{{ t('SHOPPER_REQUEST.ANSWERED_DIALOG.BODY') }}</p>
        <p v-if="message" class="text-n-ruby-11">{{ message }}</p>
      </div>
    </Dialog>
  </div>
</template>
