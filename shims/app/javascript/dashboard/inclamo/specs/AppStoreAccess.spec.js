import { mount, enableAutoUnmount } from '@vue/test-utils';
import OrdersSection from '../components/OrdersSection.vue';
import SetupPage from '../components/SetupPage.vue';
import InclamoAPI from '../api';
import { clearCommerce } from '../widgets/commerce';
import { stubs, order, agent, admin, flush } from './helpers';
enableAutoUnmount(afterEach);

// The store connection of an account the store app provisioned, as the
// Orders section and the setup page show it (capability app-store-access).

const { route } = vi.hoisted(() => ({ route: { params: { accountId: 1 }, query: { step: 'store' } } }));
vi.mock('vue-router', () => ({ useRoute: () => route, useRouter: () => ({ replace: vi.fn() }) }));
vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', () => ({ default: { template: '<div><slot name="body" /></div>' } }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../api', () => ({
  default: {
    getPanel: vi.fn(),
    recheck: vi.fn(),
    disconnect: vi.fn(),
    connect: vi.fn(),
    connectThroughApp: vi.fn(),
    getRoles: vi.fn(),
    getSetup: vi.fn(),
    reviewSetup: vi.fn(),
    completeSetup: vi.fn(),
  },
}));

const ACTIONS = ['cancel', 'refund', 'address', 'replacement', 'order_tags', 'order_note', 'customer_tags', 'customer_note', 'new_order', 'edit_items', 'discount'];
const NEEDS = { replacement: ['write_draft_orders', 'read_products'], customer_tags: ['write_customers'], customer_note: ['write_customers'], new_order: ['write_draft_orders', 'read_products'], edit_items: ['write_order_edits'], discount: ['write_discounts'] };
// The connection of the spec's scenario: the app granted only the two read
// scopes and write_orders.
const throughApp = (overrides = {}) => ({
  connected: true,
  status: 'working',
  auth_kind: 'app_key',
  managed_by_app: true,
  through_app: true,
  shop_name: 'Example Store',
  shop_domain: 'example-store.myshopify.com',
  customer_data: 'full',
  scopes: ['read_customers', 'read_orders', 'write_orders'],
  last_checked_at: '2026-11-19T10:00:00Z',
  renewed_at: '2026-11-19T10:30:00Z',
  broken_reason: null,
  actions: ACTIONS.map(name => (NEEDS[name] ? { name, available: false, reason: 'missing_scope', missing_scopes: NEEDS[name] } : { name, available: true, reason: null, missing_scopes: [] })),
  ...overrides,
});
const matched = (overrides = {}) => ({
  state: 'matched',
  viewer: admin,
  connection: throughApp(),
  customer: { id: 'gid://shopify/Customer/1', name: 'Maya Example', orders_count: 1, total_spent: { amount: '54.0', currency: 'EUR' } },
  orders: [order()],
  page: { has_more: false, cursor: null },
  marked_order: null,
  open_actions: [],
  ...overrides,
});

const show = async data => {
  clearCommerce();
  InclamoAPI.getPanel.mockResolvedValue({ data });
  const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
  await flush();
  return wrapper;
};
const has = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`).exists();
const text = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`).text();

describe('the Orders section of a store connected through the Inclamo app', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    clearCommerce();
  });

  it('shows the store, the last check and renewal, and each action with what the app lacks, with no removal', async () => {
    const wrapper = await show(matched());

    expect(text(wrapper, 'inclamo-app-connection')).toContain('Connected through the Inclamo app');
    expect(text(wrapper, 'inclamo-app-store')).toBe('Example Store · example-store.myshopify.com');
    expect(has(wrapper, 'inclamo-app-checked')).toBe(true);
    expect(has(wrapper, 'inclamo-app-renewed')).toBe(true);
    const available = wrapper.findAll('[data-testid^="inclamo-app-action-"][data-available="true"]').map(item => item.attributes('data-testid').replace('inclamo-app-action-', ''));
    expect(available).toEqual(['cancel', 'refund', 'address', 'order_tags', 'order_note']);
    expect(text(wrapper, 'inclamo-app-action-discount')).toContain('the Inclamo app does not have this permission at your store (write_discounts)');
    expect(has(wrapper, 'inclamo-manage-recheck')).toBe(true);
    expect(has(wrapper, 'inclamo-manage-remove')).toBe(false);
    expect(wrapper.html()).not.toContain('Dev Dashboard');
  });

  it('shows an agent what is connected and offers nothing to press', async () => {
    const wrapper = await show(matched({ viewer: agent }));

    expect(text(wrapper, 'inclamo-app-store')).toContain('example-store.myshopify.com');
    expect(has(wrapper, 'inclamo-app-checked')).toBe(true);
    expect(wrapper.findAll('[data-testid^="inclamo-app-action-"]')).toHaveLength(ACTIONS.length);
    expect(has(wrapper, 'inclamo-manage')).toBe(false);
    expect(has(wrapper, 'inclamo-manage-recheck')).toBe(false);
  });

  it('tells an administrator to install the app again when it was removed, offering check again and no credentials', async () => {
    const wrapper = await show({ state: 'broken', viewer: admin, connection: throughApp({ status: 'broken', broken_reason: 'app_removed' }) });

    expect(text(wrapper, 'inclamo-orders-broken-text')).toBe('The Inclamo app was removed from the store.');
    expect(text(wrapper, 'inclamo-orders-broken-hint')).toBe('Install the Inclamo app again in Shopify, then check again.');
    expect(has(wrapper, 'inclamo-reconnect')).toBe(false);
    expect(has(wrapper, 'inclamo-connect-open')).toBe(false);
    expect(wrapper.findAllComponents({ name: 'OrderCard' })).toHaveLength(0);

    InclamoAPI.recheck.mockResolvedValue({});
    InclamoAPI.getPanel.mockResolvedValue({ data: matched() });
    await wrapper.find('[data-testid="inclamo-broken-recheck"]').trigger('click');
    await flush();
    expect(InclamoAPI.recheck).toHaveBeenCalledTimes(1);
    expect(has(wrapper, 'inclamo-app-connection')).toBe(true);
  });

  it('tells an administrator to contact support on an account mismatch, and an agent to ask an administrator', async () => {
    const broken = { state: 'broken', connection: throughApp({ status: 'broken', broken_reason: 'account_mismatch' }) };

    const forAdmin = await show({ ...broken, viewer: admin });
    expect(text(forAdmin, 'inclamo-orders-broken-hint')).toBe('Contact support.');

    const forAgent = await show({ ...broken, viewer: agent });
    expect(text(forAgent, 'inclamo-orders-broken-text')).toBe('The Inclamo app does not know this account for the store.');
    expect(has(forAgent, 'inclamo-broken-recheck')).toBe(false);
    expect(forAgent.text()).toContain('Ask an administrator');
  });

  it('offers "Connect through the Inclamo app" instead of the credentials form, and shows what went wrong', async () => {
    const notConnected = { state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: true, managed_by_app: true, through_app: true } };
    const wrapper = await show(notConnected);

    expect(has(wrapper, 'inclamo-connect-open')).toBe(false);
    expect(text(wrapper, 'inclamo-orders-not-connected')).toContain('Your store connects through the Inclamo app.');

    InclamoAPI.connectThroughApp.mockRejectedValueOnce({ response: { data: { error: 'other_store' } } });
    await wrapper.find('[data-testid="inclamo-connect-app"]').trigger('click');
    await flush();
    expect(text(wrapper, 'inclamo-connect-app-error')).toBe('The Inclamo app answered for another store.');

    InclamoAPI.connectThroughApp.mockRejectedValueOnce({ response: { data: { error: 'missing_scopes', missing_scopes: ['read_orders'] } } });
    await wrapper.find('[data-testid="inclamo-connect-app"]').trigger('click');
    await flush();
    expect(text(wrapper, 'inclamo-connect-app-error')).toBe('The Inclamo app does not have this permission at your store: read_orders.');

    InclamoAPI.connectThroughApp.mockResolvedValueOnce({ data: {} });
    InclamoAPI.getPanel.mockResolvedValue({ data: matched() });
    await wrapper.find('[data-testid="inclamo-connect-app"]').trigger('click');
    await flush();
    expect(InclamoAPI.connectThroughApp).toHaveBeenCalledTimes(3);
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(true);
  });

  it('says so when the installation cannot reach the app, offering nothing to press', async () => {
    const wrapper = await show({ state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: true, managed_by_app: true, through_app: false } });

    expect(text(wrapper, 'inclamo-orders-not-connected')).toContain('Contact support');
    expect(has(wrapper, 'inclamo-connect-app')).toBe(false);
    expect(has(wrapper, 'inclamo-connect-open')).toBe(false);
  });

  it('keeps the credentials form for an account the app did not provision', async () => {
    const wrapper = await show({ state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: true, managed_by_app: false, through_app: false } });

    expect(has(wrapper, 'inclamo-connect-open')).toBe(true);
    expect(has(wrapper, 'inclamo-connect-app')).toBe(false);
  });

  it("says the store's data is temporarily unavailable with no orders and no actions, and reads again when reopened", async () => {
    const outage = { state: 'unavailable', reason: 'store_data_unavailable', viewer: admin, connection: throughApp() };
    const wrapper = await show(outage);

    expect(text(wrapper, 'inclamo-orders-store-data-unavailable')).toBe("The store's data is temporarily unavailable. It comes back by itself.");
    expect(wrapper.findAllComponents({ name: 'OrderCard' })).toHaveLength(0);
    expect(wrapper.find('[data-testid^="inclamo-action-"]').exists()).toBe(false);
    wrapper.unmount();

    InclamoAPI.getPanel.mockResolvedValue({ data: matched() });
    const reopened = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();
    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(2);
    expect(has(reopened, 'inclamo-orders-matched')).toBe(true);
  });

  it('says the app was removed with no orders and no actions, and reads again when reopened', async () => {
    const wrapper = await show({ state: 'broken', viewer: agent, connection: throughApp({ status: 'broken', broken_reason: 'app_removed' }) });

    expect(text(wrapper, 'inclamo-orders-broken-text')).toBe('The Inclamo app was removed from the store.');
    expect(wrapper.findAllComponents({ name: 'OrderCard' })).toHaveLength(0);
    expect(wrapper.find('[data-testid^="inclamo-action-"]').exists()).toBe(false);
    wrapper.unmount();

    InclamoAPI.getPanel.mockResolvedValue({ data: matched({ viewer: agent }) });
    mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();
    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(2);
  });
});

describe('the setup page of an account the Inclamo app provisioned', () => {
  const setup = overrides => ({ checks: { store: false, channels: true, staff: true, ai: true }, ready: false, complete: false, ai_connected: false, channels: [], review_digests: {}, order_actions: [], members_count: 1, store: null, ...overrides });
  const mountPage = () => mount(SetupPage, { global: { stubs: { ConnectDialog: true, StaffPermissionsEditor: true, AiPolicyEditor: true, RouterLink: { template: '<a><slot /></a>' } } } });

  beforeEach(() => vi.clearAllMocks());

  it('connects through the app, never with credentials', async () => {
    InclamoAPI.getSetup.mockResolvedValue({ data: setup({ managed_by_app: true, through_app: true }) });
    const page = mountPage();
    await flush();

    expect(page.find('[data-testid="setup-connect"]').exists()).toBe(false);
    expect(page.find('[data-testid="setup-through-app"]').text()).toBe('Your store connects through the Inclamo app.');
    InclamoAPI.connectThroughApp.mockResolvedValue({ data: {} });
    await page.find('[data-testid="setup-connect-app"]').trigger('click');
    await flush();
    expect(InclamoAPI.connectThroughApp).toHaveBeenCalledTimes(1);
  });

  it('keeps the credentials form for an account made by an operator', async () => {
    InclamoAPI.getSetup.mockResolvedValue({ data: setup({ managed_by_app: false, through_app: false }) });
    const page = mountPage();
    await flush();

    expect(page.find('[data-testid="setup-connect"]').exists()).toBe(true);
    expect(page.find('[data-testid="setup-connect-app"]').exists()).toBe(false);
  });
});
