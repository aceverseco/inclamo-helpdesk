<script setup>
import { useCommerce } from './commerce';
import { money } from '../format';
import { t } from '../i18n';
const props = defineProps({ context: { type: Object, required: true } });
const { entry, panel, load } = useCommerce(() => props.context);
</script>
<template>
  <div v-if="panel?.state === 'matched'" class="customer-stats" data-testid="inclamo-customer-summary">
    <div><strong>{{ panel.customer.orders_count }}</strong><span>{{ t('WORKSPACE.ORDER_COUNT') }}</span></div>
    <div v-if="panel.customer.total_spent"><strong>{{ money(panel.customer.total_spent.amount, panel.customer.total_spent.currency) }}</strong><span>{{ t('WORKSPACE.SPENT') }}</span></div>
  </div>
  <p v-else-if="entry.loading" class="p-3 text-sm">{{ t('ORDERS.LOADING') }}</p>
  <div v-else class="p-3 text-sm">
    <p>{{ t('WIDGETS.STATISTICS_UNAVAILABLE') }}</p>
    <button v-if="entry.failed" type="button" class="underline" @click="load">{{ t('ORDERS.RETRY') }}</button>
  </div>
</template>
