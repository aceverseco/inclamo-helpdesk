// The pages the overlay adds to the account settings. Chatwoot gives every
// entry a route and a line in the sidebar's Settings group.
import OrderRolesPage from './components/OrderRolesPage.vue';
import AiAgentPage from './components/AiAgentPage.vue';
import SlaPoliciesPage from './components/SlaPoliciesPage.vue';
import RulePresetsPage from './components/RulePresetsPage.vue';
import DiscountSettingsPage from './components/DiscountSettingsPage.vue';
import { t } from './i18n';
import { ORDER_ROLES_ROUTE, RULE_PRESETS_ROUTE, DISCOUNT_SETTINGS_ROUTE, SLA_POLICIES_ROUTE, AI_AGENT_ROUTE } from './routes';

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
    name: RULE_PRESETS_ROUTE,
    path: 'preset-rules',
    label: () => t('SETTINGS.RULE_PRESETS.MENU'),
    icon: 'i-lucide-list-checks',
    component: RulePresetsPage,
    permissions: ['administrator'],
  },
  {
    name: DISCOUNT_SETTINGS_ROUTE,
    path: 'discount-codes',
    label: () => t('SETTINGS.DISCOUNTS.MENU'),
    icon: 'i-lucide-ticket-percent',
    component: DiscountSettingsPage,
    permissions: ['administrator'],
  },
  {
    name: SLA_POLICIES_ROUTE,
    // Not settings/sla: Chatwoot's own (paid) SLA page owns that address.
    path: 'sla-policies',
    label: () => t('SETTINGS.SLA.MENU'),
    icon: 'i-lucide-timer',
    component: SlaPoliciesPage,
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
