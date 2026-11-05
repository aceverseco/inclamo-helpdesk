// The sections the overlay adds to the conversation sidebar. Chatwoot's
// ContactPanel renders every entry of this list like one of its own sections.
import OrdersSection from './components/OrdersSection.vue';
import { t } from './i18n';

export default [
  {
    name: 'inclamo_orders',
    openKey: 'is_inclamo_orders_open',
    title: () => t('ORDERS.TITLE'),
    component: OrdersSection,
  },
];
