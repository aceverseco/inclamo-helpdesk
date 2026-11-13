import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { mount } from '@vue/test-utils';
import { useFacebookPageConnect } from 'dashboard/composables/useFacebookPageConnect';
import Reauthorize from 'dashboard/routes/dashboard/settings/inbox/facebook/Reauthorize.vue';
import { flush } from './helpers';

// The connect composable and the reauthorize screen are Chatwoot's, changed by
// patches/0021-meta-page-connect-instagram-scopes.patch (the tests run from the
// assembled Chatwoot root). Meta's SDK is replaced by a stub that records what
// FB.login is asked for; no request leaves the test.
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => ({ value: 1 }) }));
vi.mock('dashboard/api/channels', () => ({
  default: { fetchFacebookPages: async () => ({ data: { data: { page_details: [], user_access_token: 'long-token' } } }) },
}));
vi.mock('dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils', () => ({ setupFacebookSdk: async () => {} }));
vi.mock('dashboard/helper/DOMHelpers', () => ({ loadScript: async () => {} }));
vi.mock('dashboard/composables', () => ({ useAlert: () => {} }));
vi.mock('@sentry/vue', () => ({ captureException: () => {} }));

const PAGE_AND_INSTAGRAM = 'pages_manage_metadata,business_management,pages_messaging,pages_show_list,pages_read_engagement,instagram_basic,instagram_manage_messages';

const requestedScope = () => window.FB.login.mock.calls[0][1].scope;

const connectScope = async () => {
  await useFacebookPageConnect().loginAndFetchPages();
  return requestedScope();
};

const reauthorizeScope = async inbox => {
  const wrapper = mount(Reauthorize, {
    props: { inbox },
    global: {
      mocks: { $t: key => key, $store: { dispatch: async () => {} } },
      stubs: { InboxReconnectionRequired: { name: 'InboxReconnectionRequired', emits: ['reauthorize'], template: '<button data-testid="reconnect" @click="$emit(\'reauthorize\')" />' } },
    },
  });
  await wrapper.find('[data-testid="reconnect"]').trigger('click');
  await flush();
  return requestedScope();
};

describe('Meta permissions asked for a Facebook Page', () => {
  beforeEach(() => {
    window.chatwootConfig = { fbAppId: 'fb-app', fbApiVersion: 'v22.0' };
    window.FB = {
      init: vi.fn(),
      AppEvents: { logPageView: vi.fn() },
      login: vi.fn(callback => callback({ status: 'connected', authResponse: { accessToken: 'user-token' } })),
    };
  });

  it('connecting a Page asks for the Page and the Instagram messaging permissions in one dialog', async () => {
    const scope = await connectScope();

    expect(window.FB.login).toHaveBeenCalledTimes(1);
    expect(scope).toBe(PAGE_AND_INSTAGRAM);
    expect(scope.split(',')).toEqual(expect.arrayContaining(['instagram_basic', 'instagram_manage_messages', 'business_management']));
  });

  it('the inbox settings and the onboarding form both connect through that one flow', () => {
    // Both screens need the store and the router to mount, so the seam is
    // checked in their source: they take the login from the composable and
    // never call Meta's SDK login themselves.
    ['app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Facebook.vue', 'app/javascript/dashboard/routes/dashboard/onboarding/inbox-setup/InboxFacebookForm.vue'].forEach(file => {
      const source = readFileSync(resolve(process.cwd(), file), 'utf8');

      expect(source).toContain("from 'dashboard/composables/useFacebookPageConnect'");
      expect(source).toMatch(/loginAndFetchPages\s*\}?\s*=\s*useFacebookPageConnect\(\)/);
      expect(source).not.toMatch(/FB\.login\(/);
      expect(source).not.toContain('buildFacebookLoginScopes');
    });
  });

  it('reauthorizing asks for the same permissions as connecting, whether or not the inbox has an Instagram account', async () => {
    const connect = await connectScope();
    window.FB.login.mockClear();
    const withInstagram = await reauthorizeScope({ id: 7, instagram_id: '17841400000000000' });
    window.FB.login.mockClear();
    const withoutInstagram = await reauthorizeScope({ id: 8, instagram_id: null });

    expect(withInstagram).toBe(connect);
    expect(withoutInstagram).toBe(connect);
    expect(connect).toBe(PAGE_AND_INSTAGRAM);
  });
});
