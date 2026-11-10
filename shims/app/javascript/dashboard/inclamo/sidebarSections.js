// The sections the overlay adds to the conversation sidebar. Chatwoot's
// ContactPanel renders every entry of this list like one of its own sections,
// and hides one whose `visible` says no.
import OrdersSection from './components/OrdersSection.vue';
import SlaSection from './components/SlaSection.vue';
import { t } from './i18n';
import { hasTimer } from './slaTimers';

export default [
  {
    name: 'inclamo_orders',
    openKey: 'is_inclamo_orders_open',
    title: () => t('ORDERS.TITLE'),
    component: OrdersSection,
  },
  {
    name: 'inclamo_sla',
    openKey: 'is_inclamo_sla_open',
    title: () => t('SLA.TITLE'),
    component: SlaSection,
    // Only a conversation with a timer has the section.
    visible: conversationId => hasTimer(conversationId),
  },
];
