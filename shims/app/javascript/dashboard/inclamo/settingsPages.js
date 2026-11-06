// The pages the overlay adds to the account settings. Chatwoot gives every
// entry a route and a line in the sidebar's Settings group.
import OrderRolesPage from './components/OrderRolesPage.vue';
import { t } from './i18n';
import { ORDER_ROLES_ROUTE } from './routes';

export default [
  {
    name: ORDER_ROLES_ROUTE,
    path: 'order-actions',
    label: () => t('SETTINGS.ORDER_ROLES.MENU'),
    icon: 'i-lucide-shopping-bag',
    component: OrderRolesPage,
    permissions: ['administrator'],
  },
];
