// The pages the overlay adds to the account settings. Chatwoot gives every
// entry a route and a line in the sidebar's Settings group.
import OrderRolesPage from './components/OrderRolesPage.vue';
import AiAgentPage from './components/AiAgentPage.vue';
import { t } from './i18n';
import { ORDER_ROLES_ROUTE, AI_AGENT_ROUTE } from './routes';

export default [
  {
    name: ORDER_ROLES_ROUTE,
    path: 'order-actions',
    label: () => t('SETTINGS.ORDER_ROLES.MENU'),
    icon: 'i-lucide-shopping-bag',
    component: OrderRolesPage,
    permissions: ['administrator'],
  },
  {
    name: AI_AGENT_ROUTE,
    path: 'ai-agent',
    label: () => t('SETTINGS.AI_AGENT.MENU'),
    icon: 'i-lucide-bot',
    component: AiAgentPage,
    permissions: ['administrator'],
  },
];
