import { mount } from '@vue/test-utils';
import ReplyInserts from '../components/ReplyInserts.vue';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { insertIntoReply } from '../reply';
import { stubs, connection, agent, admin, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    searchProducts: vi.fn(),
    performAction: vi.fn(),
    getPanel: vi.fn(),
  },
}));
vi.mock('../reply', () => ({ insertIntoReply: vi.fn() }));

// The dashboard's store, reduced to the open conversation and its inbox.
const dashboard = { channelType: 'Channel::WebWidget' };
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      getSelectedChat: { id: 7, inbox_id: 3 },
      'inboxes/getInbox': () => ({ id: 3, channel_type: dashboard.channelType }),
    },
  }),
}));

const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const findAll = (wrapper, id) => wrapper.findAll(`[data-testid="${id}"]`);

const typeAndWait = async (wrapper, text) => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  await find(wrapper, 'inclamo-product-query').setValue(text);
  await vi.advanceTimersByTimeAsync(350);
  vi.useRealTimers();
  await flush();
};

const price = amount => ({ amount, currency: 'UAH' });
const variant = (id, overrides = {}) => ({ id: `gid://shopify/ProductVariant/${id}`, title: null, sku: null, price: price('120.00'), available_for_sale: true, ...overrides });
const mug = { id: 'gid://shopify/Product/1', title: 'Blue Mug', image_url: null, online_store_url: 'https://shop.example.com/products/blue-mug', variants: [variant(11, { sku: 'MUG-1' })] };
const hidden = { id: 'gid://shopify/Product/2', title: 'Hidden Board', image_url: null, online_store_url: null, variants: [variant(21, { price: price('699.95') })] };
const found = products => ({ data: { products, page: { has_more: false, cursor: null } } });

const sorry = { id: 1, name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer' };
const thanks = { id: 2, name: 'Thanks', kind: 'amount', value: '5', expires_in_days: null, usage_limit: 3, audience: 'anyone' };
const giver = (overrides = {}) => ({ ...agent, can_give_discounts: true, discount_presets: [sorry, thanks], ...overrides });
const discountScope = (available = true) => ({ name: 'discount', available, reason: available ? null : 'missing_scope', missing_scopes: available ? [] : ['write_discounts'] });
const store = (overrides = {}) => connection({ shop_currency: 'UAH', products_readable: true, actions: [discountScope()], ...overrides });

const show = (props = {}) =>
  mount(ReplyInserts, { props: { conversationId: 7, viewer: giver(), connection: store(), customerMatched: true, ...props }, global: { stubs } });

beforeEach(() => {
  vi.clearAllMocks();
  dashboard.channelType = 'Channel::WebWidget';
});

describe('the controls', () => {
  it('offers "Insert product" to any agent and "Discount code" only with the right', () => {
    const plain = show({ viewer: { ...agent, can_act_on_orders: true, can_give_discounts: false, discount_presets: [] } });
    expect(find(plain, 'inclamo-insert-product-open').exists()).toBe(true);
    expect(find(plain, 'inclamo-discount-open').exists()).toBe(false);
    expect(find(plain, 'inclamo-discount-unavailable').exists()).toBe(false);

    const allowed = show();
    expect(find(allowed, 'inclamo-insert-product-open').exists()).toBe(true);
    expect(find(allowed, 'inclamo-discount-open').exists()).toBe(true);
  });

  it('offers both also when the contact matches no customer', () => {
    const wrapper = show({ customerMatched: false });

    expect(find(wrapper, 'inclamo-insert-product-open').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-discount-open').exists()).toBe(true);
  });

  it('offers no "Insert product" when the app cannot read products', () => {
    expect(find(show({ connection: store({ products_readable: false }) }), 'inclamo-insert-product-open').exists()).toBe(false);
  });

  it('names write_discounts instead of offering "Discount code" when the app lacks it', () => {
    const wrapper = show({ viewer: { ...admin, can_give_discounts: true, discount_presets: [sorry] }, connection: store({ actions: [discountScope(false)] }) });

    expect(find(wrapper, 'inclamo-discount-open').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-discount-unavailable').text()).toContain('write_discounts');
  });

  it('points an administrator to the settings page when there is no preset, and says nothing to an agent', () => {
    const forAdmin = show({ viewer: { ...admin, can_give_discounts: true, discount_presets: [] } });
    expect(find(forAdmin, 'inclamo-discount-open').exists()).toBe(false);
    expect(find(forAdmin, 'inclamo-discount-no-presets').exists()).toBe(true);
    expect(find(forAdmin, 'inclamo-discount-settings-link').attributes('data-route')).toBe('inclamo_discount_codes');

    const forAgent = show({ viewer: giver({ discount_presets: [] }) });
    expect(find(forAgent, 'inclamo-discount-open').exists()).toBe(false);
    expect(find(forAgent, 'inclamo-discount-no-presets').exists()).toBe(false);
  });

  it('sits at the top of the Orders section when the contact matches no customer', async () => {
    InclamoAPI.getPanel.mockResolvedValue({ data: { state: 'none', viewer: giver(), connection: store(), open_actions: [] } });
    const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();

    expect(find(wrapper, 'inclamo-orders-none').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-insert-product-open').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-discount-open').exists()).toBe(true);
  });
});

describe('Insert product', () => {
  const pick = async (wrapper, products, text = 'mug') => {
    InclamoAPI.searchProducts.mockResolvedValue(found(products));
    await find(wrapper, 'inclamo-insert-product-open').trigger('click');
    await typeAndWait(wrapper, text);
  };

  it('puts the title as a link and the price into the reply of an inbox that keeps links', async () => {
    const wrapper = show();
    await pick(wrapper, [mug]);

    await find(wrapper, 'inclamo-product-variant').trigger('click');

    expect(insertIntoReply).toHaveBeenCalledTimes(1);
    expect(insertIntoReply.mock.calls[0][0]).toMatch(/^\[Blue Mug\]\(https:\/\/shop\.example\.com\/products\/blue-mug\), .*120/);
    expect(find(wrapper, 'inclamo-insert-product-dialog').exists()).toBe(false);
  });

  it('puts "Title, price: URL" into the reply of a plain-text inbox', async () => {
    dashboard.channelType = 'Channel::Api';
    const wrapper = show();
    await pick(wrapper, [mug]);

    await find(wrapper, 'inclamo-product-variant').trigger('click');

    expect(insertIntoReply.mock.calls[0][0]).toMatch(/^Blue Mug, .*120.*: https:\/\/shop\.example\.com\/products\/blue-mug$/);
  });

  it('marks a product that is not in the online store and inserts it without a link', async () => {
    const wrapper = show();
    await pick(wrapper, [hidden], 'board');

    expect(find(wrapper, 'inclamo-product-no-link').exists()).toBe(true);
    await find(wrapper, 'inclamo-product-variant').trigger('click');

    expect(insertIntoReply.mock.calls[0][0]).toMatch(/^Hidden Board, .*699/);
    expect(insertIntoReply.mock.calls[0][0]).not.toContain('http');
    expect(insertIntoReply.mock.calls[0][0]).not.toContain('[');
  });

  it('says when nothing is found and inserts nothing', async () => {
    const wrapper = show();
    await pick(wrapper, [], 'zzqx');

    expect(find(wrapper, 'inclamo-product-none').exists()).toBe(true);
    expect(insertIntoReply).not.toHaveBeenCalled();
  });
});

describe('Discount code', () => {
  const open = async (props = {}) => {
    const wrapper = show(props);
    await find(wrapper, 'inclamo-discount-open').trigger('click');
    return wrapper;
  };
  const confirm = async wrapper => {
    await find(wrapper, 'dialog-confirm').trigger('click');
    await flush();
  };

  it('lists the presets with their conditions and offers no field for the text of the code', async () => {
    const wrapper = await open();

    const presets = findAll(wrapper, 'inclamo-discount-preset');
    expect(presets.map(preset => preset.text())).toEqual([
      expect.stringContaining('Sorry'),
      expect.stringContaining('Thanks'),
    ]);
    expect(presets[0].text()).toContain('10% off the order · expires in 30 days · usable once · this customer only');
    expect(presets[1].text()).toContain('never expires · usable 3 times · anyone, once per buyer');
    expect(wrapper.find('[data-testid="inclamo-action-dialog"] input[type="text"]').exists()).toBe(false);
  });

  it('creates the code from the chosen preset and puts it into the reply', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'accepted', action: 'discount', result: { code: 'THANKS-7KQ2M9XA', discount_id: 'gid://shopify/DiscountCodeNode/1' } } });
    const wrapper = await open();

    await findAll(wrapper, 'inclamo-discount-preset')[1].find('input').setValue(true);
    await confirm(wrapper);

    expect(InclamoAPI.performAction).toHaveBeenCalledWith(7, expect.objectContaining({ action_name: 'discount', order_id: null, params: { preset_id: 2 }, action_id: expect.any(String) }));
    expect(insertIntoReply).toHaveBeenCalledWith('THANKS-7KQ2M9XA');
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('shows a preset for this customer as unavailable when the customer was not found, and picks one for anyone', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'accepted', action: 'discount', result: { code: 'THANKS-ABCDEFGH' } } });
    const wrapper = await open({ customerMatched: false });

    const [forCustomer] = findAll(wrapper, 'inclamo-discount-preset');
    expect(forCustomer.find('input').attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'inclamo-discount-no-customer').exists()).toBe(true);
    await confirm(wrapper);

    expect(InclamoAPI.performAction.mock.calls[0][1].params).toEqual({ preset_id: 2 });
  });

  it('shows the store reason when it refuses the code, and inserts nothing', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'refused', refusal: 'store_refused', store_message: 'Code must be unique. Please try a different code.', result: {} } });
    const wrapper = await open();

    await confirm(wrapper);

    expect(find(wrapper, 'inclamo-action-message').text()).toContain('Code must be unique');
    expect(insertIntoReply).not.toHaveBeenCalled();
  });

  it('says that giving discounts is not allowed when the right was taken meanwhile', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'refused', refusal: 'not_allowed', result: {} } });
    const wrapper = await open();

    await confirm(wrapper);

    expect(find(wrapper, 'inclamo-action-message').text()).toBe('An administrator has not allowed you to give discounts.');
  });
});
