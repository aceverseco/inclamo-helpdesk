import { mount } from '@vue/test-utils';
import EditItemsDialog from '../components/EditItemsDialog.vue';
import ProductSearch from '../components/ProductSearch.vue';
import RefundDialog from '../components/RefundDialog.vue';
import OrderCard from '../components/OrderCard.vue';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { clearCommerce } from '../widgets/commerce';
import { stubs, order, connection, agent, allowedAgent, admin, flush, expandCard } from './helpers';

vi.mock('../api', () => ({
  default: {
    editItemsPreview: vi.fn(),
    searchProducts: vi.fn(),
    performAction: vi.fn(),
    refundPreview: vi.fn(),
    getPanel: vi.fn(),
  },
}));

const money = amount => ({ amount, currency: 'UAH' });
const line = (number, title, { current, unshipped, price = '80.0' }) => ({
  id: `gid://shopify/LineItem/${number}`,
  title,
  variant: null,
  quantity: current,
  current_quantity: current,
  unfulfilled_quantity: unshipped,
  refundable_quantity: current,
  unit_price: money(price),
});
// One shipped item, one partly shipped (1 of 3 shipped), one not shipped at all.
const editable = (overrides = {}) =>
  order({
    number: '#1421',
    currency: 'UAH',
    total: money('1745.9'),
    refundable: money('1745.9'),
    fulfillment_status: 'PARTIALLY_FULFILLED',
    items: [
      line(1, 'Minimal Snowboard', { current: 1, unshipped: 0, price: '885.95' }),
      line(2, 'Ceramic Plate', { current: 3, unshipped: 2, price: '30.0' }),
      line(3, 'Tracked Mug', { current: 2, unshipped: 2 }),
    ],
    actions: { ...order().actions, edit_items: { allowed: true, reason: null } },
    ...overrides,
  });
const withEdit = (entry = {}) =>
  connection({ actions: [...connection().actions, { name: 'edit_items', available: true, reason: null, missing_scopes: [], ...entry }] });

const summary = (overrides = {}) => ({
  currency: 'UAH',
  total_before: money('1745.9'),
  total_after: money('1665.9'),
  balance: money('-80.0'),
  difference: 'due_back',
  amount: '80.0',
  customer_email: true,
  lines: [
    { id: 'gid://shopify/LineItem/1', title: 'Minimal Snowboard', variant: null, quantity: 1, quantity_before: 1, editable: 0, restocking: false, unit_price: money('885.95') },
    { id: 'gid://shopify/LineItem/3', title: 'Tracked Mug', variant: null, quantity: 1, quantity_before: 2, editable: 2, restocking: true, unit_price: money('80.0') },
  ],
  added: [],
  ...overrides,
});
const owedSummary = (overrides = {}) =>
  summary({
    total_after: money('2445.85'),
    balance: money('699.95'),
    difference: 'owed',
    amount: '699.95',
    lines: summary().lines.map(entry => ({ ...entry, quantity: entry.quantity_before })),
    added: [{ title: 'Snowboard', variant: 'Ice', quantity: 1, unit_price: money('699.95') }],
    ...overrides,
  });
const board = { id: 'gid://shopify/Product/2', title: 'Snowboard', image_url: null, variants: [{ id: 'gid://shopify/ProductVariant/21', title: 'Ice', sku: null, price: money('699.95'), available_for_sale: true }] };

const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const findAll = (wrapper, id) => wrapper.findAll(`[data-testid="${id}"]`);
const lineOf = (wrapper, number) => wrapper.find(`[data-line-id="gid://shopify/LineItem/${number}"]`);
const sent = () => InclamoAPI.performAction.mock.calls.at(-1)[1];

const openDialog = async (props = {}) => {
  const wrapper = mount(EditItemsDialog, { props: { conversationId: 7, order: editable(), ...props }, global: { stubs } });
  await wrapper.vm.open();
  await flush();
  return wrapper;
};
const reduceMug = async wrapper => {
  await lineOf(wrapper, 3).find('[data-testid="inclamo-edit-quantity"]').setValue('1');
};
const calculate = async wrapper => {
  await find(wrapper, 'inclamo-edit-calculate').trigger('click');
  await flush();
};
const save = async wrapper => {
  await find(wrapper, 'dialog-confirm').trigger('click');
  await flush();
};
const addBoard = async wrapper => {
  wrapper.findComponent(ProductSearch).vm.$emit('select', { product: board, variant: board.variants[0] });
  await flush();
};

beforeEach(() => vi.clearAllMocks());

// The panel store keeps answers between mounts; every test starts empty.
beforeEach(() => clearCommerce());

describe('EditItemsDialog', () => {
  it('shows a shipped item without controls, and keeps the shipped units of a partly shipped one', async () => {
    const wrapper = await openDialog();

    expect(findAll(wrapper, 'inclamo-edit-line')).toHaveLength(3);
    const shipped = lineOf(wrapper, 1);
    expect(shipped.find('[data-testid="inclamo-edit-quantity"]').exists()).toBe(false);
    expect(shipped.find('[data-testid="inclamo-edit-locked"]').text()).toContain('1');
    expect(shipped.text()).toContain('Shipped');
    const partly = lineOf(wrapper, 2);
    expect(partly.find('[data-testid="inclamo-edit-quantity"]').attributes('min')).toBe('1');
    expect(partly.find('[data-testid="inclamo-edit-partly-shipped"]').text()).toContain('1 shipped');
    await partly.find('[data-testid="inclamo-edit-take-off"]').trigger('click');
    expect(partly.find('[data-testid="inclamo-edit-quantity"]').element.value).toBe('1');
    expect(lineOf(wrapper, 3).find('[data-testid="inclamo-edit-quantity"]').attributes('min')).toBe('0');
  });

  it('has nothing to calculate or save before a change, and refuses a quantity below what has shipped', async () => {
    const wrapper = await openDialog();

    expect(find(wrapper, 'inclamo-edit-calculate').attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'dialog-confirm').attributes('disabled')).toBeDefined();
    await lineOf(wrapper, 2).find('[data-testid="inclamo-edit-quantity"]').setValue('0');
    expect(find(wrapper, 'inclamo-edit-invalid').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-edit-calculate').attributes('disabled')).toBeDefined();
  });

  it('asks the store for the new total and shows the money due back; nothing is saved by that', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary() });
    const wrapper = await openDialog();

    await reduceMug(wrapper);
    await calculate(wrapper);

    expect(InclamoAPI.editItemsPreview).toHaveBeenCalledWith(7, 'gid://shopify/Order/1', { lines: [{ line_item_id: 'gid://shopify/LineItem/3', quantity: 1 }], additions: [] });
    expect(InclamoAPI.performAction).not.toHaveBeenCalled();
    expect(find(wrapper, 'inclamo-edit-summary-change').text()).toContain('Tracked Mug: 2 → 1');
    expect(find(wrapper, 'inclamo-edit-total').text()).toContain('1');
    expect(find(wrapper, 'inclamo-edit-difference').attributes('data-difference')).toBe('due_back');
    expect(find(wrapper, 'inclamo-edit-difference').text()).toContain('due back');
    expect(find(wrapper, 'inclamo-edit-invoice').exists()).toBe(false);
    expect(find(wrapper, 'dialog-confirm').attributes('disabled')).toBeUndefined();
  });

  it('says when the total does not change, with no invoice and no refund to offer', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary({ total_after: money('1745.9'), balance: money('0.0'), difference: 'none', amount: '0.0' }) });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    expect(find(wrapper, 'inclamo-edit-difference').text()).toContain('does not change');
    expect(find(wrapper, 'inclamo-edit-invoice').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-edit-notify').exists()).toBe(true);
  });

  it('asks for a new total when the items change after the summary', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary() });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    await lineOf(wrapper, 3).find('[data-testid="inclamo-edit-quantity"]').setValue('0');

    expect(find(wrapper, 'inclamo-edit-stale').exists()).toBe(true);
    expect(find(wrapper, 'dialog-confirm').attributes('disabled')).toBeDefined();
  });

  it('saves the changes with the totals the agent saw', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary() });
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'accepted', action: 'edit_items', result: { difference: 'due_back', amount: '80.0', currency: 'UAH' } } });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    await save(wrapper);

    expect(sent()).toMatchObject({
      action_name: 'edit_items',
      order_id: 'gid://shopify/Order/1',
      params: { lines: [{ line_item_id: 'gid://shopify/LineItem/3', quantity: 1 }], additions: [], notify: false, invoice: false, expected: { total_after: '1665.9', balance: '-80.0' } },
    });
    expect(wrapper.emitted('done')[0][0].result.difference).toBe('due_back');
  });

  it('adds a product from the catalogue, once per variant', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: owedSummary() });
    const wrapper = await openDialog();

    await addBoard(wrapper);
    await addBoard(wrapper);
    await calculate(wrapper);

    expect(findAll(wrapper, 'inclamo-edit-addition')).toHaveLength(1);
    expect(InclamoAPI.editItemsPreview).toHaveBeenCalledWith(7, 'gid://shopify/Order/1', { lines: [], additions: [{ variant_id: 'gid://shopify/ProductVariant/21', quantity: 2 }] });
    expect(find(wrapper, 'inclamo-edit-summary-added').text()).toContain('Snowboard · Ice: 1 added');
  });

  it('offers an invoice when the customer owes, and sends it only without the notification', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: owedSummary() });
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'accepted', action: 'edit_items', result: { difference: 'owed', amount: '699.95', currency: 'UAH', invoice: 'sent' } } });
    const wrapper = await openDialog();
    await addBoard(wrapper);
    await calculate(wrapper);

    expect(find(wrapper, 'inclamo-edit-difference').text()).toContain('owes');
    await find(wrapper, 'inclamo-edit-invoice').setValue(true);
    await save(wrapper);

    expect(sent().params).toMatchObject({ notify: false, invoice: true, expected: { total_after: '2445.85', balance: '699.95' } });
  });

  it('shows the invoice as part of the store\'s email when the customer is notified, and sends no second one', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: owedSummary() });
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'accepted', action: 'edit_items', result: {} } });
    const wrapper = await openDialog();
    await addBoard(wrapper);
    await calculate(wrapper);

    await find(wrapper, 'inclamo-edit-notify').setValue(true);

    const invoice = find(wrapper, 'inclamo-edit-invoice');
    expect(invoice.element.checked).toBe(true);
    expect(invoice.attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'inclamo-edit-invoice-included').exists()).toBe(true);
    await save(wrapper);
    expect(sent().params).toMatchObject({ notify: true, invoice: false });
  });

  it('says why no invoice can be emailed when the order has no email', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: owedSummary({ customer_email: false }) });
    const wrapper = await openDialog();
    await addBoard(wrapper);
    await calculate(wrapper);

    expect(find(wrapper, 'inclamo-edit-invoice').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-edit-no-email').exists()).toBe(true);
  });

  it('shows the store refusing the summary in its own words', async () => {
    InclamoAPI.editItemsPreview.mockRejectedValue({ response: { data: { error: 'store_refused', message: 'The order cannot be edited.' } } });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    expect(find(wrapper, 'inclamo-edit-problem').text()).toContain('The order cannot be edited.');
    expect(find(wrapper, 'inclamo-edit-summary').exists()).toBe(false);
  });

  it('shows the store refusing the save in its own words, and stays open', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary() });
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'refused', refusal: 'store_refused', store_message: 'The order cannot be edited.' } });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    await save(wrapper);

    expect(find(wrapper, 'inclamo-action-message').text()).toContain('The order cannot be edited.');
    expect(wrapper.emitted('done')).toBeUndefined();
    expect(find(wrapper, 'dialog').exists()).toBe(true);
  });

  it('shows the new total when the order changed in the store meanwhile, to be saved again', async () => {
    InclamoAPI.editItemsPreview.mockResolvedValue({ data: summary() });
    const changed = summary({ total_after: money('1600.0'), balance: money('-145.9'), amount: '145.9' });
    InclamoAPI.performAction.mockResolvedValueOnce({ data: { outcome: 'refused', refusal: 'summary_changed', result: { summary: changed } } });
    InclamoAPI.performAction.mockResolvedValueOnce({ data: { outcome: 'accepted', action: 'edit_items', result: {} } });
    const wrapper = await openDialog();
    await reduceMug(wrapper);
    await calculate(wrapper);

    await save(wrapper);

    expect(find(wrapper, 'inclamo-action-message').text()).toContain('changed in the store');
    expect(find(wrapper, 'inclamo-edit-difference').text()).toContain('145.9');
    const first = sent();
    await save(wrapper);
    expect(sent().params.expected).toEqual({ total_after: '1600.0', balance: '-145.9' });
    expect(sent().action_id).not.toBe(first.action_id);
  });
});

describe('Edit items on the order card', () => {
  const card = (props = {}) =>
    mount(OrderCard, {
      props: { conversationId: 7, order: editable(), connection: withEdit(), viewer: allowedAgent, startOpen: true, ...props },
      global: { stubs },
    });
  const button = wrapper => find(wrapper, 'inclamo-action-edit_items');

  it('is offered to an agent with the role, on a connection with the scope, for an order with items left to ship', () => {
    expect(button(card()).exists()).toBe(true);
    expect(button(card({ viewer: admin })).exists()).toBe(true);
  });

  it('is not offered for a fully shipped or a cancelled order', () => {
    const shipped = editable({ actions: { ...order().actions, edit_items: { allowed: false, reason: 'already_shipped' } } });
    const cancelled = editable({ cancelled_at: '2026-11-06T10:00:00Z', actions: { ...order().actions, edit_items: { allowed: false, reason: 'already_cancelled' } } });

    [shipped, cancelled].forEach(subject => {
      const wrapper = card({ order: subject });
      expect(button(wrapper).exists()).toBe(false);
      expect(find(wrapper, 'inclamo-edit-unavailable').exists()).toBe(false);
    });
  });

  it('is not offered to an agent without the role', () => {
    const wrapper = card({ viewer: agent });

    expect(button(wrapper).exists()).toBe(false);
    expect(find(wrapper, 'inclamo-edit-unavailable').exists()).toBe(false);
  });

  it('is not offered without the scope, and a line names the missing permission', () => {
    const wrapper = card({ viewer: admin, connection: withEdit({ available: false, reason: 'missing_scope', missing_scopes: ['write_order_edits'] }) });

    expect(button(wrapper).exists()).toBe(false);
    expect(find(wrapper, 'inclamo-edit-unavailable').text()).toContain('write_order_edits');
  });

  it('shows what the order holds and comes to now: current quantities and total, an item taken off not listed', () => {
    const items = editable().items.map(item => (item.title === 'Tracked Mug' ? { ...item, current_quantity: 1 } : item.title === 'Ceramic Plate' ? { ...item, current_quantity: 0 } : item));
    const wrapper = card({ order: editable({ items, current_total: money('1665.9') }) });

    const shown = findAll(wrapper, 'inclamo-order-item');
    expect(shown).toHaveLength(2);
    expect(wrapper.find('[data-testid="inclamo-order-item"][data-line-id="gid://shopify/LineItem/3"]').text()).toContain('× 1');
    expect(wrapper.text()).not.toContain('Ceramic Plate');
    expect(find(wrapper, 'inclamo-order-total').text()).toContain('1,665.90');
  });

  it('shows the total of an order the store gives no current total for', () => {
    expect(find(card({ order: editable({ current_total: null }) }), 'inclamo-order-total').text()).toContain('1,745.90');
  });

  it('opens the refund dialog for the amount due back after a save, and offers it again', async () => {
    const wrapper = card();

    wrapper.findComponent(EditItemsDialog).vm.$emit('done', { outcome: 'accepted', action: 'edit_items', result: { difference: 'due_back', amount: '80.0', currency: 'UAH' } });
    await flush();

    const refund = wrapper.findComponent(RefundDialog);
    expect(refund.find('[data-testid="inclamo-refund-due-back"]').text()).toContain('80');
    expect(refund.find('[data-testid="inclamo-refund-mode-amount"]').element.checked).toBe(true);
    expect(refund.find('[data-testid="inclamo-refund-amount"]').element.value).toBe('80.0');
    expect(InclamoAPI.performAction).not.toHaveBeenCalled();
    expect(find(wrapper, 'inclamo-edited-due-back').text()).toContain('80');
    expect(find(wrapper, 'inclamo-edited-refund').exists()).toBe(true);
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('opens no refund when the customer owes, and says when the store did not send the invoice', async () => {
    const wrapper = card();

    wrapper.findComponent(EditItemsDialog).vm.$emit('done', {
      outcome: 'accepted',
      action: 'edit_items',
      result: { difference: 'owed', amount: '699.95', currency: 'UAH', invoice: 'refused', invoice_message: 'No outstanding balance exist' },
    });
    await flush();

    expect(wrapper.findComponent(RefundDialog).find('[data-testid="inclamo-refund-due-back"]').exists()).toBe(false);
    expect(find(wrapper, 'inclamo-edited-invoice').text()).toContain('No outstanding balance exist');
  });
});

describe('The panel after an edit', () => {
  const panel = (orders, page) => ({
    state: 'matched',
    viewer: allowedAgent,
    connection: withEdit(),
    customer: { id: 'gid://shopify/Customer/1', name: 'Maya Example', orders_count: 11, total_spent: money('6355.7') },
    orders,
    page,
    marked_order: null,
    open_actions: [],
  });
  const newer = order({ id: 'gid://shopify/Order/2', number: '#1545' });

  it('keeps an order loaded further down, and the refund its card opened, when it reads the orders again', async () => {
    InclamoAPI.getPanel.mockImplementation((id, after) =>
      Promise.resolve({ data: after ? panel([editable()], { has_more: false, cursor: null }) : panel([newer], { has_more: true, cursor: 'c1' }) })
    );
    const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();
    await find(wrapper, 'inclamo-orders-more').trigger('click');
    await flush();
    const card = wrapper.findAllComponents(OrderCard).find(component => component.props('order').number === '#1421');
    await expandCard(card);

    card.findComponent(EditItemsDialog).vm.$emit('done', { outcome: 'accepted', action: 'edit_items', result: { difference: 'due_back', amount: '80.0', currency: 'UAH' } });
    await flush();
    await flush();

    // The third argument is the account the panel was read for.
    expect(InclamoAPI.getPanel).toHaveBeenLastCalledWith(7, 'c1', '');
    expect(wrapper.findAllComponents(OrderCard).map(component => component.props('order').number)).toEqual(['#1545', '#1421']);
    expect(find(wrapper, 'inclamo-refund-due-back').exists()).toBe(true);
    expect(find(wrapper, 'inclamo-edited-due-back').exists()).toBe(true);
  });
});
