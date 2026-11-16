// Stands in for Chatwoot's settings.routes.js (kept as
// settings.routes.chatwoot.js): the overlay's settings pages
// (dashboard/inclamo/settingsPages) get their routes after Chatwoot's.
import { frontendURL } from 'dashboard/helper/URLHelper';
import settingsPages from 'dashboard/inclamo/settingsPages';
import chatwoot from './settings.routes.chatwoot';
import SettingsWrapper from './SettingsWrapper.vue';

export default {
  ...chatwoot,
  routes: [
    ...chatwoot.routes,
    ...settingsPages.map(page => ({
      path: frontendURL(`accounts/:accountId/settings/${page.path}`),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: page.name,
          component: page.component,
          meta: { permissions: page.permissions },
        },
      ],
    })),
  ],
};
