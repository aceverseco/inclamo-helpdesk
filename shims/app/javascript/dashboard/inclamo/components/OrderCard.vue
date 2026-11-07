<script setup>
import { ref, computed } from 'vue';
import CancelDialog from './CancelDialog.vue';
import RefundDialog from './RefundDialog.vue';
import AddressDialog from './AddressDialog.vue';
import ReplacementDialog from './ReplacementDialog.vue';
import EditItemsDialog from './EditItemsDialog.vue';
import { t } from '../i18n';
import { money, date, status } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
  connection: { type: Object, required: true },
  viewer: { type: Object, required: true },
  marked: { type: Boolean, default: false },
  // The unsettled action record of this order, if any (cancelling, outcome unknown).
  openAction: { type: Object, default: null },
  startOpen: { type: Boolean, default: false },
  // Whether "order again" is offered: the order is one of the matched customer's.
  canOrderAgain: { type: Boolean, default: false },
});
const emit = defineEmits(['changed', 'mark', 'unmark', 'order-again']);

const ACTIONS = ['cancel', 'refund', 'address', 'replacement'];
const expanded = ref(props.startOpen);
const dialogs = { cancel: ref(null), refund: ref(null), address: ref(null), replacement: ref(null), edit_items: ref(null) };

const limited = computed(() => props.connection.customer_data === 'limited');
// What the order holds and comes to now, after edits and refunds: an item
// taken off is not listed (founder, 2026-11-07).
const total = computed(() => (props.order.current_total?.amount ? props.order.current_total : props.order.total));
const quantityOf = item => Number(item.current_quantity ?? item.quantity);
const currentItems = computed(() => (props.order.items || []).filter(item => quantityOf(item) > 0));

// Why an action is unavailable, as a sentence, or '' when it can be performed.
const whyNot = action => {
  if (!props.viewer.can_act_on_orders) return t('ORDER.WHY_NOT.no_role');
  const scope = (props.connection.actions || []).find(entry => entry.name === action);
  if (scope && !scope.available) {
    return t(`ORDER.WHY_NOT.${scope.reason}`, { scopes: (scope.missing_scopes || []).join(', ') });
  }
  const own = props.order.actions?.[action];
  if (own && !own.allowed) return t(`ORDER.WHY_NOT.${own.reason}`);
  return '';
};

const cancelling = computed(() => props.openAction?.action === 'cancel' && props.openAction?.outcome === 'running');
const unknown = computed(() => props.openAction?.outcome === 'unknown');
const start = action => dialogs[action].value.open();

// "Edit items" is offered only when it can be done: to whoever may act, on a
// connection with the scope, for an order with something left to ship. When
// only the scope is missing, a line names it.
const editScope = computed(() => (props.connection.actions || []).find(entry => entry.name === 'edit_items'));
const canEdit = computed(
  () => !whyNot('edit_items') && Boolean(editScope.value?.available) && props.order.actions?.edit_items?.allowed === true && !cancelling.value
);
const editScopeMissing = computed(() => {
  if (!props.viewer.can_act_on_orders || props.order.actions?.edit_items?.allowed === false) return '';
  const scope = editScope.value;
  if (!scope || scope.available) return '';
  return t(`ORDER.WHY_NOT.${scope.reason}`, { scopes: (scope.missing_scopes || []).join(', ') });
});

// After an edit: what is due back, offered as a refund of that amount, and
// what became of the invoice when it was not sent.
const edited = ref(null);
const refundDue = () => dialogs.refund.value.open({ amount: edited.value.amount, currency: edited.value.currency });
const afterRefund = record => {
  if (record.outcome === 'accepted') edited.value = null;
  emit('changed', record);
};
const afterEdit = record => {
  const result = record.result || {};
  edited.value = record.outcome === 'accepted' ? { ...result } : null;
  emit('changed', record);
  if (record.outcome === 'accepted' && result.difference === 'due_back') refundDue();
};
</script>

<template>
  <div class="rounded-lg outline outline-1 outline-n-weak bg-n-solid-1" :data-testid="`inclamo-order-${order.number}`">
    <button type="button" class="flex w-full items-start justify-between gap-2 px-3 py-2 text-left" @click="expanded = !expanded">
      <span class="flex flex-col">
        <span class="font-medium text-n-slate-12">{{ order.number }}</span>
        <span class="text-xs text-n-slate-11">{{ t('ORDER.PLACED', { date: date(order.created_at) }) }}</span>
      </span>
      <span class="flex flex-col items-end">
        <span class="font-medium text-n-slate-12" data-testid="inclamo-order-total">{{ money(total.amount, total.currency) }}</span>
        <span class="text-xs text-n-slate-11" data-testid="inclamo-order-statuses">
          <template v-if="cancelling">{{ t('ORDER.CANCELLING') }}</template>
          <template v-else-if="order.cancelled_at">{{ t('ORDER.CANCELLED') }}</template>
          <template v-else>{{ status(order.financial_status) }} · {{ status(order.fulfillment_status) }}</template>
        </span>
      </span>
    </button>
    <p v-if="marked" class="px-3 pb-1 text-xs text-n-teal-11" data-testid="inclamo-order-marked">{{ t('ORDER.MARKED') }}</p>
    <p v-if="unknown" class="mx-3 mb-2 p-2 rounded-md bg-n-amber-3 text-xs text-n-amber-11" data-testid="inclamo-order-unknown">
      {{ t('ORDER.OUTCOME_UNKNOWN') }}
      <a :href="order.admin_url" target="_blank" rel="noopener noreferrer" class="underline">{{ t('ORDER.OPEN_IN_ADMIN') }}</a>
    </p>
    <div v-if="expanded" class="flex flex-col gap-3 px-3 pb-3 text-sm text-n-slate-12">
      <section>
        <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.ITEMS') }}</h4>
        <ul>
          <li v-for="item in currentItems" :key="item.id" class="flex justify-between gap-2" data-testid="inclamo-order-item" :data-line-id="item.id">
            <span class="truncate">{{ item.title }} <span class="text-n-slate-11">{{ t('ORDER.QUANTITY', { count: quantityOf(item) }) }}</span></span>
            <span>{{ money(item.unit_price.amount, item.unit_price.currency) }}</span>
          </li>
        </ul>
      </section>
      <section>
        <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.ADDRESS') }}</h4>
        <p v-if="order.shipping_address" data-testid="inclamo-order-address">
          {{ order.shipping_address.name }}<br />
          {{ order.shipping_address.address1 }} {{ order.shipping_address.address2 }}<br />
          {{ order.shipping_address.zip }} {{ order.shipping_address.city }}, {{ order.shipping_address.country }}
        </p>
        <p v-else class="text-n-slate-11" data-testid="inclamo-order-address-hidden">{{ limited ? t('ORDER.ADDRESS_HIDDEN') : '—' }}</p>
      </section>
      <section>
        <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.SHIPMENTS') }}</h4>
        <p v-if="!order.shipments.length" class="text-n-slate-11">{{ t('ORDER.NO_SHIPMENTS') }}</p>
        <ul v-else>
          <li v-for="shipment in order.shipments" :key="shipment.id" data-testid="inclamo-order-shipment">
            <span v-for="(tracking, index) in shipment.tracking" :key="index" class="flex justify-between gap-2">
              <span>{{ tracking.company }} {{ tracking.number }}</span>
              <a v-if="tracking.url" :href="tracking.url" target="_blank" rel="noopener noreferrer" class="text-n-blue-text">{{ t('ORDER.TRACK') }}</a>
            </span>
          </li>
        </ul>
      </section>
      <section v-if="order.refunds.length" data-testid="inclamo-order-refunds">
        <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.REFUNDS') }}</h4>
        <p>{{ t('ORDER.REFUNDED', { amount: money(order.refunded.amount, order.refunded.currency) }) }}</p>
        <p>{{ t('ORDER.REFUNDABLE', { amount: money(order.refundable.amount, order.refundable.currency) }) }}</p>
      </section>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="action in ACTIONS"
          :key="action"
          type="button"
          class="rounded-md border border-n-weak px-2 py-1 text-xs disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!!whyNot(action) || cancelling"
          :title="whyNot(action)"
          :data-testid="`inclamo-action-${action}`"
          @click="start(action)"
        >
          {{ t(`ORDER.ACTIONS.${action}`) }}
        </button>
        <button
          v-if="canEdit"
          type="button"
          class="rounded-md border border-n-weak px-2 py-1 text-xs"
          data-testid="inclamo-action-edit_items"
          @click="start('edit_items')"
        >
          {{ t('ORDER.ACTIONS.edit_items') }}
        </button>
        <button
          v-if="canOrderAgain"
          type="button"
          class="rounded-md border border-n-weak px-2 py-1 text-xs disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="!!whyNot('new_order')"
          :title="whyNot('new_order')"
          data-testid="inclamo-action-order-again"
          @click="emit('order-again', order)"
        >
          {{ t('ORDER.ORDER_AGAIN') }}
        </button>
      </div>
      <p v-if="editScopeMissing" class="text-xs text-n-slate-11" data-testid="inclamo-edit-unavailable">
        {{ t('ORDER.EDIT_UNAVAILABLE', { reason: editScopeMissing }) }}
      </p>
      <div v-if="edited" class="flex flex-col gap-1 rounded-md bg-n-alpha-1 p-2 text-xs" data-testid="inclamo-edited">
        <p>{{ t('ORDER.EDITED.SAVED') }}</p>
        <p v-if="edited.difference === 'due_back'" class="flex flex-wrap items-center justify-between gap-2" data-testid="inclamo-edited-due-back">
          <span>{{ t('EDIT_ITEMS.DIFFERENCE.due_back', { amount: money(edited.amount, edited.currency) }) }}</span>
          <button type="button" class="text-n-blue-text" data-testid="inclamo-edited-refund" @click="refundDue">
            {{ t('ORDER.EDITED.REFUND', { amount: money(edited.amount, edited.currency) }) }}
          </button>
        </p>
        <p v-if="edited.invoice === 'sent'" data-testid="inclamo-edited-invoice">{{ t('ORDER.EDITED.INVOICE_SENT') }}</p>
        <p v-if="edited.invoice === 'refused'" class="text-n-ruby-11" data-testid="inclamo-edited-invoice">
          {{ t('ORDER.EDITED.INVOICE_REFUSED', { message: edited.invoice_message || '' }) }}
        </p>
        <p v-if="edited.invoice === 'unknown'" class="text-n-amber-11" data-testid="inclamo-edited-invoice">{{ t('ORDER.EDITED.INVOICE_UNKNOWN') }}</p>
      </div>
      <div class="flex flex-wrap items-center justify-between gap-2 text-xs">
        <button v-if="!marked" type="button" class="text-n-blue-text" data-testid="inclamo-order-mark" @click="emit('mark', order)">{{ t('ORDER.MARK') }}</button>
        <button v-else type="button" class="text-n-blue-text" data-testid="inclamo-order-unmark" @click="emit('unmark', order)">{{ t('ORDER.UNMARK') }}</button>
        <a :href="order.admin_url" target="_blank" rel="noopener noreferrer" class="text-n-blue-text" data-testid="inclamo-order-admin-link">{{ t('ORDER.OPEN_IN_ADMIN') }}</a>
      </div>
    </div>
    <CancelDialog :ref="element => (dialogs.cancel.value = element)" :conversation-id="conversationId" :order="order" @done="record => emit('changed', record)" />
    <RefundDialog :ref="element => (dialogs.refund.value = element)" :conversation-id="conversationId" :order="order" @done="afterRefund" />
    <AddressDialog :ref="element => (dialogs.address.value = element)" :conversation-id="conversationId" :order="order" @done="record => emit('changed', record)" />
    <ReplacementDialog :ref="element => (dialogs.replacement.value = element)" :conversation-id="conversationId" :order="order" @done="record => emit('changed', record)" />
    <EditItemsDialog :ref="element => (dialogs.edit_items.value = element)" :conversation-id="conversationId" :order="order" @done="afterEdit" />
  </div>
</template>
