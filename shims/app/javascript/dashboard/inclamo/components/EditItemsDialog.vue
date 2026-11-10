<script setup>
// Changes the items of an order that has not fully shipped: the quantity of an
// unshipped item, an item taken off, a product added from the catalogue. The
// store calculates the new total and the difference before anything is
// saved; saving refunds nothing, the card then leads into the refund dialog.
// Shipped units stay on the order: a shipped item has no controls and a
// partly shipped one cannot go below what has shipped.
import { ref, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import ProductSearch from './ProductSearch.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { money } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
});
const emit = defineEmits(['done']);

const MAX_QUANTITY = 999;
const frame = ref(null);
const search = ref(null);
const lines = ref([]);
const additions = ref([]);
const notify = ref(false);
const invoice = ref(false);
const summary = ref(null);
const calculatedFor = ref('');
const calculating = ref(false);
const problem = ref('');

const whole = quantity => String(quantity).trim() !== '' && Number.isInteger(Number(quantity));
const lineOk = line => whole(line.quantity) && Number(line.quantity) >= line.shipped && Number(line.quantity) <= MAX_QUANTITY;
const additionOk = addition => whole(addition.quantity) && Number(addition.quantity) >= 1 && Number(addition.quantity) <= MAX_QUANTITY;
const valid = computed(() => lines.value.every(lineOk) && additions.value.every(additionOk));

const changedLines = computed(() =>
  lines.value.filter(line => line.editable && lineOk(line) && Number(line.quantity) !== line.current).map(line => ({ line_item_id: line.id, quantity: Number(line.quantity) }))
);
const params = () => ({
  lines: changedLines.value,
  additions: additions.value.map(addition => ({ variant_id: addition.variant.id, quantity: Number(addition.quantity) })),
});
const changed = computed(() => changedLines.value.length > 0 || additions.value.length > 0);
// A summary holds for the edit it was calculated for; a change asks for a new one.
const fingerprint = computed(() => JSON.stringify(params()));
const current = computed(() => Boolean(summary.value) && calculatedFor.value === fingerprint.value);
const canConfirm = computed(() => current.value && valid.value && changed.value && !calculating.value);

const owed = computed(() => summary.value?.difference === 'owed');
// The store's email about the change carries the invoice: then it is shown as included.
const invoiceShown = computed({
  get: () => notify.value || invoice.value,
  set: value => {
    invoice.value = value;
  },
});

const explain = error => {
  const data = error?.response?.data || {};
  if (data.message) return t('DIALOG.FAILED', { message: data.message });
  if (data.error === 'not_allowed') return t('DIALOG.NOT_ALLOWED');
  const key = `ORDER.WHY_NOT.${data.error}`;
  return t(key) === key ? t('DIALOG.FAILED_PLAIN') : t(key, { scopes: (data.missing_scopes || []).join(', ') });
};

const calculate = async () => {
  if (!valid.value || !changed.value || calculating.value) return;
  calculating.value = true;
  problem.value = '';
  const asked = fingerprint.value;
  try {
    const { data } = await InclamoAPI.editItemsPreview(props.conversationId, props.order.id, params());
    summary.value = data;
    calculatedFor.value = asked;
  } catch (error) {
    summary.value = null;
    problem.value = explain(error);
  } finally {
    calculating.value = false;
  }
};

const add = ({ product, variant }) => {
  const same = additions.value.find(addition => addition.variant.id === variant.id);
  if (same) same.quantity = Math.min(Number(same.quantity) + 1, MAX_QUANTITY);
  else additions.value.push({ product, variant, quantity: 1 });
};
const removeAddition = index => additions.value.splice(index, 1);
// Takes off what has not shipped; shipped units stay.
const takeOff = line => {
  line.quantity = line.shipped;
};

const reset = () => {
  lines.value = (props.order.items || [])
    .filter(item => Number(item.current_quantity ?? item.quantity) > 0)
    .map(item => {
      const current = Number(item.current_quantity ?? item.quantity);
      const unshipped = Math.min(Number(item.unfulfilled_quantity || 0), current);
      return { id: item.id, title: item.title, variant: item.variant, unitPrice: item.unit_price, current, shipped: current - unshipped, editable: unshipped > 0, quantity: current };
    });
  additions.value = [];
  notify.value = false;
  invoice.value = false;
  summary.value = null;
  calculatedFor.value = '';
  problem.value = '';
  search.value?.reset();
};

const build = () => ({
  action_name: 'edit_items',
  order_id: props.order.id,
  params: {
    ...params(),
    notify: notify.value,
    invoice: owed.value && Boolean(summary.value?.customer_email) && !notify.value && invoice.value,
    expected: { total_after: summary.value?.total_after?.amount, balance: summary.value?.balance?.amount },
  },
});

// The order changed in the store since the summary: the store's new one is shown, to be saved again.
const refused = record => {
  if (record.refusal === 'summary_changed' && record.result?.summary) summary.value = record.result.summary;
};

const named = line => [line.title, line.variant].filter(part => part && part !== 'Default Title').join(' · ');
const changes = computed(() => (summary.value?.lines || []).filter(line => line.quantity !== line.quantity_before));

defineExpose({ open: () => frame.value.open() });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('EDIT_ITEMS.TITLE', { number: order.number })"
    :confirm-label="t('EDIT_ITEMS.CONFIRM')"
    :can-confirm="canConfirm"
    :build="build"
    @opened="reset"
    @refused="refused"
    @done="record => emit('done', record)"
  >
    <section class="flex flex-col gap-1" data-testid="inclamo-edit-lines">
      <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.ITEMS') }}</h4>
      <div v-for="line in lines" :key="line.id" class="flex items-center justify-between gap-2" data-testid="inclamo-edit-line" :data-line-id="line.id">
        <span class="flex min-w-0 flex-col">
          <span class="truncate">{{ named(line) }}</span>
          <span v-if="!line.editable" class="text-xs text-n-slate-11" data-testid="inclamo-edit-shipped">{{ t('EDIT_ITEMS.SHIPPED', { count: line.current }) }}</span>
          <span v-else-if="line.shipped" class="text-xs text-n-slate-11" data-testid="inclamo-edit-partly-shipped">{{ t('EDIT_ITEMS.PARTLY_SHIPPED', { count: line.shipped }) }}</span>
        </span>
        <span v-if="!line.editable" class="shrink-0 text-n-slate-11" data-testid="inclamo-edit-locked">{{ t('ORDER.QUANTITY', { count: line.current }) }}</span>
        <span v-else class="flex shrink-0 items-center gap-2">
          <input
            v-model="line.quantity"
            type="number"
            :min="line.shipped"
            :max="MAX_QUANTITY"
            :aria-label="t('EDIT_ITEMS.QUANTITY')"
            class="w-16 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
            :class="{ 'border-n-ruby-9': !lineOk(line) }"
            data-testid="inclamo-edit-quantity"
          />
          <button
            type="button"
            class="text-xs text-n-ruby-11 disabled:opacity-50"
            :disabled="Number(line.quantity) === line.shipped"
            data-testid="inclamo-edit-take-off"
            @click="takeOff(line)"
          >
            {{ t('EDIT_ITEMS.TAKE_OFF') }}
          </button>
        </span>
      </div>
      <p v-if="!lines.every(lineOk)" class="text-xs text-n-ruby-11" data-testid="inclamo-edit-invalid">{{ t('EDIT_ITEMS.INVALID_QUANTITY') }}</p>
    </section>

    <section class="flex flex-col gap-1" data-testid="inclamo-edit-additions">
      <h4 class="text-xs uppercase text-n-slate-10">{{ t('EDIT_ITEMS.ADD') }}</h4>
      <ProductSearch ref="search" :conversation-id="conversationId" @select="add" />
      <div v-for="(addition, index) in additions" :key="addition.variant.id" class="flex items-center justify-between gap-2" data-testid="inclamo-edit-addition">
        <span class="truncate">{{ addition.product.title }}<template v-if="addition.variant.title"> · {{ addition.variant.title }}</template></span>
        <span class="flex shrink-0 items-center gap-2">
          <span class="text-xs text-n-slate-11">{{ money(addition.variant.price.amount, addition.variant.price.currency) }}</span>
          <input
            v-model="addition.quantity"
            type="number"
            min="1"
            :max="MAX_QUANTITY"
            :aria-label="t('EDIT_ITEMS.QUANTITY')"
            class="w-16 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
            data-testid="inclamo-edit-addition-quantity"
          />
          <button type="button" class="text-xs text-n-ruby-11" data-testid="inclamo-edit-addition-remove" @click="removeAddition(index)">{{ t('NEW_ORDER.REMOVE') }}</button>
        </span>
      </div>
    </section>

    <button
      type="button"
      class="self-start rounded-md border border-n-weak px-3 py-1 disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="!valid || !changed || calculating"
      data-testid="inclamo-edit-calculate"
      @click="calculate"
    >
      {{ t('EDIT_ITEMS.CALCULATE') }}
    </button>
    <p v-if="problem" class="rounded-md bg-n-ruby-3 p-2 text-n-ruby-11" data-testid="inclamo-edit-problem">{{ problem }}</p>

    <section v-if="summary" class="flex flex-col gap-1 rounded-md bg-n-alpha-1 p-2" :class="{ 'opacity-50': !current }" data-testid="inclamo-edit-summary">
      <p v-for="line in changes" :key="line.id" data-testid="inclamo-edit-summary-change">
        {{ line.quantity ? t('EDIT_ITEMS.CHANGE', { item: named(line), from: line.quantity_before, to: line.quantity }) : t('EDIT_ITEMS.REMOVED', { item: named(line) }) }}
      </p>
      <p v-for="(line, index) in summary.added" :key="`added-${index}`" data-testid="inclamo-edit-summary-added">
        {{ t('EDIT_ITEMS.ADDED', { item: named(line), count: line.quantity }) }}
      </p>
      <div class="flex justify-between gap-2 border-t border-n-weak pt-1">
        <span>{{ t('EDIT_ITEMS.TOTAL_BEFORE') }}</span><span>{{ money(summary.total_before.amount, summary.total_before.currency) }}</span>
      </div>
      <div class="flex justify-between gap-2 font-medium" data-testid="inclamo-edit-total">
        <span>{{ t('EDIT_ITEMS.TOTAL_AFTER') }}</span><span>{{ money(summary.total_after.amount, summary.total_after.currency) }}</span>
      </div>
      <p class="font-medium" :data-difference="summary.difference" data-testid="inclamo-edit-difference">
        {{ t(`EDIT_ITEMS.DIFFERENCE.${summary.difference}`, { amount: money(summary.amount, summary.currency) }) }}
      </p>
      <p v-if="!current" class="text-xs text-n-amber-11" data-testid="inclamo-edit-stale">{{ t('EDIT_ITEMS.STALE') }}</p>
    </section>

    <fieldset v-if="summary" class="flex flex-col gap-1" data-testid="inclamo-edit-options">
      <label class="flex items-center gap-2">
        <input v-model="notify" type="checkbox" data-testid="inclamo-edit-notify" />
        <span>{{ t('EDIT_ITEMS.NOTIFY') }}</span>
      </label>
      <p class="pl-6 text-xs text-n-slate-11">{{ t('EDIT_ITEMS.NOTIFY_HINT') }}</p>
      <template v-if="owed">
        <label v-if="summary.customer_email" class="flex items-center gap-2">
          <input v-model="invoiceShown" type="checkbox" :disabled="notify" data-testid="inclamo-edit-invoice" />
          <span>{{ t('EDIT_ITEMS.INVOICE', { amount: money(summary.amount, summary.currency) }) }}</span>
        </label>
        <p v-if="summary.customer_email && notify" class="pl-6 text-xs text-n-slate-11" data-testid="inclamo-edit-invoice-included">{{ t('EDIT_ITEMS.INVOICE_INCLUDED') }}</p>
        <p v-if="!summary.customer_email" class="text-xs text-n-amber-11" data-testid="inclamo-edit-no-email">{{ t('EDIT_ITEMS.NO_EMAIL') }}</p>
      </template>
    </fieldset>
  </ActionDialog>
</template>
