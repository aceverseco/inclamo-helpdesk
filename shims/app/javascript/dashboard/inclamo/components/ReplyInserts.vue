<script setup>
// The two controls at the top of the Orders section that put something into
// the reply: a product of the store, and a new discount code from a preset.
// Shown also when the contact matches no customer.
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import ProductInsertDialog from './ProductInsertDialog.vue';
import DiscountDialog from './DiscountDialog.vue';
import { inboxTakesLinks } from '../channels';
import { DISCOUNT_SETTINGS_ROUTE } from '../routes';
import { t } from '../i18n';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  viewer: { type: Object, required: true },
  connection: { type: Object, required: true },
  customerMatched: { type: Boolean, default: false },
});
const emit = defineEmits(['changed']);

const store = useStore();
const productDialog = ref(null);
const discountDialog = ref(null);

// The inbox of the conversation open in the dashboard, for whether its reply editor keeps links.
const links = computed(() => {
  const getters = store?.getters;
  const chat = getters?.getSelectedChat;
  const inbox = chat?.inbox_id ? getters['inboxes/getInbox'](chat.inbox_id) : null;
  return inboxTakesLinks(inbox);
});

const canInsertProduct = computed(() => Boolean(props.connection.products_readable));

const presets = computed(() => props.viewer.discount_presets || []);
const discountScope = computed(() => (props.connection.actions || []).find(entry => entry.name === 'discount'));
const mayGive = computed(() => Boolean(props.viewer.can_give_discounts));
const canGiveDiscount = computed(() => mayGive.value && Boolean(discountScope.value?.available) && presets.value.length > 0);
// Why "Discount code" is not offered, for those who could otherwise give one.
const missingScope = computed(() => {
  const scope = discountScope.value;
  if (!mayGive.value || !scope || scope.available) return '';
  return t(`ORDER.WHY_NOT.${scope.reason}`, { scopes: (scope.missing_scopes || []).join(', ') });
});
const noPresets = computed(() => props.viewer.administrator && Boolean(discountScope.value?.available) && presets.value.length === 0);
</script>

<template>
  <div v-if="canInsertProduct || canGiveDiscount || missingScope || noPresets" class="mb-2 flex flex-col gap-1" data-testid="inclamo-reply-inserts">
    <div class="flex flex-wrap gap-2">
      <button v-if="canInsertProduct" type="button" class="rounded-md border border-n-weak px-3 py-1 text-xs" data-testid="inclamo-insert-product-open" @click="productDialog.open()">
        {{ t('INSERTS.PRODUCT.OPEN') }}
      </button>
      <button v-if="canGiveDiscount" type="button" class="rounded-md border border-n-weak px-3 py-1 text-xs" data-testid="inclamo-discount-open" @click="discountDialog.open()">
        {{ t('INSERTS.DISCOUNT.OPEN') }}
      </button>
    </div>
    <p v-if="missingScope" class="text-xs text-n-slate-11" data-testid="inclamo-discount-unavailable">{{ t('INSERTS.DISCOUNT.UNAVAILABLE', { reason: missingScope }) }}</p>
    <p v-else-if="noPresets" class="text-xs text-n-slate-11" data-testid="inclamo-discount-no-presets">
      {{ t('INSERTS.DISCOUNT.NO_PRESETS') }}
      <router-link :to="{ name: DISCOUNT_SETTINGS_ROUTE }" class="text-n-blue-text" data-testid="inclamo-discount-settings-link">{{ t('INSERTS.DISCOUNT.SETTINGS_LINK') }}</router-link>
    </p>
    <ProductInsertDialog v-if="canInsertProduct" ref="productDialog" :conversation-id="conversationId" :links="links" />
    <DiscountDialog
      v-if="canGiveDiscount"
      ref="discountDialog"
      :conversation-id="conversationId"
      :presets="presets"
      :currency="connection.shop_currency"
      :customer-matched="customerMatched"
      @done="emit('changed')"
    />
  </div>
</template>
