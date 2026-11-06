import { mount } from '@vue/test-utils';
import ProductSearch from '../components/ProductSearch.vue';
import NewOrderDialog from '../components/NewOrderDialog.vue';
import OrderCard from '../components/OrderCard.vue';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { insertIntoReply } from '../reply';
import { stubs, order, connection, agent, admin, allowedAgent, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    searchProducts: vi.fn(),
    newOrderPreview: vi.fn(),
    newOrderPrefill: vi.fn(),
    performAction: vi.fn(),
    getPanel: vi.fn(),
  },
}));
vi.mock('../reply', () => ({ insertIntoReply: vi.fn() }));

const money = amount => ({ amount, currency: 'UAH' });
const variant = (id, overrides = {}) => ({ id: `gid://shopify/ProductVariant/${id}`, title: null, sku: null, price: money('120.00'), available_for_sale: true, ...overrides });
const product = (id, title, variants) => ({ id: `gid://shopify/Product/${id}`, title, image_url: null, variants });
const mug = product(1, 'Blue Mug', [variant(11, { sku: 'MUG-1' })]);
const board = product(2, 'Snowboard', [variant(21, { title: 'Ice', price: money('699.95') }), variant(22, { title: 'Dawn', price: money('699.95'), available_for_sale: false })]);
const found = (products, page = { has_more: false, cursor: null }) => ({ data: { products, page } });
const customer = { id: 'gid://shopify/Customer/1', name: 'Maya Example', email: 'maya.example@example.com', phone: null };
const summary = {
  currency: 'UAH',
  taxes_included: true,
  lines: [{ variant_id: 'gid://shopify/ProductVariant/11', title: 'Blue Mug', quantity: 1, unit_price: money('120.00'), total: money('120.00') }],
  subtotal: money('120.00'),
  discount: money('12.00'),
  shipping: money('5.00'),
  tax: money('0.0'),
  total: money('113.00'),
  warnings: [],
};
const accepted = (result = {}) => ({ data: { outcome: 'accepted', action: 'new_order', result: { delivery: 'email', invoice_url: 'https://shop.example.com/1/invoices/abc', ...result } } });

const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const findAll = (wrapper, id) => wrapper.findAll(`[data-testid="${id}"]`);

// Only the timers are faked: Vue drops an event older than the handler it reaches.
const typeAndWait = async (wrapper, text) => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  await find(wrapper, 'inclamo-product-query').setValue(text);
  await vi.advanceTimersByTimeAsync(350);
  vi.useRealTimers();
  await flush();
};

beforeEach(() => vi.clearAllMocks());

describe('ProductSearch', () => {
  const show = (props = {}) => mount(ProductSearch, { props: { conversationId: 7, ...props }, global: { stubs } });

  it('shows the products with their variants, SKU and price, and emits the chosen one', async () => {
    InclamoAPI.searchProducts.mockResolvedValue(found([mug, board]));
    const wrapper = show();

    await typeAndWait(wrapper, 'mug');

    expect(InclamoAPI.searchProducts).toHaveBeenCalledWith(7, { query: 'mug', after: undefined });
    expect(findAll(wrapper, 'inclamo-product')).toHaveLength(2);
    const first = findAll(wrapper, 'inclamo-product-variant')[0];
    expect(first.text()).toContain('Blue Mug');
    expect(first.text()).toContain('MUG-1');
    await first.trigger('click');
    expect(wrapper.emitted('select')[0][0]).toEqual({ product: mug, variant: mug.variants[0] });
  });

  it('says when nothing is found', async () => {
    InclamoAPI.searchProducts.mockResolvedValue(found([]));
    const wrapper = show();

    await typeAndWait(wrapper, 'zzqx');

    expect(find(wrapper, 'inclamo-product-none').exists()).toBe(true);
  });

  it('shows a variant the store cannot sell as not available, and does not let it be chosen', async () => {
    InclamoAPI.searchProducts.mockResolvedValue(found([board]));
    const wrapper = show();

    await typeAndWait(wrapper, 'snow');

    const dawn = findAll(wrapper, 'inclamo-product-variant')[1];
    expect(dawn.text()).toContain('Not available');
    expect(dawn.attributes('disabled')).toBeDefined();
    await dawn.trigger('click');
    expect(wrapper.emitted('select')).toBeUndefined();
  });

  it('lets an unavailable variant be chosen when the dialog allows it', async () => {
    InclamoAPI.searchProducts.mockResolvedValue(found([board]));
    const wrapper = show({ allowUnavailable: true });

    await typeAndWait(wrapper, 'snow');
    await findAll(wrapper, 'inclamo-product-variant')[1].trigger('click');

    expect(wrapper.emitted('select')[0][0].variant.id).toBe('gid://shopify/ProductVariant/22');
  });

  it('names the missing scope', async () => {
    InclamoAPI.searchProducts.mockRejectedValue({ response: { data: { error: 'missing_scope', missing_scopes: ['read_products'] } } });
    const wrapper = show();

    await typeAndWait(wrapper, 'mug');

    expect(find(wrapper, 'inclamo-product-problem').text()).toContain('read_products');
  });

  it('asks the store once the agent stops typing, not for each letter, and loads the next page', async () => {
    InclamoAPI.searchProducts.mockResolvedValueOnce(found([mug], { has_more: true, cursor: 'c1' })).mockResolvedValueOnce(found([board]));
    const wrapper = show();
    vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
    await find(wrapper, 'inclamo-product-query').setValue('m');
    await find(wrapper, 'inclamo-product-query').setValue('mu');
    await find(wrapper, 'inclamo-product-query').setValue('mug');
    await vi.advanceTimersByTimeAsync(350);
    vi.useRealTimers();
    await flush();

    expect(InclamoAPI.searchProducts).toHaveBeenCalledTimes(1);
    await find(wrapper, 'inclamo-product-more').trigger('click');
    await flush();
    expect(InclamoAPI.searchProducts).toHaveBeenLastCalledWith(7, { query: 'mug', after: 'c1' });
    expect(findAll(wrapper, 'inclamo-product')).toHaveLength(2);
  });
});

describe('NewOrderDialog', () => {
  const open = async (props = {}, fromOrder = null) => {
    const wrapper = mount(NewOrderDialog, { props: { conversationId: 7, customer, currency: 'UAH', ...props }, global: { stubs } });
    await wrapper.vm.open(fromOrder);
    await flush();
    return wrapper;
  };
  const addMug = async wrapper => {
    InclamoAPI.searchProducts.mockResolvedValue(found([mug]));
    await typeAndWait(wrapper, 'mug');
    await findAll(wrapper, 'inclamo-product-variant')[0].trigger('click');
  };
  const calculate = async wrapper => {
    InclamoAPI.newOrderPreview.mockResolvedValue({ data: summary });
    await find(wrapper, 'inclamo-new-order-calculate').trigger('click');
    await flush();
  };
  const confirmButton = wrapper => find(wrapper, 'dialog-confirm');
  const confirm = async wrapper => {
    await confirmButton(wrapper).trigger('click');
    await flush();
  };

  it('builds the lines from the search, adding up a product chosen twice, and removes a line', async () => {
    const wrapper = await open();
    expect(find(wrapper, 'inclamo-new-order-empty').exists()).toBe(true);

    await addMug(wrapper);
    await findAll(wrapper, 'inclamo-product-variant')[0].trigger('click');
    expect(findAll(wrapper, 'inclamo-new-order-line')).toHaveLength(1);
    expect(find(wrapper, 'inclamo-new-order-quantity').element.value).toBe('2');

    await find(wrapper, 'inclamo-new-order-remove').trigger('click');
    expect(findAll(wrapper, 'inclamo-new-order-line')).toHaveLength(0);
  });

  it('asks the store for the totals with the discount and shipping, and shows them', async () => {
    const wrapper = await open();
    await addMug(wrapper);
    await find(wrapper, 'inclamo-new-order-discount-type').setValue('percentage');
    await find(wrapper, 'inclamo-new-order-discount-value').setValue('10');
    await find(wrapper, 'inclamo-new-order-shipping').setValue('5.00');

    await calculate(wrapper);

    expect(InclamoAPI.newOrderPreview).toHaveBeenCalledWith(7, {
      lines: [{ variant_id: 'gid://shopify/ProductVariant/11', quantity: 1 }],
      discount: { type: 'percentage', value: '10' },
      shipping: '5.00',
    });
    expect(find(wrapper, 'inclamo-new-order-summary-discount').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-new-order-summary-shipping').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-new-order-total').text()).toContain('113');
  });

  it('cannot be confirmed before the totals are calculated, nor after the order changed, nor without a delivery', async () => {
    const wrapper = await open();
    await addMug(wrapper);
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();

    await calculate(wrapper);
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
    await find(wrapper, 'inclamo-new-order-delivery-email').setValue(true);
    expect(confirmButton(wrapper).attributes('disabled')).toBeUndefined();

    await find(wrapper, 'inclamo-new-order-quantity').setValue('3');
    expect(find(wrapper, 'inclamo-new-order-stale').exists()).toBe(true);
    expect(confirmButton(wrapper).attributes('disabled')).toBeDefined();
  });

  it('creates the order with the invoice emailed, the note beside the parameters, and one action id', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted());
    const wrapper = await open();
    await addMug(wrapper);
    await find(wrapper, 'inclamo-new-order-note').setValue('Gift wrap');
    await calculate(wrapper);
    expect(find(wrapper, 'inclamo-new-order-delivery').text()).toContain('maya.example@example.com');
    await find(wrapper, 'inclamo-new-order-delivery-email').setValue(true);

    await confirm(wrapper);

    const sent = InclamoAPI.performAction.mock.calls[0][1];
    expect(sent).toMatchObject({ action_name: 'new_order', note: 'Gift wrap', params: { delivery: 'email', lines: [{ variant_id: 'gid://shopify/ProductVariant/11', quantity: 1 }] } });
    expect(sent.action_id).toMatch(/^[A-Za-z0-9-]{8,64}$/);
    expect(insertIntoReply).not.toHaveBeenCalled();
    expect(wrapper.emitted('done')).toHaveLength(1);
  });

  it('puts the payment link into the reply when that was chosen', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted({ delivery: 'reply' }));
    const wrapper = await open();
    await addMug(wrapper);
    await calculate(wrapper);
    await find(wrapper, 'inclamo-new-order-delivery-reply').setValue(true);

    await confirm(wrapper);

    expect(InclamoAPI.performAction.mock.calls[0][1].params.delivery).toBe('reply');
    expect(insertIntoReply).toHaveBeenCalledWith('https://shop.example.com/1/invoices/abc');
  });

  it('offers only the link in the reply to a customer without an email', async () => {
    const wrapper = await open({ customer: { ...customer, email: null, phone: '+15005551011' } });
    await addMug(wrapper);
    await calculate(wrapper);

    expect(find(wrapper, 'inclamo-new-order-delivery-email').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-new-order-delivery-reply').element.checked).toBe(true);
    expect(confirmButton(wrapper).attributes('disabled')).toBeUndefined();
  });

  it('shows the store reason when it refuses the order, and stays open', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'refused', refusal: 'store_refused', store_message: 'Product with ID 1 is no longer available.' } });
    const wrapper = await open();
    await addMug(wrapper);
    await calculate(wrapper);
    await find(wrapper, 'inclamo-new-order-delivery-email').setValue(true);

    await confirm(wrapper);

    expect(find(wrapper, 'inclamo-action-message').text()).toContain('Product with ID 1 is no longer available.');
    expect(find(wrapper, 'dialog').exists()).toBe(true);
    expect(wrapper.emitted('done')).toBeUndefined();
    expect(insertIntoReply).not.toHaveBeenCalled();
  });

  it('shows the store reason when it refuses the calculation', async () => {
    InclamoAPI.newOrderPreview.mockRejectedValue({ response: { data: { error: 'store_refused', message: 'Quantity must be greater than or equal to 1' } } });
    const wrapper = await open();
    await addMug(wrapper);

    await find(wrapper, 'inclamo-new-order-calculate').trigger('click');
    await flush();

    expect(find(wrapper, 'inclamo-new-order-problem').text()).toContain('Quantity must be greater than or equal to 1');
    expect(find(wrapper, 'inclamo-new-order-summary').exists()).toBe(false);
  });

  it('starts from the items and quantities of an existing order and names what is no longer sold', async () => {
    InclamoAPI.newOrderPrefill.mockResolvedValue({
      data: { order_number: '#1001', lines: [{ product: mug, variant: mug.variants[0], quantity: 2 }], skipped: [{ title: 'Old Plate', quantity: 1 }] },
    });
    const wrapper = await open({}, order());

    expect(InclamoAPI.newOrderPrefill).toHaveBeenCalledWith(7, 'gid://shopify/Order/1');
    expect(findAll(wrapper, 'inclamo-new-order-line')).toHaveLength(1);
    expect(find(wrapper, 'inclamo-new-order-quantity').element.value).toBe('2');
    expect(find(wrapper, 'inclamo-new-order-skipped').text()).toContain('Old Plate');

    await find(wrapper, 'inclamo-new-order-quantity').setValue('1');
    await calculate(wrapper);
    expect(InclamoAPI.newOrderPreview.mock.calls[0][1].lines).toEqual([{ variant_id: 'gid://shopify/ProductVariant/11', quantity: 1 }]);
  });
});

describe('Order again and orders awaiting payment', () => {
  const withNewOrder = (overrides = {}) =>
    connection({ actions: [...connection().actions, { name: 'new_order', available: true, reason: null, missing_scopes: [], ...overrides }] });
  const newOrderAllowed = { ...order().actions, new_order: { allowed: true, reason: null } };

  it('offers "order again" on an order card of the matched customer and emits it', async () => {
    const card = mount(OrderCard, {
      props: { conversationId: 7, order: order({ actions: newOrderAllowed }), connection: withNewOrder(), viewer: allowedAgent, canOrderAgain: true, startOpen: true },
      global: { stubs },
    });

    await find(card, 'inclamo-action-order-again').trigger('click');

    expect(card.emitted('order-again')[0][0].id).toBe('gid://shopify/Order/1');
  });

  it('does not let an agent without the role order again', () => {
    const card = mount(OrderCard, {
      props: { conversationId: 7, order: order({ actions: newOrderAllowed }), connection: withNewOrder(), viewer: agent, canOrderAgain: true, startOpen: true },
      global: { stubs },
    });

    expect(find(card, 'inclamo-action-order-again').attributes('disabled')).toBeDefined();
  });

  const awaiting = {
    id: 'gid://shopify/DraftOrder/64',
    number: '#D64',
    status: 'invoice_sent',
    created_at: '2026-11-06T11:29:00Z',
    total: money('2062.27'),
    invoice_url: 'https://shop.example.com/1/invoices/abc',
    invoice_sent: true,
    admin_url: 'https://admin.shopify.com/store/example-store/draft_orders/64',
    items: [{ title: 'Blue Mug', quantity: 2 }],
  };
  const panel = (overrides = {}) => ({
    state: 'matched',
    viewer: allowedAgent,
    connection: withNewOrder(),
    customer,
    orders: [order({ actions: newOrderAllowed })],
    page: { has_more: false, cursor: null },
    marked_order: null,
    open_actions: [],
    awaiting_payment: [],
    ...overrides,
  });
  const show = async data => {
    InclamoAPI.getPanel.mockResolvedValue({ data });
    const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();
    return wrapper;
  };

  it('offers "New order" to an agent with the role, and not to one without', async () => {
    expect(find(await show(panel()), 'inclamo-new-order-open').exists()).toBe(true);

    const without = await show(panel({ viewer: agent }));
    expect(find(without, 'inclamo-new-order-open').exists()).toBe(false);
    expect(find(without, 'inclamo-new-order-unavailable').exists()).toBe(false);
  });

  it('names the missing permission instead of offering "New order"', async () => {
    const wrapper = await show(panel({ viewer: admin, connection: withNewOrder({ available: false, reason: 'missing_scope', missing_scopes: ['write_draft_orders'] }) }));

    expect(find(wrapper, 'inclamo-new-order-open').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-new-order-unavailable').text()).toContain('write_draft_orders');
  });

  it('lists the orders awaiting payment with items, total, payment link and admin link, and puts the link into the reply', async () => {
    const wrapper = await show(panel({ awaiting_payment: [awaiting] }));

    const block = find(wrapper, 'inclamo-awaiting-#D64');
    expect(block.text()).toContain('Blue Mug');
    expect(block.text()).toContain('Invoice sent');
    expect(find(wrapper, 'inclamo-awaiting-total').text()).toContain('2,062.27');
    expect(find(wrapper, 'inclamo-awaiting-link').attributes('href')).toBe(awaiting.invoice_url);
    expect(find(wrapper, 'inclamo-awaiting-admin-link').attributes('href')).toBe(awaiting.admin_url);

    await find(wrapper, 'inclamo-awaiting-insert').trigger('click');
    expect(insertIntoReply).toHaveBeenCalledWith(awaiting.invoice_url);
  });

  it('says when a new order is not confirmed by the store yet', async () => {
    const wrapper = await show(panel({ open_actions: [{ action_id: 'a-1', action: 'new_order', order_id: null, outcome: 'unknown' }] }));

    expect(find(wrapper, 'inclamo-new-order-unconfirmed').exists()).toBe(true);
  });

  it('opens the new order from "order again" with that order items', async () => {
    InclamoAPI.newOrderPrefill.mockResolvedValue({ data: { order_number: '#1001', lines: [{ product: mug, variant: mug.variants[0], quantity: 2 }], skipped: [] } });
    const wrapper = await show(panel());

    await find(wrapper, 'inclamo-order-#1001').find('button').trigger('click');
    await find(wrapper, 'inclamo-action-order-again').trigger('click');
    await flush();

    expect(InclamoAPI.newOrderPrefill).toHaveBeenCalledWith(7, 'gid://shopify/Order/1');
    expect(findAll(wrapper, 'inclamo-new-order-line')).toHaveLength(1);
  });
});
