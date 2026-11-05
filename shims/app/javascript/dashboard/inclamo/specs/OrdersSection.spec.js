import { mount } from '@vue/test-utils';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { stubs, order, connection, agent, admin, allowedAgent, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    getPanel: vi.fn(),
    lookup: vi.fn(),
    chooseCustomer: vi.fn(),
    forgetCustomer: vi.fn(),
    markOrder: vi.fn(),
    clearOrder: vi.fn(),
    recheck: vi.fn(),
    disconnect: vi.fn(),
    getRoles: vi.fn(),
    connect: vi.fn(),
  },
}));

const matched = (overrides = {}) => ({
  state: 'matched',
  viewer: allowedAgent,
  connection: connection(),
  customer: { id: 'gid://shopify/Customer/1', name: 'Maya Example', orders_count: 3, total_spent: { amount: '120.0', currency: 'EUR' } },
  orders: [order(), order({ id: 'gid://shopify/Order/2', number: '#1002' })],
  page: { has_more: false, cursor: null },
  marked_order: null,
  open_actions: [],
  ...overrides,
});

const show = async data => {
  InclamoAPI.getPanel.mockResolvedValue({ data });
  const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
  await flush();
  return wrapper;
};
const has = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`).exists();

describe('OrdersSection', () => {
  it('tells an agent that no store is connected, without a connect action', async () => {
    const wrapper = await show({ state: 'not_connected', viewer: agent, connection: { connected: false, encryption_configured: true } });

    expect(wrapper.text()).toContain('An administrator can connect one');
    expect(has(wrapper, 'inclamo-connect-open')).toBe(false);
    expect(has(wrapper, 'inclamo-manage')).toBe(false);
  });

  it('offers an administrator to connect the store', async () => {
    const wrapper = await show({ state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: true } });

    expect(has(wrapper, 'inclamo-connect-open')).toBe(true);
    await wrapper.find('[data-testid="inclamo-connect-open"]').trigger('click');
    expect(has(wrapper, 'inclamo-connect-dialog')).toBe(true);
  });

  it('says encryption must be configured first, and offers no connect action', async () => {
    const wrapper = await show({ state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: false } });

    expect(wrapper.text()).toContain('Encryption must be configured');
    expect(has(wrapper, 'inclamo-connect-open')).toBe(false);
  });

  it('shows a broken connection with the reconnect action for administrators only', async () => {
    const broken = { state: 'broken', connection: connection({ status: 'broken' }) };
    const forAgent = await show({ ...broken, viewer: agent });
    expect(forAgent.text()).toContain('needs attention');
    expect(has(forAgent, 'inclamo-reconnect')).toBe(false);
    expect(has(forAgent, 'inclamo-orders-matched')).toBe(false);

    const forAdmin = await show({ ...broken, viewer: admin });
    expect(has(forAdmin, 'inclamo-reconnect')).toBe(true);
  });

  it('says the store did not answer and retries on demand, showing no stale orders', async () => {
    const wrapper = await show({ state: 'unavailable', reason: 'timeout', viewer: agent, connection: connection() });
    expect(has(wrapper, 'inclamo-orders-unavailable')).toBe(true);
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(false);

    InclamoAPI.getPanel.mockResolvedValue({ data: matched() });
    await wrapper.find('[data-testid="inclamo-orders-retry"]').trigger('click');
    await flush();

    expect(InclamoAPI.getPanel).toHaveBeenCalledTimes(2);
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(true);
  });

  it('keeps the orders on screen while it refreshes after an action', async () => {
    const wrapper = await show(matched());
    let finish;
    InclamoAPI.getPanel.mockReturnValue(new Promise(resolve => { finish = resolve; }));

    wrapper.findComponent({ name: 'OrderCard' }).vm.$emit('changed', {});
    await flush();

    expect(has(wrapper, 'inclamo-orders-loading')).toBe(false);
    expect(has(wrapper, 'inclamo-order-#1001')).toBe(true);
    finish({ data: matched({ orders: [order({ financial_status: 'REFUNDED' })] }) });
    await flush();
    expect(wrapper.find('[data-testid="inclamo-order-statuses"]').text()).toContain('Refunded');
  });

  it('shows the same message when the request itself fails', async () => {
    InclamoAPI.getPanel.mockRejectedValue(new Error('network'));
    const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();

    expect(has(wrapper, 'inclamo-orders-unavailable')).toBe(true);
  });

  it('works by order number only in the limited mode, and says why', async () => {
    const wrapper = await show({ state: 'limited', viewer: admin, connection: connection({ customer_data: 'limited' }), candidates: [] });

    expect(has(wrapper, 'inclamo-orders-limited')).toBe(true);
    expect(wrapper.text()).toContain('custom distribution');
    expect(has(wrapper, 'inclamo-lookup')).toBe(true);
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(false);
  });

  it('offers only the lookup for a contact without email and phone, and when nobody matches', async () => {
    const without = await show({ state: 'no_identifier', viewer: agent, connection: connection(), candidates: [] });
    expect(has(without, 'inclamo-orders-no-identifier')).toBe(true);
    expect(has(without, 'inclamo-lookup')).toBe(true);

    const nobody = await show({ state: 'none', viewer: agent, connection: connection(), candidates: [] });
    expect(has(nobody, 'inclamo-orders-none')).toBe(true);
    expect(has(nobody, 'inclamo-lookup')).toBe(true);
  });

  it('lists the candidates without orders when the match is not unique, and takes the agent\'s choice', async () => {
    const candidates = [
      { id: 'gid://shopify/Customer/1', name: 'Maya Example', email: 'maya@example.com', orders_count: 3 },
      { id: 'gid://shopify/Customer/2', name: 'Mia Example', email: 'mia@example.com', orders_count: 1 },
    ];
    const wrapper = await show({ state: 'ambiguous', viewer: agent, connection: connection(), candidates });

    expect(wrapper.findAll('[data-testid="inclamo-candidate"]')).toHaveLength(2);
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(false);

    InclamoAPI.chooseCustomer.mockResolvedValue({ data: matched() });
    await wrapper.findAll('[data-testid="inclamo-candidate-choose"]')[1].trigger('click');
    await flush();

    expect(InclamoAPI.chooseCustomer).toHaveBeenCalledWith(7, 'gid://shopify/Customer/2');
    expect(has(wrapper, 'inclamo-orders-matched')).toBe(true);
  });

  it('shows the matched customer with their orders and loads more', async () => {
    const wrapper = await show(matched({ page: { has_more: true, cursor: 'next' } }));

    expect(wrapper.find('[data-testid="inclamo-customer-name"]').text()).toBe('Maya Example');
    expect(wrapper.find('[data-testid="inclamo-customer-summary"]').text()).toContain('3 orders');
    expect(has(wrapper, 'inclamo-order-#1001')).toBe(true);
    expect(has(wrapper, 'inclamo-order-#1002')).toBe(true);

    InclamoAPI.getPanel.mockResolvedValue({ data: matched({ orders: [order({ id: 'gid://shopify/Order/3', number: '#1000' })], page: { has_more: false, cursor: null } }) });
    await wrapper.find('[data-testid="inclamo-orders-more"]').trigger('click');
    await flush();

    expect(InclamoAPI.getPanel).toHaveBeenLastCalledWith(7, 'next');
    expect(has(wrapper, 'inclamo-order-#1000')).toBe(true);
    expect(has(wrapper, 'inclamo-order-#1001')).toBe(true);
    expect(has(wrapper, 'inclamo-orders-more')).toBe(false);
  });

  it('finds an order by its number and can keep its customer for the contact', async () => {
    const wrapper = await show({ state: 'none', viewer: agent, connection: connection(), candidates: [] });
    InclamoAPI.lookup.mockResolvedValue({ data: { found: true, order: order({ number: '#1042' }) } });

    await wrapper.find('[data-testid="inclamo-lookup-number"]').setValue('#1042');
    await wrapper.find('[data-testid="inclamo-lookup"]').trigger('submit');
    await flush();

    expect(InclamoAPI.lookup).toHaveBeenCalledWith(7, '#1042');
    expect(has(wrapper, 'inclamo-order-#1042')).toBe(true);

    InclamoAPI.chooseCustomer.mockResolvedValue({ data: matched() });
    await wrapper.find('[data-testid="inclamo-lookup-keep"]').trigger('click');
    await flush();
    expect(InclamoAPI.chooseCustomer).toHaveBeenCalledWith(7, 'gid://shopify/Customer/1');
  });

  it('says so when no order has the number', async () => {
    const wrapper = await show({ state: 'none', viewer: agent, connection: connection(), candidates: [] });
    InclamoAPI.lookup.mockResolvedValue({ data: { found: false } });

    await wrapper.find('[data-testid="inclamo-lookup-number"]').setValue('999999');
    await wrapper.find('[data-testid="inclamo-lookup"]').trigger('submit');
    await flush();

    expect(has(wrapper, 'inclamo-lookup-not-found')).toBe(true);
  });

  it('shows which order the conversation is about, and marks another on request', async () => {
    const wrapper = await show(matched({ marked_order: order() }));
    expect(wrapper.find('[data-testid="inclamo-order-#1001"]').find('[data-testid="inclamo-order-marked"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-order-#1002"]').find('[data-testid="inclamo-order-marked"]').exists()).toBe(false);
  });

  it('shows the store menu to administrators only, with removal behind a confirmation', async () => {
    expect(has(await show(matched({ viewer: allowedAgent })), 'inclamo-manage')).toBe(false);

    const wrapper = await show(matched({ viewer: admin }));
    expect(has(wrapper, 'inclamo-manage-recheck')).toBe(true);
    expect(has(wrapper, 'inclamo-manage-roles')).toBe(true);

    await wrapper.find('[data-testid="inclamo-manage-remove"]').trigger('click');
    expect(InclamoAPI.disconnect).not.toHaveBeenCalled();
    InclamoAPI.disconnect.mockResolvedValue({});
    InclamoAPI.getPanel.mockResolvedValue({ data: { state: 'not_connected', viewer: admin, connection: { connected: false, encryption_configured: true } } });
    await wrapper.find('[data-testid="inclamo-manage-remove-confirm"]').trigger('click');
    await flush();

    expect(InclamoAPI.disconnect).toHaveBeenCalledTimes(1);
    expect(has(wrapper, 'inclamo-orders-not-connected')).toBe(true);
  });
});
