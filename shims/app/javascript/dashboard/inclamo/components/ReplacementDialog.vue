<script setup>
import { ref, reactive, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
});
const emit = defineEmits(['done']);

const frame = ref(null);
const quantities = reactive({});

// Starts from every item of the original order; the agent can only take away.
const reset = () => {
  Object.keys(quantities).forEach(key => delete quantities[key]);
  (props.order.items || []).forEach(item => {
    quantities[item.id] = item.quantity;
  });
};
const kept = computed(() =>
  (props.order.items || [])
    .map(item => ({ line_item_id: item.id, quantity: Math.min(Math.max(Number(quantities[item.id]) || 0, 0), item.quantity) }))
    .filter(item => item.quantity > 0)
);
const build = () => ({ action_name: 'replacement', order_id: props.order.id, params: { items: kept.value } });

defineExpose({ open: () => frame.value.open() });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('DIALOG.REPLACEMENT.TITLE', { number: order.number })"
    :confirm-label="t('DIALOG.REPLACEMENT.CONFIRM')"
    :can-confirm="kept.length > 0"
    :build="build"
    @opened="reset"
    @done="record => emit('done', record)"
  >
    <p data-testid="inclamo-replacement-intro">{{ t('DIALOG.REPLACEMENT.INTRO') }}</p>
    <label v-for="item in order.items" :key="item.id" class="flex items-center justify-between gap-2">
      <span class="truncate">{{ item.title }}</span>
      <input
        v-model="quantities[item.id]"
        type="number"
        min="0"
        :max="item.quantity"
        class="w-16 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1"
        :data-testid="`inclamo-replacement-quantity-${item.id}`"
      />
    </label>
    <p v-if="kept.length === 0" class="text-n-ruby-11">{{ t('DIALOG.REPLACEMENT.NONE') }}</p>
  </ActionDialog>
</template>
