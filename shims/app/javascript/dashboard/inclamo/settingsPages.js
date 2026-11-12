// The pages the overlay adds to the account settings. Chatwoot gives every
// entry a route and a line in the sidebar's Settings group. Load the page
// only when its route opens: the settings frame itself imports the router.
import { t } from './i18n';
import { ORDER_ROLES_ROUTE, RULE_PRESETS_ROUTE, DISCOUNT_SETTINGS_ROUTE, SLA_POLICIES_ROUTE, AI_AGENT_ROUTE, SETUP_ROUTE, TEAM_QUEUES_ROUTE } from './routes';

export default [
  {
    name: SETUP_ROUTE,
    path: 'setup',
    label: () => t('SETUP.TITLE'),
    icon: 'i-lucide-list-checks',
    component: () => import('./components/SetupPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: 'inclamo_website_widget',
    path: 'website-widget',
    label: () => t('WEBSITE_WIDGET.WEBSITE_WIDGET'),
    icon: 'i-lucide-message-circle',
    component: () => import('./website-widget/WebsiteWidgetPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: 'inclamo_workspace_widgets',
    path: 'workspace-widgets',
    label: () => t('WIDGETS.ADMIN_TITLE'),
    icon: 'i-lucide-layout-dashboard',
    component: () => import('./widgets/WorkspaceWidgetsPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: ORDER_ROLES_ROUTE,
    path: 'order-actions',
    label: () => t('SETTINGS.ORDER_ROLES.MENU'),
    icon: 'i-lucide-shopping-bag',
    component: () => import('./components/OrderRolesPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: RULE_PRESETS_ROUTE,
    path: 'preset-rules',
    label: () => t('SETTINGS.RULE_PRESETS.MENU'),
    icon: 'i-lucide-list-checks',
    component: () => import('./components/RulePresetsPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: DISCOUNT_SETTINGS_ROUTE,
    path: 'discount-codes',
    label: () => t('SETTINGS.DISCOUNTS.MENU'),
    icon: 'i-lucide-ticket-percent',
    component: () => import('./components/DiscountSettingsPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: TEAM_QUEUES_ROUTE,
    path: 'team-queues',
    label: () => t('SETTINGS.TEAM_QUEUES.MENU'),
    icon: 'i-lucide-list-tree',
    component: () => import('./components/TeamQueuesPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: SLA_POLICIES_ROUTE,
    // Not settings/sla: Chatwoot's own (paid) SLA page owns that address.
    path: 'sla-policies',
    label: () => t('SETTINGS.SLA.MENU'),
    icon: 'i-lucide-timer',
    component: () => import('./components/SlaPoliciesPage.vue'),
    permissions: ['administrator'],
  },
  {
    name: AI_AGENT_ROUTE,
    path: 'ai-agent',
    label: () => t('SETTINGS.AI_AGENT.MENU'),
    icon: 'i-lucide-bot',
    component: () => import('./components/AiAgentPage.vue'),
    permissions: ['administrator'],
  },
];
