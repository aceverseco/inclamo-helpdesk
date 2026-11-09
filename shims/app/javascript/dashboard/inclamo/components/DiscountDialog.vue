<script setup>
// "Discount code": the agent picks one of the presets an administrator set
// and changes nothing. The store makes the code; it goes into the reply the
// agent is writing. A preset for this customer only cannot be picked when
// the contact matches no customer.
import { ref, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import { insertIntoReply } from '../reply';
import { presetConditions } from '../inserts';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  presets: { type: Array, required: true },
  currency: { type: String, default: '' },
  customerMatched: { type: Boolean, default: false },
});
const emit = defineEmits(['done']);

const dialog = ref(null);
const chosen = ref(null);

const usable = preset => preset.audience !== 'customer' || props.customerMatched;
const chosenPreset = computed(() => props.presets.find(preset => preset.id === chosen.value && usable(preset)) || null);

const open = () => {
  chosen.value = (props.presets.find(usable) || {}).id ?? null;
  dialog.value.open();
};

const build = () => ({ action_name: 'discount', order_id: null, params: { preset_id: chosenPreset.value.id } });

const done = record => {
  if (record.outcome === 'accepted' && record.result?.code) insertIntoReply(record.result.code);
  emit('done', record);
};

defineExpose({ open });
</script>

<template>
  <ActionDialog
    ref="dialog"
    :conversation-id="conversationId"
    :title="t('INSERTS.DISCOUNT.TITLE')"
    :confirm-label="t('INSERTS.DISCOUNT.CONFIRM')"
    :not-allowed-text="t('INSERTS.DISCOUNT.NOT_ALLOWED')"
    :can-confirm="Boolean(chosenPreset)"
    :build="build"
    @done="done"
  >
    <p class="text-xs text-n-slate-11">{{ t('INSERTS.DISCOUNT.INTRO') }}</p>
    <fieldset class="flex flex-col gap-2" data-testid="inclamo-discount-presets">
      <legend class="sr-only">{{ t('INSERTS.DISCOUNT.PRESETS') }}</legend>
      <label
        v-for="preset in presets"
        :key="preset.id"
        class="flex items-start gap-2 rounded-md outline outline-1 outline-n-weak p-2"
        :class="{ 'opacity-50': !usable(preset) }"
        data-testid="inclamo-discount-preset"
        :data-preset-id="preset.id"
      >
        <input v-model="chosen" type="radio" name="inclamo-discount-preset" :value="preset.id" :disabled="!usable(preset)" class="mt-1" />
        <span class="flex flex-col">
          <span class="font-medium">{{ preset.name }}</span>
          <span class="text-xs text-n-slate-11">{{ presetConditions(preset, currency) }}</span>
          <span v-if="!usable(preset)" class="text-xs text-n-ruby-11" data-testid="inclamo-discount-no-customer">{{ t('INSERTS.DISCOUNT.CUSTOMER_NOT_FOUND') }}</span>
          <span v-else-if="preset.audience === 'customer'" class="text-xs text-n-slate-11">{{ t('INSERTS.DISCOUNT.CUSTOMER_EMAIL') }}</span>
        </span>
      </label>
    </fieldset>
  </ActionDialog>
</template>
