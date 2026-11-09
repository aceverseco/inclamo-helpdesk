import { mount } from '@vue/test-utils';
import OrderCard from '../components/OrderCard.vue';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { stubs, order, connection, agent, allowedAgent, admin, flush } from './helpers';

vi.mock('../api', () => ({
  default: { getPanel: vi.fn(), lookup: vi.fn(), performAction: vi.fn(), refundPreview: vi.fn(), marks: vi.fn() },
}));

const card = (props = {}) =>
  mount(OrderCard, {
    props: { conversationId: 7, order: order(), connection: connection(), viewer: allowedAgent, startOpen: true, ...props },
    global: { stubs },
  });
const section = async data => {
  InclamoAPI.getPanel.mockResolvedValue({ data });
  const wrapper = mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
  await flush();
  return wrapper;
};
const texts = (wrapper, id) => wrapper.findAll(`[data-testid="${id}"]`).map(element => element.text());
const has = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`).exists();

const customer = { id: 'gid://shopify/Customer/1', name: 'Maya Example', orders_count: 1, total_spent: null, tags: ['wholesale'], note: 'Pays by invoice' };
const tagged = order({ tags: ['gift', 'priority'], note: 'Leave at the door' });

describe('Tags and notes', () => {
  it("shows the order's tags and note on the card", () => {
    const wrapper = card({ order: tagged });

    expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
    expect(wrapper.find('[data-testid="inclamo-order-note"]').text()).toBe('Leave at the door');
  });

  it('says so when an order has no tags and no note', () => {
    const wrapper = card({ order: order({ tags: [], note: null }) });

    expect(has(wrapper, 'inclamo-order-no-tags')).toBe(true);
    expect(has(wrapper, 'inclamo-order-no-note')).toBe(true);
  });

  it("shows the customer's tags and note in the customer block", async () => {
    const wrapper = await section({ state: 'matched', viewer: allowedAgent, connection: connection(), customer, orders: [tagged], page: { has_more: false }, open_actions: [] });

    expect(texts(wrapper, 'inclamo-customer-tag')).toEqual(['wholesale']);
    expect(wrapper.find('[data-testid="inclamo-customer-note"]').text()).toBe('Pays by invoice');
  });

  it('shows tags and notes to an agent without the order-actions role', async () => {
    const wrapper = await section({ state: 'matched', viewer: agent, connection: connection(), customer, orders: [tagged], page: { has_more: false }, open_actions: [] });
    await wrapper.find('[data-testid="inclamo-order-#1001"] button').trigger('click');

    expect(texts(wrapper, 'inclamo-customer-tag')).toEqual(['wholesale']);
    expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
    expect(wrapper.find('[data-testid="inclamo-order-note"]').text()).toBe('Leave at the door');
  });

  it("shows no customer tags or note in the limited mode, and still the order's", async () => {
    const limited = connection({ customer_data: 'limited' });
    const wrapper = await section({ state: 'limited', viewer: allowedAgent, connection: limited, page: null, open_actions: [] });
    InclamoAPI.lookup.mockResolvedValue({ data: { found: true, order: order({ ...tagged, customer: null, shipping_address: null }) } });
    await wrapper.find('[data-testid="inclamo-lookup-number"]').setValue('1001');
    await wrapper.find('[data-testid="inclamo-lookup"]').trigger('submit');
    await flush();

    expect(has(wrapper, 'inclamo-customer-marks')).toBe(false);
    expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
    expect(wrapper.find('[data-testid="inclamo-order-note"]').text()).toBe('Leave at the door');
  });
});

const ACTIONS = ['cancel', 'refund', 'address', 'replacement', 'order_tags', 'order_note', 'customer_tags', 'customer_note'];
// A connection whose app lacks the scopes named per action, e.g. { customer_tags: ['write_customers'] }.
const scoped = (missing = {}, overrides = {}) =>
  connection({
    actions: ACTIONS.map(name =>
      missing[name] ? { name, available: false, reason: 'missing_scope', missing_scopes: missing[name] } : { name, available: true, reason: null, missing_scopes: [] }
    ),
    ...overrides,
  });
const withoutCustomers = scoped({ customer_tags: ['write_customers'], customer_note: ['write_customers'] });
const both = { order_marks: true, customer_marks: true };
const matched = ({ viewer = admin, can = both, conn = scoped() } = {}) => ({
  state: 'matched',
  viewer,
  connection: conn,
  can,
  customer,
  orders: [tagged],
  page: { has_more: false },
  open_actions: [],
});
const expand = async wrapper => {
  await wrapper.find('[data-testid="inclamo-order-#1001"] button').trigger('click');
};
const accepted = { data: { outcome: 'accepted' } };
const refused = (refusal, storeMessage = null) => ({ data: { outcome: 'refused', refusal, store_message: storeMessage } });
const storeHolds = (tags, note) => ({ data: { id: 'x', tags, note } });
const editable = (wrapper, subject) =>
  ['tag-input', 'tag-remove', 'note-edit'].some(control => has(wrapper, `inclamo-${subject}-${control}`));
const lastPayload = () => InclamoAPI.performAction.mock.calls.at(-1)[1];

describe('Changing tags and notes', () => {
  beforeEach(() => vi.resetAllMocks());

  describe('who is offered the controls', () => {
    it.each([
      ['an administrator', admin],
      ['an agent with the role', allowedAgent],
    ])('offers %s the controls on the order and on the customer when the app holds both scopes', async (_, viewer) => {
      const wrapper = await section(matched({ viewer }));
      await expand(wrapper);

      expect(wrapper.findAll('[data-testid="inclamo-order-tag-remove"]')).toHaveLength(2);
      expect(has(wrapper, 'inclamo-order-tag-input')).toBe(true);
      expect(has(wrapper, 'inclamo-order-note-edit')).toBe(true);
      expect(wrapper.findAll('[data-testid="inclamo-customer-tag-remove"]')).toHaveLength(1);
      expect(has(wrapper, 'inclamo-customer-tag-input')).toBe(true);
      expect(has(wrapper, 'inclamo-customer-note-edit')).toBe(true);
      expect(has(wrapper, 'inclamo-customer-marks-lacks')).toBe(false);
    });

    it('offers an agent without the role no control, and shows the tags and the notes', async () => {
      const wrapper = await section(matched({ viewer: agent, can: { order_marks: false, customer_marks: false } }));
      await expand(wrapper);

      expect(editable(wrapper, 'order')).toBe(false);
      expect(editable(wrapper, 'customer')).toBe(false);
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
      expect(texts(wrapper, 'inclamo-customer-tag')).toEqual(['wholesale']);
      expect(has(wrapper, 'inclamo-customer-marks-lacks')).toBe(false);
    });

    it('follows the panel, not the viewer: an administrator whose panel allows nothing gets no control', async () => {
      const wrapper = await section(matched({ viewer: admin, can: { order_marks: false, customer_marks: false } }));
      await expand(wrapper);

      expect(editable(wrapper, 'order')).toBe(false);
      expect(editable(wrapper, 'customer')).toBe(false);
    });

    it('without write_customers keeps the order controls, and names the missing permission at the customer', async () => {
      const wrapper = await section(matched({ can: { order_marks: true, customer_marks: false }, conn: withoutCustomers }));
      await expand(wrapper);

      expect(editable(wrapper, 'order')).toBe(true);
      expect(editable(wrapper, 'customer')).toBe(false);
      expect(texts(wrapper, 'inclamo-customer-tag')).toEqual(['wholesale']);
      expect(wrapper.find('[data-testid="inclamo-customer-note"]').text()).toBe('Pays by invoice');
      expect(wrapper.find('[data-testid="inclamo-customer-marks-lacks"]').text()).toBe(
        'Tags and the note cannot be changed here: the connected app lacks write_customers.'
      );
      expect(has(wrapper, 'inclamo-order-marks-lacks')).toBe(false);
    });

    it("offers the order's controls in the limited mode, where no customer is shown", async () => {
      const limited = scoped({}, { customer_data: 'limited' });
      const wrapper = await section({ state: 'limited', viewer: admin, connection: limited, can: { order_marks: true, customer_marks: false }, page: null, open_actions: [] });
      InclamoAPI.lookup.mockResolvedValue({ data: { found: true, order: order({ ...tagged, customer: null, shipping_address: null }) } });
      await wrapper.find('[data-testid="inclamo-lookup-number"]').setValue('1001');
      await wrapper.find('[data-testid="inclamo-lookup"]').trigger('submit');
      await flush();

      expect(has(wrapper, 'inclamo-customer-marks')).toBe(false);
      expect(editable(wrapper, 'order')).toBe(true);
    });
  });

  describe('changes, sent at once', () => {
    const editableCard = () => card({ order: tagged, connection: scoped(), canChangeMarks: true });

    it('adds an order tag without a confirmation, sending only that tag, and shows what the store holds then', async () => {
      InclamoAPI.performAction.mockResolvedValue(accepted);
      InclamoAPI.marks.mockResolvedValue(storeHolds(['address-confirmed', 'fraud-check', 'gift', 'priority'], 'Leave at the door'));
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue('  address-confirmed ');
      await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
      await flush();

      expect(InclamoAPI.performAction).toHaveBeenCalledTimes(1);
      expect(InclamoAPI.performAction.mock.calls[0][0]).toBe(7);
      expect(lastPayload()).toEqual({
        action_name: 'order_tags',
        order_id: 'gid://shopify/Order/1',
        params: { operation: 'add', tag: 'address-confirmed' },
        action_id: expect.any(String),
      });
      expect(has(wrapper, 'dialog')).toBe(false);
      expect(InclamoAPI.marks).toHaveBeenCalledWith(7, { order_id: 'gid://shopify/Order/1' });
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['address-confirmed', 'fraud-check', 'gift', 'priority']);
      expect(wrapper.find('[data-testid="inclamo-order-tag-input"]').element.value).toBe('');
    });

    it('sends each change with its own action id', async () => {
      InclamoAPI.performAction.mockResolvedValue(accepted);
      InclamoAPI.marks.mockResolvedValue(storeHolds(['gift', 'priority'], null));
      const wrapper = editableCard();

      for (const tag of ['a', 'b']) {
        await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue(tag);
        await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
        await flush();
      }

      const [first, second] = InclamoAPI.performAction.mock.calls.map(call => call[1].action_id);
      expect(first).not.toBe(second);
    });

    it('does not send an empty tag', async () => {
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue('   ');
      await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
      await flush();

      expect(wrapper.find('[data-testid="inclamo-order-tag-add"]').attributes('disabled')).toBeDefined();
      expect(InclamoAPI.performAction).not.toHaveBeenCalled();
    });

    it('removes an order tag', async () => {
      InclamoAPI.performAction.mockResolvedValue(accepted);
      InclamoAPI.marks.mockResolvedValue(storeHolds(['gift'], 'Leave at the door'));
      const wrapper = editableCard();

      await wrapper.findAll('[data-testid="inclamo-order-tag-remove"]')[1].trigger('click');
      await flush();

      expect(lastPayload()).toMatchObject({ action_name: 'order_tags', order_id: 'gid://shopify/Order/1', params: { operation: 'remove', tag: 'priority' } });
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift']);
    });

    it('shows the change when the store cannot be read after it', async () => {
      InclamoAPI.performAction.mockResolvedValue(accepted);
      InclamoAPI.marks.mockRejectedValue(new Error('timeout'));
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue('address-confirmed');
      await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
      await flush();

      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority', 'address-confirmed']);
      expect(has(wrapper, 'inclamo-order-marks-message')).toBe(false);
    });

    it('edits the order note starting from the note the store holds now', async () => {
      InclamoAPI.marks
        .mockResolvedValueOnce(storeHolds(['gift', 'priority'], 'Leave at the side door'))
        .mockResolvedValueOnce(storeHolds(['gift', 'priority'], 'Customer asked for delivery after 6 pm'));
      InclamoAPI.performAction.mockResolvedValue(accepted);
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-note-edit"]').trigger('click');
      await flush();
      const input = wrapper.find('[data-testid="inclamo-order-note-input"]');
      expect(input.element.value).toBe('Leave at the side door');

      await input.setValue('Customer asked for delivery after 6 pm');
      await wrapper.find('[data-testid="inclamo-order-note-save"]').trigger('click');
      await flush();

      expect(lastPayload()).toEqual({
        action_name: 'order_note',
        order_id: 'gid://shopify/Order/1',
        note: 'Customer asked for delivery after 6 pm',
        action_id: expect.any(String),
      });
      expect(has(wrapper, 'inclamo-order-note-input')).toBe(false);
      expect(wrapper.find('[data-testid="inclamo-order-note"]').text()).toBe('Customer asked for delivery after 6 pm');
    });

    it('adds a customer tag and edits the customer note by the customer id', async () => {
      InclamoAPI.performAction.mockResolvedValue(accepted);
      InclamoAPI.marks.mockResolvedValue(storeHolds(['VIP', 'wholesale'], 'Pays by invoice'));
      const wrapper = await section(matched());

      await wrapper.find('[data-testid="inclamo-customer-tag-input"]').setValue('vip');
      await wrapper.find('[data-testid="inclamo-customer-tag-form"]').trigger('submit');
      await flush();

      expect(lastPayload()).toMatchObject({ action_name: 'customer_tags', customer_id: 'gid://shopify/Customer/1', params: { operation: 'add', tag: 'vip' } });
      expect(lastPayload()).not.toHaveProperty('order_id');
      expect(InclamoAPI.marks).toHaveBeenCalledWith(7, { customer_id: 'gid://shopify/Customer/1' });
      expect(texts(wrapper, 'inclamo-customer-tag')).toEqual(['VIP', 'wholesale']);

      InclamoAPI.marks.mockResolvedValue(storeHolds(['VIP', 'wholesale'], 'Prefers phone calls'));
      await wrapper.find('[data-testid="inclamo-customer-note-edit"]').trigger('click');
      await flush();
      await wrapper.find('[data-testid="inclamo-customer-note-input"]').setValue('Prefers phone calls');
      await wrapper.find('[data-testid="inclamo-customer-note-save"]').trigger('click');
      await flush();

      expect(lastPayload()).toMatchObject({ action_name: 'customer_note', customer_id: 'gid://shopify/Customer/1', note: 'Prefers phone calls' });
      expect(wrapper.find('[data-testid="inclamo-customer-note"]').text()).toBe('Prefers phone calls');
    });
  });

  describe('refusals', () => {
    const editableCard = () => card({ order: tagged, connection: scoped(), canChangeMarks: true });

    it("shows the store's reason when it refuses a tag, and keeps the tags as they were", async () => {
      InclamoAPI.performAction.mockResolvedValue(refused('store_refused', 'Order tags is invalid'));
      const wrapper = editableCard();
      const long = 'x'.repeat(300);

      await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue(long);
      await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
      await flush();

      expect(wrapper.find('[data-testid="inclamo-order-marks-message"]').text()).toBe('Shopify refused: Order tags is invalid');
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
      expect(wrapper.find('[data-testid="inclamo-order-tag-input"]').element.value).toBe(long);
      expect(InclamoAPI.marks).not.toHaveBeenCalled();
    });

    it("keeps the old note when the store refuses the new one, and the editor holds the agent's text", async () => {
      InclamoAPI.marks.mockResolvedValue(storeHolds(['gift', 'priority'], 'Leave at the door'));
      InclamoAPI.performAction.mockResolvedValue(refused('store_refused', 'Note is too long (maximum is 5000 characters)'));
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-note-edit"]').trigger('click');
      await flush();
      await wrapper.find('[data-testid="inclamo-order-note-input"]').setValue('y'.repeat(6000));
      await wrapper.find('[data-testid="inclamo-order-note-save"]').trigger('click');
      await flush();

      expect(wrapper.find('[data-testid="inclamo-order-marks-message"]').text()).toBe('Shopify refused: Note is too long (maximum is 5000 characters)');
      expect(wrapper.find('[data-testid="inclamo-order-note-input"]').element.value).toHaveLength(6000);

      await wrapper.find('[data-testid="inclamo-order-note-cancel"]').trigger('click');
      expect(wrapper.find('[data-testid="inclamo-order-note"]').text()).toBe('Leave at the door');
    });

    it.each([
      ['tag_has_comma', 'A tag cannot contain a comma.'],
      ['not_allowed', 'An administrator has not allowed you to perform this action.'],
      ['store_unreachable', 'Shopify did not answer. Nothing was changed.'],
      ['connection_broken', 'The action could not be performed.'],
    ])('explains the refusal %s in words', async (refusal, words) => {
      InclamoAPI.performAction.mockResolvedValue(refused(refusal, refusal === 'store_unreachable' ? 'timeout' : null));
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-tag-input"]').setValue('a,b');
      await wrapper.find('[data-testid="inclamo-order-tag-form"]').trigger('submit');
      await flush();

      expect(wrapper.find('[data-testid="inclamo-order-marks-message"]').text()).toBe(words);
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
    });

    it('says the outcome is unknown when Shopify does not answer', async () => {
      InclamoAPI.performAction.mockRejectedValue(new Error('Network Error'));
      const wrapper = editableCard();

      await wrapper.findAll('[data-testid="inclamo-order-tag-remove"]')[0].trigger('click');
      await flush();

      expect(wrapper.find('[data-testid="inclamo-order-marks-message"]').text()).toBe(
        'Shopify did not confirm the change. Check it in Shopify before trying again.'
      );
      expect(texts(wrapper, 'inclamo-order-tag')).toEqual(['gift', 'priority']);
    });

    it('does not open the note editor when the current note cannot be read', async () => {
      InclamoAPI.marks.mockRejectedValue(new Error('bad gateway'));
      const wrapper = editableCard();

      await wrapper.find('[data-testid="inclamo-order-note-edit"]').trigger('click');
      await flush();

      expect(has(wrapper, 'inclamo-order-note-input')).toBe(false);
      expect(wrapper.find('[data-testid="inclamo-order-marks-message"]').text()).toBe('The current note could not be read from Shopify. Try again.');
      expect(InclamoAPI.performAction).not.toHaveBeenCalled();
    });
  });
});
