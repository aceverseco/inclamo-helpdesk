<script setup>
import { ref, reactive, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { money } from '../format';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
});
const emit = defineEmits(['done']);

const frame = ref(null);
const form = reactive({ mode: 'full', amount: '', shipping: false, restock: false, notify: false, quantities: {} });
const preview = ref(null);
const previewError = ref('');
const calculating = ref(false);

const maximum = computed(() => Number(props.order.refundable?.amount || 0));
const refundableItems = computed(() => (props.order.items || []).filter(item => item.refundable_quantity > 0));
const chosenItems = computed(() =>
  Object.entries(form.quantities)
    .filter(([, quantity]) => Number(quantity) > 0)
    .map(([lineItemId, quantity]) => ({ line_item_id: lineItemId, quantity: Number(quantity) }))
);
const aboveMaximum = computed(() => form.mode === 'amount' && Number(form.amount) > maximum.value);
const valid = computed(() => {
  if (form.mode === 'amount') return Number(form.amount) > 0 && !aboveMaximum.value;
  if (form.mode === 'items') return chosenItems.value.length > 0;
  return maximum.value > 0;
});

const params = () => {
  const base = { mode: form.mode, restock: form.restock, notify: form.notify };
  if (form.mode === 'amount') return { ...base, amount: String(form.amount) };
  if (form.mode === 'items') return { ...base, items: chosenItems.value, shipping: form.shipping };
  return base;
};
const build = () => ({ action_name: 'refund', order_id: props.order.id, params: params() });

const reset = () => {
  Object.assign(form, { mode: 'full', amount: '', shipping: false, restock: false, notify: false, quantities: {} });
  preview.value = null;
  previewError.value = '';
};

// What exactly will be refunded and where the money goes, asked from the store.
const calculate = async () => {
  if (!valid.value) return;
  calculating.value = true;
  previewError.value = '';
  try {
    const { data } = await InclamoAPI.refundPreview(props.conversationId, props.order.id, params());
    preview.value = data;
  } catch (error) {
    preview.value = null;
    previewError.value = error.response?.data?.message || t('DIALOG.FAILED_PLAIN');
  } finally {
    calculating.value = false;
  }
};

const confirmLabel = computed(() =>
  t('DIALOG.REFUND.CONFIRM', { amount: preview.value ? money(preview.value.amount, preview.value.currency) : '' }).trim()
);

defineExpose({ open: () => frame.value.open() });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('DIALOG.REFUND.TITLE', { number: order.number })"
    :confirm-label="confirmLabel"
    :can-confirm="valid && !!preview"
    :build="build"
    @opened="reset"
    @done="record => emit('done', record)"
  >
    <div class="flex flex-col gap-1">
      <label v-for="mode in ['full', 'items', 'amount']" :key="mode" class="flex items-center gap-2">
        <input v-model="form.mode" type="radio" :value="mode" :data-testid="`inclamo-refund-mode-${mode}`" @change="preview = null" />
        {{ t(`DIALOG.REFUND.MODE.${mode}`) }}
      </label>
    </div>
    <label v-if="form.mode === 'amount'" class="flex flex-col gap-1">
      <span>{{ t('DIALOG.REFUND.AMOUNT', { currency: order.currency }) }}</span>
      <input
        v-model="form.amount"
        type="number"
        min="0"
        step="0.01"
        class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5"
        data-testid="inclamo-refund-amount"
        @input="preview = null"
      />
      <span v-if="aboveMaximum" class="text-n-ruby-11" data-testid="inclamo-refund-above">
        {{ t('DIALOG.REFUND.ABOVE', { amount: money(order.refundable.amount, order.refundable.currency) }) }}
      </span>
    </label>
    <div v-if="form.mode === 'items'" class="flex flex-col gap-2">
      <label v-for="(item, index) in refundableItems" :key="item.id" class="flex items-center justify-between gap-2">
        <span class="truncate">{{ item.title }}</span>
        <input
          v-model="form.quantities[item.id]"
          type="number"
          min="0"
          :max="item.refundable_quantity"
          class="w-16 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
          :data-testid="`inclamo-refund-quantity-${index}`"
          @input="preview = null"
        />
      </label>
      <label class="flex items-center gap-2"><input v-model="form.shipping" type="checkbox" @change="preview = null" />{{ t('DIALOG.REFUND.SHIPPING') }}</label>
    </div>
    <label class="flex items-center gap-2"><input v-model="form.restock" type="checkbox" data-testid="inclamo-refund-restock" @change="preview = null" />{{ t('DIALOG.REFUND.RESTOCK') }}</label>
    <label class="flex items-center gap-2"><input v-model="form.notify" type="checkbox" @change="preview = null" />{{ t('DIALOG.REFUND.NOTIFY') }}</label>
    <button
      v-if="!preview"
      type="button"
      class="self-start rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-50"
      :disabled="!valid || calculating"
      data-testid="inclamo-refund-calculate"
      @click="calculate"
    >
      {{ t('DIALOG.REFUND.CALCULATE') }}
    </button>
    <div v-if="preview" class="p-2 rounded-md bg-n-alpha-black2" data-testid="inclamo-refund-preview">
      <p class="font-medium">{{ t('DIALOG.REFUND.SUMMARY', { amount: money(preview.amount, preview.currency) }) }}</p>
      <p v-for="(destination, index) in preview.destinations" :key="index">
        {{ t('DIALOG.REFUND.GOES_TO', { amount: money(destination.amount, preview.currency), gateway: destination.gateway }) }}
      </p>
      <p v-if="preview.restocked_items">{{ t('DIALOG.REFUND.RESTOCKED', { count: preview.restocked_items }) }}</p>
      <p v-if="preview.restock_locations?.length" data-testid="inclamo-refund-location">
        {{ t('DIALOG.REFUND.RETURNED_TO', { location: preview.restock_locations.join(', ') }) }}
      </p>
      <p v-if="preview.left_out_items" class="text-n-amber-11" data-testid="inclamo-refund-left-out">
        {{ t('DIALOG.REFUND.LEFT_OUT', { scopes: (preview.missing_scopes || []).join(', ') }) }}
      </p>
      <p v-if="preview.unplaced_items" class="text-n-amber-11" data-testid="inclamo-refund-unplaced">
        {{ t('DIALOG.REFUND.UNPLACED', { count: preview.unplaced_items }) }}
      </p>
    </div>
    <p v-if="previewError" class="text-n-ruby-11">{{ previewError }}</p>
  </ActionDialog>
</template>
