import { mount } from '@vue/test-utils';
import OrderCard from '../components/OrderCard.vue';
import { stubs, order, connection, agent, allowedAgent } from './helpers';

vi.mock('../api', () => ({ default: { performAction: vi.fn(), refundPreview: vi.fn() } }));

const card = (props = {}) =>
  mount(OrderCard, {
    props: { conversationId: 7, order: order(), connection: connection(), viewer: allowedAgent, startOpen: true, ...props },
    global: { stubs },
  });
const button = (wrapper, action) => wrapper.find(`[data-testid="inclamo-action-${action}"]`);

describe('OrderCard', () => {
  it('shows the number, total, statuses, items, address and the link to the admin', () => {
    const wrapper = card();

    expect(wrapper.text()).toContain('#1001');
    expect(wrapper.find('[data-testid="inclamo-order-statuses"]').text()).toContain('Paid');
    expect(wrapper.find('[data-testid="inclamo-order-statuses"]').text()).toContain('Not shipped');
    expect(wrapper.findAll('[data-testid="inclamo-order-item"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="inclamo-order-address"]').text()).toContain('1 Example Street');
    expect(wrapper.find('[data-testid="inclamo-order-admin-link"]').attributes('href')).toBe('https://admin.shopify.com/store/example-store/orders/1');
  });

  it('shows each shipment with its carrier, tracking number and link', () => {
    const shipments = [
      { id: 's1', status: 'FULFILLED', tracking: [{ company: 'DHL Express', number: 'A1', url: 'https://example.com/track/A1' }] },
      { id: 's2', status: 'FULFILLED', tracking: [{ company: 'UPS', number: 'B2', url: 'https://example.com/track/B2' }] },
    ];
    const wrapper = card({ order: order({ shipments, fulfillment_status: 'FULFILLED' }) });

    const rows = wrapper.findAll('[data-testid="inclamo-order-shipment"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].text()).toContain('DHL Express A1');
    expect(rows[1].find('a').attributes('href')).toBe('https://example.com/track/B2');
  });

  it('shows what was refunded and what remains refundable', () => {
    const wrapper = card({
      order: order({ financial_status: 'PARTIALLY_REFUNDED', refunded: { amount: '20.0', currency: 'EUR' }, refundable: { amount: '34.0', currency: 'EUR' }, refunds: [{ id: 'r1', amount: '20.0', currency: 'EUR' }] }),
    });

    const refunds = wrapper.find('[data-testid="inclamo-order-refunds"]').text();
    expect(refunds).toContain('20');
    expect(refunds).toContain('34');
  });

  it('offers every action to an agent who may act', () => {
    const wrapper = card();

    ['cancel', 'refund', 'address', 'replacement'].forEach(action => {
      expect(button(wrapper, action).attributes('disabled')).toBeUndefined();
    });
  });

  it('shows every action as unavailable, with the reason, to an agent without the role', () => {
    const wrapper = card({ viewer: agent });

    ['cancel', 'refund', 'address', 'replacement'].forEach(action => {
      expect(button(wrapper, action).attributes('disabled')).toBeDefined();
      expect(button(wrapper, action).attributes('title')).toContain('administrator has not allowed');
    });
  });

  it('names the missing scope of an unavailable action', () => {
    const actions = connection().actions.map(entry =>
      entry.name === 'replacement' ? { ...entry, available: false, reason: 'missing_scope', missing_scopes: ['write_draft_orders'] } : entry
    );
    const wrapper = card({ connection: connection({ actions }) });

    expect(button(wrapper, 'replacement').attributes('title')).toContain('write_draft_orders');
    expect(button(wrapper, 'refund').attributes('disabled')).toBeUndefined();
  });

  it('says "already shipped" for the address of a shipped order', () => {
    const wrapper = card({ order: order({ actions: { ...order().actions, address: { allowed: false, reason: 'already_shipped' } } }) });

    expect(button(wrapper, 'address').attributes('disabled')).toBeDefined();
    expect(button(wrapper, 'address').attributes('title')).toBe('Already shipped.');
  });

  it('shows the address as unavailable in the limited mode', () => {
    const actions = connection().actions.map(entry => (entry.name === 'address' ? { ...entry, available: false, reason: 'customer_data_hidden' } : entry));
    const wrapper = card({ order: order({ shipping_address: null, customer: null }), connection: connection({ customer_data: 'limited', actions }) });

    expect(wrapper.find('[data-testid="inclamo-order-address-hidden"]').text()).toContain('does not share');
    expect(button(wrapper, 'address').attributes('disabled')).toBeDefined();
  });

  it('shows an order as cancelling while the store works on it, with no action offered', () => {
    const wrapper = card({ openAction: { action: 'cancel', outcome: 'running', order_id: 'gid://shopify/Order/1' } });

    expect(wrapper.find('[data-testid="inclamo-order-statuses"]').text()).toBe('Cancelling…');
    expect(button(wrapper, 'refund').attributes('disabled')).toBeDefined();
  });

  it('shows an unknown outcome with a link to the order, neither as done nor as failed', () => {
    const wrapper = card({ openAction: { action: 'refund', outcome: 'unknown', order_id: 'gid://shopify/Order/1' } });

    const notice = wrapper.find('[data-testid="inclamo-order-unknown"]');
    expect(notice.text()).toContain('Outcome unknown');
    expect(notice.find('a').attributes('href')).toContain('/orders/1');
  });

  it('marks and unmarks the order the conversation is about', async () => {
    const unmarked = card();
    await unmarked.find('[data-testid="inclamo-order-mark"]').trigger('click');
    expect(unmarked.emitted('mark')[0][0].number).toBe('#1001');

    const marked = card({ marked: true });
    expect(marked.find('[data-testid="inclamo-order-marked"]').exists()).toBe(true);
    await marked.find('[data-testid="inclamo-order-unmark"]').trigger('click');
    expect(marked.emitted('unmark')).toHaveLength(1);
  });
});
