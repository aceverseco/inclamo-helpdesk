// Order variables in Chatwoot's own variable list and reply box, through the
// reply variables seam (patches/0003-reply-variables.patch).
import { mount, shallowMount, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { getUndefinedVariablesInMessage } from '@chatwoot/utils';
import VariableList from 'dashboard/components/widgets/conversation/VariableList.vue';
import ReplyBox from 'dashboard/components/widgets/conversation/ReplyBox.vue';
import { getReplyVariables, resolveVariablesInMessage } from 'dashboard/helper/editorHelper';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import registry from 'dashboard/extensions/replyVariables';
import OrdersSection from '../components/OrdersSection.vue';
import InclamoAPI from '../api';
import { clearCommerce } from '../widgets/commerce';
import { ORDER_VARIABLES } from '../replyVariables';
import { notePanel, forgetOrderState } from '../orderState';
import { stubs, order, connection, allowedAgent, flush } from './helpers';

vi.mock('../api', () => ({ default: { url: '/api/v1/accounts/1/inclamo', getConnection: vi.fn(), getPanel: vi.fn() } }));
// A list left mounted would ask about the connection again in the next test.
enableAutoUnmount(afterEach);

const VARIABLES = {
  number: '#1042',
  date: 'November 5, 2026',
  total: '54.00 EUR',
  payment_status: 'Paid',
  fulfillment_status: 'Shipped',
  tracking_number: 'A1',
  tracking_link: 'https://example.com/track/A1',
  status_link: 'https://shop.example.com/orders/status',
  items: '2 × Blue Mug\n1 × Red Plate',
};
const tied = (overrides = {}) => order({ number: '#1042', variables: { ...VARIABLES, ...overrides } });
const panel = (overrides = {}) => ({ state: 'none', viewer: allowedAgent, connection: connection(), orders: [], marked_order: null, open_actions: [], ...overrides });
const conversation = (attributes = {}) => ({ id: 7, inbox_id: 1, can_reply: true, status: 'open', meta: { sender: { id: 2, name: 'maya example' } }, messages: [], custom_attributes: attributes });
const user = { id: 7, name: 'Agent Smith', email: 'agent@example.com', accounts: [] };
const variablesFor = chat => getReplyVariables({ conversation: chat, contact: { name: 'maya example' }, inbox: {}, user });

const connected = async (data = connection()) => {
  InclamoAPI.getConnection.mockResolvedValue({ data });
  registry[0].variables();
  await flush();
};

const PickerStub = {
  name: 'CaretAnchoredPicker',
  props: ['items'],
  template: '<ul><li v-for="item in items" :key="item.id" data-testid="variable">{{ item.label }} | {{ item.subtitle }}</li></ul>',
};
const list = () => {
  const store = createStore({ getters: { 'attributes/getAttributes': () => [] } });
  return mount(VariableList, { props: { variables: {} }, global: { plugins: [store], stubs: { CaretAnchoredPicker: PickerStub } } });
};
const offered = wrapper => wrapper.findAll('[data-testid="variable"]').map(item => item.text());

// Chatwoot's reply box with the store its own test gives it.
const replyBox = chat => {
  const send = vi.fn();
  const confirm = vi.fn().mockResolvedValue(false);
  const store = createStore({
    state: { chat },
    actions: { 'draftMessages/setReplyEditorMode': () => {}, 'draftMessages/set': () => {}, createPendingMessageAndSend: send },
    getters: {
      getSelectedChat: state => state.chat,
      getCurrentUser: () => user,
      getCurrentAccountId: () => 1,
      getMessageSignature: () => '',
      getUISettings: () => ({}),
      getLastEmailInSelectedChat: () => null,
      'globalConfig/get': () => ({}),
      'globalConfig/isMetaMessageSendingDisabled': () => false,
      'inboxes/getInbox': () => id => ({ id, channel_type: 'Channel::Api' }),
      'inboxes/getWhatsAppTemplates': () => () => [],
      'contacts/getContact': () => () => ({}),
      'draftMessages/get': () => () => '',
      'draftMessages/getReplyEditorMode': () => REPLY_EDITOR_MODES.REPLY,
      'accounts/isFeatureEnabledonAccount': () => () => false,
      'accounts/getAccount': () => () => ({}),
      'portals/allPortals': () => [],
      'integrations/getUIFlags': () => ({ isFetching: false }),
    },
  });
  const wrapper = shallowMount(ReplyBox, {
    global: {
      plugins: [store],
      mocks: { $t: (key, params) => (params ? `${key} ${Object.values(params).join(' ')}` : key) },
      stubs: { transition: false, 'woot-confirm-modal': { template: '<div />', methods: { showConfirmation: confirm } } },
    },
  });
  return { wrapper, send, confirm };
};

// The panel store keeps answers between mounts; every test starts empty.
beforeEach(() => clearCommerce());

describe('order variables in replies', () => {
  beforeEach(() => {
    forgetOrderState();
    vi.clearAllMocks();
  });

  describe('the variable list', () => {
    it('offers the order variables with their descriptions when a store is connected', async () => {
      await connected();

      const items = offered(list());

      expect(items).toContain('{{contact.name}} | Contact name');
      expect(items).toContain('{{order.number}} | Order number');
      expect(items).toContain('{{order.tracking_link}} | Tracking link of the first shipment');
      ORDER_VARIABLES.forEach(name => expect(items.some(item => item.startsWith(`{{order.${name}}} | `) && item.length > `{{order.${name}}} | `.length)).toBe(true));
    });

    it('offers them as soon as the answer about the connection arrives', async () => {
      InclamoAPI.getConnection.mockResolvedValue({ data: connection() });
      const wrapper = list();
      expect(offered(wrapper).some(item => item.includes('order.'))).toBe(false);

      await flush();

      expect(offered(wrapper)).toContain('{{order.number}} | Order number');
      expect(InclamoAPI.getConnection).toHaveBeenCalledTimes(1);
    });

    it('holds no order variables without a store connection', async () => {
      await connected({ connected: false, encryption_configured: true });

      const items = offered(list());

      expect(items).toContain('{{contact.name}} | Contact name');
      expect(items.some(item => item.includes('order.'))).toBe(false);
    });

    it('holds none while the connection is broken, or when the question fails', async () => {
      await connected(connection({ status: 'broken' }));
      expect(offered(list()).some(item => item.includes('order.'))).toBe(false);

      forgetOrderState();
      InclamoAPI.getConnection.mockRejectedValue(new Error('network'));
      registry[0].variables();
      await flush();
      expect(offered(list()).some(item => item.includes('order.'))).toBe(false);
    });
  });

  describe('the values the editor resolves', () => {
    beforeEach(() => connected());

    it('are those of the tied order the panel loaded', () => {
      notePanel(7, panel({ marked_order: tied() }));

      const variables = variablesFor(conversation());

      ORDER_VARIABLES.forEach(name => expect(variables[`order.${name}`]).toBe(VARIABLES[name]));
      expect(resolveVariablesInMessage('Your order {{order.number}} is on its way: {{order.tracking_link}}', variables)).toBe(
        'Your order #1042 is on its way: https://example.com/track/A1'
      );
      expect(variables['contact.name']).toBe('Maya Example');
    });

    it('leave a placeholder, without a warning, for what the order does not have', () => {
      notePanel(7, panel({ marked_order: tied({ tracking_number: '', tracking_link: '' }) }));
      const variables = variablesFor(conversation());
      const message = resolveVariablesInMessage('{{order.number}}: {{order.tracking_number}}', variables);

      expect(message).toBe('#1042: {{order.tracking_number}}');
      expect(getUndefinedVariablesInMessage({ message, variables })).toEqual([]);
    });

    it('are left to the server, without a warning, while the panel has not been read', () => {
      const variables = variablesFor(conversation());
      const message = resolveVariablesInMessage('Order {{order.number}}', variables);

      expect(message).toBe('Order {{order.number}}');
      expect(getUndefinedVariablesInMessage({ message, variables })).toEqual([]);
    });

    it('are those of the newest order of the customer when none is tied', () => {
      const newest = order({ id: 'gid://shopify/Order/9', number: '#1043', variables: { ...VARIABLES, number: '#1043', fulfillment_status: 'Not shipped' } });
      notePanel(7, panel({ state: 'matched', orders: [newest, tied()] }));

      const variables = variablesFor(conversation());

      expect(variables['order.number']).toBe('#1043');
      expect(variables['order.fulfillment_status']).toBe('Not shipped');
    });

    it('prefer the tied order to the newest one', () => {
      const newest = order({ id: 'gid://shopify/Order/9', number: '#1043', variables: { ...VARIABLES, number: '#1043' } });
      notePanel(7, panel({ state: 'matched', orders: [newest, tied()], marked_order: tied() }));

      expect(variablesFor(conversation())['order.number']).toBe('#1042');
    });

    it('are absent when the panel found neither a tied order nor a customer with orders', () => {
      notePanel(7, panel());
      expect(Object.keys(variablesFor(conversation())).some(key => key.startsWith('order.'))).toBe(false);

      notePanel(7, panel({ state: 'matched', orders: [] }));
      expect(Object.keys(variablesFor(conversation())).some(key => key.startsWith('order.'))).toBe(false);
    });

    it('are kept when the store did not answer the panel', () => {
      notePanel(7, panel({ marked_order: tied() }));
      notePanel(7, { state: 'unavailable', viewer: allowedAgent, connection: connection() });

      expect(variablesFor(conversation())['order.number']).toBe('#1042');
    });

    it('belong to their conversation only', () => {
      notePanel(7, panel({ marked_order: tied() }));

      expect(variablesFor(conversation())['order.number']).toBe('#1042');
      // Another conversation, not read yet: left to the server.
      expect(variablesFor({ ...conversation(), id: 8 })['order.number']).toBe('');
    });

    it('come from what the Orders section loads', async () => {
      InclamoAPI.getPanel.mockResolvedValue({ data: panel({ marked_order: tied() }) });
      mount(OrdersSection, { props: { conversationId: 7 }, global: { stubs } });
      await flush();

      expect(variablesFor(conversation())['order.total']).toBe('54.00 EUR');
    });
  });

  describe('the reply box', () => {
    beforeEach(() => connected());

    it('warns before sending that order.number has no value when the panel found no order', async () => {
      notePanel(7, panel());
      const { wrapper, send, confirm } = replyBox(conversation());
      wrapper.vm.message = 'Your order {{order.number}} is on its way';

      await wrapper.vm.onSendReply();

      expect(confirm).toHaveBeenCalledTimes(1);
      expect(wrapper.vm.undefinedVariableMessage).toContain('order.number');
      expect(send).not.toHaveBeenCalled();
    });

    it('sends without a warning when an order is tied', async () => {
      notePanel(7, panel({ marked_order: tied() }));
      const { wrapper, send, confirm } = replyBox(conversation());
      wrapper.vm.message = 'Your order {{order.tracking_number}} is on its way';

      await wrapper.vm.onSendReply();
      await flush();

      expect(confirm).not.toHaveBeenCalled();
      expect(send).toHaveBeenCalledTimes(1);
    });
  });
});
