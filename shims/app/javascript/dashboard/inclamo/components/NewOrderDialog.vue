<script setup>
// A new order for the customer of the conversation: items from the catalogue,
// one discount for the whole order, a shipping charge and a note; the store's
// own totals before anything is created; then the payment link, by the
// store's invoice email or into the reply. Nothing here marks it paid.
import { ref, reactive, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import ProductSearch from './ProductSearch.vue';
import InclamoAPI from '../api';
import { insertIntoReply } from '../reply';
import { t } from '../i18n';
import { money } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  // The matched customer as the panel shows it: { id, name, email, phone }.
  customer: { type: Object, required: true },
  // The store's currency, for the discount amount and the shipping charge.
  currency: { type: String, default: '' },
});
const emit = defineEmits(['done']);

const MAX_QUANTITY = 999;
const frame = ref(null);
const search = ref(null);
const lines = ref([]);
const discount = reactive({ type: 'none', value: '' });
const shipping = ref('');
const note = ref('');
const delivery = ref('');
const summary = ref(null);
const calculatedFor = ref('');
const calculating = ref(false);
const problem = ref('');
const skipped = ref([]);
const prefilling = ref(false);
// Counts the openings of the dialog: an answer asked for in an earlier one is dropped.
let opening = 0;

const canEmail = computed(() => Boolean(props.customer?.email));
const quantityOk = quantity => Number.isInteger(Number(quantity)) && Number(quantity) >= 1 && Number(quantity) <= MAX_QUANTITY;
const linesOk = computed(() => lines.value.length > 0 && lines.value.every(line => quantityOk(line.quantity)));

const params = () => ({
  lines: lines.value.map(line => ({ variant_id: line.variant.id, quantity: Number(line.quantity) })),
  discount: discount.type === 'none' || !String(discount.value).trim() ? null : { type: discount.type, value: String(discount.value).trim() },
  shipping: String(shipping.value).trim() || null,
});
// A summary holds for the order it was calculated for; a change asks for a new one.
const fingerprint = computed(() => JSON.stringify(params()));
const current = computed(() => Boolean(summary.value) && calculatedFor.value === fingerprint.value);
const canConfirm = computed(() => current.value && linesOk.value && Boolean(delivery.value) && !calculating.value && !prefilling.value);
const positive = amount => Number(amount?.amount) > 0;

// One line per variant: choosing it again adds to its quantity.
const add = ({ product, variant }, quantity = 1) => {
  const same = lines.value.find(line => line.variant.id === variant.id);
  if (same) same.quantity = Math.min(Number(same.quantity) + quantity, MAX_QUANTITY);
  else lines.value.push({ product, variant, quantity });
};
const remove = index => lines.value.splice(index, 1);

const explain = error => {
  const data = error?.response?.data || {};
  if (data.message) return t('DIALOG.FAILED', { message: data.message });
  if (data.error === 'not_allowed') return t('DIALOG.NOT_ALLOWED');
  const key = `ORDER.WHY_NOT.${data.error}`;
  return t(key) === key ? t('DIALOG.FAILED_PLAIN') : t(key, { scopes: '' });
};

const calculate = async () => {
  if (!linesOk.value || calculating.value) return;
  const mine = opening;
  calculating.value = true;
  problem.value = '';
  const asked = fingerprint.value;
  try {
    const { data } = await InclamoAPI.newOrderPreview(props.conversationId, params());
    if (mine !== opening) return;
    summary.value = data;
    calculatedFor.value = asked;
  } catch (error) {
    if (mine !== opening) return;
    summary.value = null;
    problem.value = explain(error);
  } finally {
    if (mine === opening) calculating.value = false;
  }
};

const reset = () => {
  opening += 1;
  calculating.value = false;
  prefilling.value = false;
  lines.value = [];
  discount.type = 'none';
  discount.value = '';
  shipping.value = '';
  note.value = '';
  // Without an email the link can only go into the reply.
  delivery.value = canEmail.value ? '' : 'reply';
  summary.value = null;
  calculatedFor.value = '';
  problem.value = '';
  skipped.value = [];
  search.value?.reset();
};

// "Order again": the items and quantities of that order, which the agent can change.
const prefill = async order => {
  const mine = opening;
  prefilling.value = true;
  try {
    const { data } = await InclamoAPI.newOrderPrefill(props.conversationId, order.id);
    if (mine !== opening) return;
    lines.value = [];
    (data.lines || []).forEach(line => add(line, Number(line.quantity)));
    skipped.value = data.skipped || [];
  } catch (error) {
    if (mine === opening) problem.value = explain(error);
  } finally {
    if (mine === opening) prefilling.value = false;
  }
};

const open = async (fromOrder = null) => {
  frame.value.open();
  if (fromOrder) await prefill(fromOrder);
};

const build = () => ({
  action_name: 'new_order',
  params: { ...params(), delivery: delivery.value },
  note: note.value.trim() || undefined,
});

const done = record => {
  if (record.outcome === 'accepted' && record.result?.delivery === 'reply') insertIntoReply(record.result.invoice_url);
  emit('done', record);
};

defineExpose({ open });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('NEW_ORDER.TITLE', { name: customer.name })"
    :confirm-label="t('NEW_ORDER.CONFIRM')"
    :can-confirm="canConfirm"
    :build="build"
    @opened="reset"
    @done="done"
  >
    <p data-testid="inclamo-new-order-intro">{{ t('NEW_ORDER.INTRO') }}</p>
    <ProductSearch ref="search" :conversation-id="conversationId" @select="add" />
    <p v-if="prefilling" class="text-xs text-n-slate-11" data-testid="inclamo-new-order-prefilling">{{ t('NEW_ORDER.PREFILLING') }}</p>
    <p v-if="skipped.length" class="text-xs text-n-amber-11" data-testid="inclamo-new-order-skipped">
      {{ t('NEW_ORDER.SKIPPED', { items: skipped.map(item => item.title).join(', ') }) }}
    </p>

    <section class="flex flex-col gap-1" data-testid="inclamo-new-order-lines">
      <h4 class="text-xs uppercase text-n-slate-10">{{ t('ORDER.ITEMS') }}</h4>
      <p v-if="!lines.length" class="text-n-slate-11" data-testid="inclamo-new-order-empty">{{ t('NEW_ORDER.NO_LINES') }}</p>
      <div v-for="(line, index) in lines" :key="line.variant.id" class="flex items-center justify-between gap-2" data-testid="inclamo-new-order-line">
        <span class="truncate">{{ line.product.title }}<template v-if="line.variant.title"> · {{ line.variant.title }}</template></span>
        <span class="flex shrink-0 items-center gap-2">
          <span class="text-xs text-n-slate-11">{{ money(line.variant.price.amount, line.variant.price.currency) }}</span>
          <input
            v-model="line.quantity"
            type="number"
            min="1"
            :max="MAX_QUANTITY"
            :aria-label="t('NEW_ORDER.QUANTITY')"
            class="w-16 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
            data-testid="inclamo-new-order-quantity"
          />
          <button type="button" class="text-xs text-n-ruby-11" data-testid="inclamo-new-order-remove" @click="remove(index)">{{ t('NEW_ORDER.REMOVE') }}</button>
        </span>
      </div>
    </section>

    <div class="flex flex-wrap items-center gap-2">
      <label class="flex items-center gap-2">
        <span>{{ t('NEW_ORDER.DISCOUNT') }}</span>
        <select v-model="discount.type" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1" data-testid="inclamo-new-order-discount-type">
          <option value="none">{{ t('NEW_ORDER.DISCOUNT_NONE') }}</option>
          <option value="percentage">{{ t('NEW_ORDER.DISCOUNT_PERCENTAGE') }}</option>
          <option value="amount">{{ t('NEW_ORDER.DISCOUNT_AMOUNT', { currency }) }}</option>
        </select>
      </label>
      <input
        v-if="discount.type !== 'none'"
        v-model="discount.value"
        type="text"
        inputmode="decimal"
        :aria-label="t('NEW_ORDER.DISCOUNT_VALUE')"
        class="w-24 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
        data-testid="inclamo-new-order-discount-value"
      />
    </div>
    <label class="flex items-center gap-2">
      <span>{{ t('NEW_ORDER.SHIPPING', { currency }) }}</span>
      <input
        v-model="shipping"
        type="text"
        inputmode="decimal"
        :placeholder="t('NEW_ORDER.SHIPPING_NONE')"
        class="w-24 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
        data-testid="inclamo-new-order-shipping"
      />
    </label>
    <label class="flex flex-col gap-1">
      <span>{{ t('NEW_ORDER.NOTE') }}</span>
      <textarea v-model="note" rows="2" maxlength="1000" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1" data-testid="inclamo-new-order-note" />
    </label>

    <button
      type="button"
      class="self-start rounded-md border border-n-weak px-3 py-1 disabled:cursor-not-allowed disabled:opacity-50"
      :disabled="!linesOk || calculating || prefilling"
      data-testid="inclamo-new-order-calculate"
      @click="calculate"
    >
      {{ t('NEW_ORDER.CALCULATE') }}
    </button>
    <p v-if="problem" class="rounded-md bg-n-ruby-3 p-2 text-n-ruby-11" data-testid="inclamo-new-order-problem">{{ problem }}</p>

    <section v-if="summary" class="flex flex-col gap-1 rounded-md bg-n-alpha-1 p-2" :class="{ 'opacity-50': !current }" data-testid="inclamo-new-order-summary">
      <div v-for="(line, index) in summary.lines" :key="index" class="flex justify-between gap-2" data-testid="inclamo-new-order-summary-line">
        <span class="truncate">{{ line.title }} <span class="text-n-slate-11">{{ t('ORDER.QUANTITY', { count: line.quantity }) }}</span></span>
        <span>{{ money(line.total.amount, line.total.currency) }}</span>
      </div>
      <div class="flex justify-between gap-2 border-t border-n-weak pt-1">
        <span>{{ t('NEW_ORDER.SUBTOTAL') }}</span><span>{{ money(summary.subtotal.amount, summary.subtotal.currency) }}</span>
      </div>
      <div v-if="positive(summary.discount)" class="flex justify-between gap-2" data-testid="inclamo-new-order-summary-discount">
        <span>{{ t('NEW_ORDER.DISCOUNT') }}</span><span>−{{ money(summary.discount.amount, summary.discount.currency) }}</span>
      </div>
      <div v-if="positive(summary.shipping)" class="flex justify-between gap-2" data-testid="inclamo-new-order-summary-shipping">
        <span>{{ t('NEW_ORDER.SHIPPING_LINE') }}</span><span>{{ money(summary.shipping.amount, summary.shipping.currency) }}</span>
      </div>
      <div class="flex justify-between gap-2" data-testid="inclamo-new-order-summary-tax">
        <span>{{ summary.taxes_included ? t('NEW_ORDER.TAX_INCLUDED') : t('NEW_ORDER.TAX') }}</span><span>{{ money(summary.tax.amount, summary.tax.currency) }}</span>
      </div>
      <div class="flex justify-between gap-2 font-medium" data-testid="inclamo-new-order-total">
        <span>{{ t('NEW_ORDER.TOTAL') }}</span><span>{{ money(summary.total.amount, summary.total.currency) }}</span>
      </div>
      <p v-for="(warning, index) in summary.warnings" :key="`warning-${index}`" class="text-xs text-n-amber-11">{{ warning }}</p>
      <p v-if="!current" class="text-xs text-n-amber-11" data-testid="inclamo-new-order-stale">{{ t('NEW_ORDER.STALE') }}</p>
    </section>

    <fieldset v-if="summary" class="flex flex-col gap-1" data-testid="inclamo-new-order-delivery">
      <legend class="text-xs uppercase text-n-slate-10">{{ t('NEW_ORDER.DELIVERY') }}</legend>
      <label v-if="canEmail" class="flex items-center gap-2">
        <input v-model="delivery" type="radio" value="email" data-testid="inclamo-new-order-delivery-email" />
        <span>{{ t('NEW_ORDER.DELIVERY_EMAIL', { email: customer.email }) }}</span>
      </label>
      <p v-if="canEmail" class="pl-6 text-xs text-n-slate-11">{{ t('NEW_ORDER.DELIVERY_EMAIL_HINT') }}</p>
      <label class="flex items-center gap-2">
        <input v-model="delivery" type="radio" value="reply" data-testid="inclamo-new-order-delivery-reply" />
        <span>{{ t('NEW_ORDER.DELIVERY_REPLY') }}</span>
      </label>
      <p class="pl-6 text-xs text-n-slate-11">{{ t('NEW_ORDER.DELIVERY_REPLY_HINT') }}</p>
    </fieldset>
  </ActionDialog>
</template>
