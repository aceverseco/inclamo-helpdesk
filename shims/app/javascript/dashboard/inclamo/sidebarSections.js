// The sections the overlay adds to the conversation sidebar. The customer panel
// (workspace/CustomerSidePanel.vue) renders every entry like one of its own,
// and hides one whose `visible` says no.
import CallSection from './components/CallSection.vue';
import OrdersSection from './components/OrdersSection.vue';
import SlaSection from './components/SlaSection.vue';
import { t } from './i18n';
import { isCall } from './calls';
import { hasTimer } from './slaTimers';

export default [
  {
    name: 'inclamo_orders',
    openKey: 'is_inclamo_orders_open',
    title: () => t('ORDERS.TITLE'),
    component: OrdersSection,
  },
  {
    name: 'inclamo_call',
    openKey: 'is_inclamo_call_open',
    title: () => t('CALL.TITLE'),
    component: CallSection,
    // Only a conversation filed as a call has the section.
    visible: conversationId => isCall(conversationId),
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
