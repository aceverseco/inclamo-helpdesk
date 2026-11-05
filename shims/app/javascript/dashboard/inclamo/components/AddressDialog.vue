<script setup>
import { ref, reactive, computed } from 'vue';
import ActionDialog from './ActionDialog.vue';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  order: { type: Object, required: true },
});
const emit = defineEmits(['done']);

const FIELDS = [
  ['first_name', 'FIRST_NAME'],
  ['last_name', 'LAST_NAME'],
  ['company', 'COMPANY'],
  ['address1', 'ADDRESS1'],
  ['address2', 'ADDRESS2'],
  ['city', 'CITY'],
  ['province_code', 'PROVINCE'],
  ['zip', 'ZIP'],
  ['country_code', 'COUNTRY'],
  ['phone', 'PHONE'],
];
const frame = ref(null);
const form = reactive({});

// The form starts from the current address.
const reset = () => {
  const current = props.order.shipping_address || {};
  const [first, ...rest] = (current.name || '').split(' ');
  Object.assign(form, {
    first_name: first || '',
    last_name: rest.join(' '),
    company: '',
    address1: current.address1 || '',
    address2: current.address2 || '',
    city: current.city || '',
    province_code: current.province_code || '',
    zip: current.zip || '',
    country_code: current.country_code || '',
    phone: current.phone || '',
  });
};
const valid = computed(() => !!form.address1 && !!form.city && !!form.country_code);
const build = () => ({ action_name: 'address', order_id: props.order.id, address: { ...form } });

defineExpose({ open: () => frame.value.open() });
</script>

<template>
  <ActionDialog
    ref="frame"
    :conversation-id="conversationId"
    :title="t('DIALOG.ADDRESS.TITLE', { number: order.number })"
    :confirm-label="t('DIALOG.ADDRESS.CONFIRM')"
    :can-confirm="valid"
    :build="build"
    @opened="reset"
    @done="record => emit('done', record)"
  >
    <div class="grid grid-cols-2 gap-2">
      <label v-for="[field, label] in FIELDS" :key="field" class="flex flex-col gap-1" :class="{ 'col-span-2': field === 'address1' || field === 'address2' }">
        <span>{{ t(`DIALOG.ADDRESS.${label}`) }}</span>
        <input v-model="form[field]" type="text" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" :data-testid="`inclamo-address-${field}`" />
      </label>
    </div>
  </ActionDialog>
</template>
