import { h } from 'vue';
import { mount } from '@vue/test-utils';
import ShopperRequestSection from '../components/ShopperRequestSection.vue';
import sidebarSections from '../sidebarSections';
import { shopperRequestsApi } from '../shopperRequests';
import { dateTime } from '../format';
import { stubs, flush } from './helpers';

vi.mock('../api', () => ({ default: { getConversationSla: vi.fn() } }));
vi.mock('../shopperRequests', async importOriginal => {
  const original = await importOriginal();
  return { ...original, shopperRequestsApi: { read: vi.fn(), act: vi.fn() } };
});

// The dashboard's store, reduced to what the card reads.
const storeWith = conversations => ({
  getters: {
    getConversationById: id => conversations.find(conversation => conversation.id === Number(id)),
    getCurrentAccountId: 3,
  },
});
const dashboard = { store: storeWith([]) };
vi.mock('dashboard/composables/store', () => ({ useStore: () => dashboard.store }));

const RouterLinkStub = { name: 'RouterLink', props: ['to'], template: '<a :href="to"><slot /></a>' };

const erasure = (overrides = {}) => ({
  id: 41,
  kind: 'shopper_erasure',
  state: 'waiting',
  conversation_id: 7,
  received_at: '2026-11-20T10:00:00Z',
  delete_after: '2099-12-04T10:00:00Z',
  overdue: false,
  email: 'pat@example.com',
  phone: '+15556251199',
  contacts: [{ id: 15, name: 'Pat Example', conversations: 2 }],
  hold: null,
  done: null,
  ...overrides,
});
const dataRequest = (overrides = {}) => erasure({ id: 42, kind: 'shopper_data_request', delete_after: null, ...overrides });
const doneBy = (by, extra = {}) => ({
  state: 'done',
  email: null,
  phone: null,
  contacts: [],
  done: { at: '2026-11-22T10:00:00Z', by, user: by === 'team' ? { id: 1, name: 'Alex Example' } : null },
  ...extra,
});

const show = async (card, id = 7) => {
  dashboard.store = storeWith([{ id: 7, custom_attributes: { inclamo_shopper_request_id: card.id } }]);
  shopperRequestsApi.read.mockResolvedValue({ data: card });
  const wrapper = mount(ShopperRequestSection, { props: { conversationId: id }, global: { stubs: { ...stubs, RouterLink: RouterLinkStub } } });
  await flush();
  return wrapper;
};
const part = (wrapper, name) => wrapper.find(`[data-testid="inclamo-shopper-request-${name}"]`);
const actionsOf = wrapper =>
  ['delete', 'hold', 'lift', 'answered'].filter(action => part(wrapper, action).exists());

describe('ShopperRequestSection', () => {
  beforeEach(() => {
    shopperRequestsApi.read.mockReset();
    shopperRequestsApi.act.mockReset();
  });

  describe('an erasure', () => {
    it('waiting: shows the shopper\'s email and phone, the contacts found with links, the date, and Delete and Hold', async () => {
      const wrapper = await show(erasure());

      expect(shopperRequestsApi.read).toHaveBeenCalledWith(41);
      expect(part(wrapper, 'kind').text()).toBe("Shopify asked to erase one shopper's data");
      expect(wrapper.text()).toContain('Only administrators see the inbox «Data requests».');
      expect(part(wrapper, 'state').text()).toContain('Waiting');
      expect(part(wrapper, 'email').text()).toContain('pat@example.com');
      expect(part(wrapper, 'phone').text()).toContain('+15556251199');
      expect(part(wrapper, 'date').text()).toContain('Deleted automatically on');
      expect(part(wrapper, 'date').text()).toContain(dateTime('2099-12-04T10:00:00Z'));
      const link = part(wrapper, 'contact-15');
      expect(link.attributes('href')).toBe('/app/accounts/3/contacts/15');
      expect(link.text()).toBe('Pat Example, conversations: 2');
      expect(actionsOf(wrapper)).toEqual(['delete', 'hold']);
      expect(part(wrapper, 'delete').text()).toBe('Delete');
      expect(part(wrapper, 'hold').text()).toBe('Hold');
      expect(part(wrapper, 'held').exists()).toBe(false);
      expect(part(wrapper, 'overdue').exists()).toBe(false);
    });

    it('waiting with nothing matching now, and overdue', async () => {
      const wrapper = await show(erasure({ contacts: [], phone: null, overdue: true }));

      expect(part(wrapper, 'contacts').text()).toContain('No contact matches now.');
      expect(part(wrapper, 'phone').text()).toContain('Not given');
      expect(part(wrapper, 'overdue').text()).toContain("Shopify's deadline has passed");
    });

    it('held: shows who held it, when and why, the date before the hold, and Delete and Lift hold', async () => {
      const wrapper = await show(
        erasure({ state: 'held', hold: { reason: 'open payment dispute', held_at: '2026-11-21T09:00:00Z', held_by: { id: 1, name: 'Alex Example' } } })
      );

      expect(part(wrapper, 'state').text()).toContain('On hold');
      expect(part(wrapper, 'held').text()).toContain(`Held by Alex Example on ${dateTime('2026-11-21T09:00:00Z')}`);
      expect(part(wrapper, 'held-reason').text()).toBe('Reason: open payment dispute');
      expect(part(wrapper, 'date').text()).toContain('Date before the hold');
      expect(actionsOf(wrapper)).toEqual(['delete', 'lift']);
      expect(part(wrapper, 'lift').text()).toBe('Lift hold');
    });

    it('done by an administrator: says who and when, renders no email or phone, and offers nothing', async () => {
      const wrapper = await show(erasure(doneBy('team')));

      expect(part(wrapper, 'state').text()).toContain('Done');
      expect(part(wrapper, 'done').text()).toContain(`Done by Alex Example on ${dateTime('2026-11-22T10:00:00Z')}`);
      expect(part(wrapper, 'email').exists()).toBe(false);
      expect(part(wrapper, 'phone').exists()).toBe(false);
      expect(wrapper.text()).not.toContain('pat@example.com');
      expect(wrapper.text()).not.toContain('5556251199');
      expect(actionsOf(wrapper)).toEqual([]);
    });

    it('done automatically: says so, and renders no email or phone even if they were sent', async () => {
      const wrapper = await show(erasure(doneBy('automatic', { email: 'pat@example.com', phone: '+15556251199' })));

      expect(part(wrapper, 'done').text()).toContain(`Deleted automatically on ${dateTime('2026-11-22T10:00:00Z')}`);
      expect(wrapper.text()).not.toContain('pat@example.com');
      expect(wrapper.text()).not.toContain('5556251199');
    });
  });

  describe('a data request', () => {
    it('waiting: shows the shopper and the contacts, no date, and Mark answered only', async () => {
      const wrapper = await show(dataRequest());

      expect(part(wrapper, 'kind').text()).toBe('A shopper asked for a copy of their data');
      expect(part(wrapper, 'email').text()).toContain('pat@example.com');
      expect(part(wrapper, 'date').exists()).toBe(false);
      expect(part(wrapper, 'contact-15').exists()).toBe(true);
      expect(actionsOf(wrapper)).toEqual(['answered']);
      expect(part(wrapper, 'answered').text()).toBe('Mark answered');
    });

    it('done: says who answered, renders no email or phone, and offers nothing', async () => {
      const wrapper = await show(dataRequest(doneBy('team')));

      expect(part(wrapper, 'done').text()).toContain('Done by Alex Example');
      expect(wrapper.text()).not.toContain('pat@example.com');
      expect(actionsOf(wrapper)).toEqual([]);
    });
  });

  describe('the actions', () => {
    it('Delete asks first, naming the numbers, and acts only on confirmation', async () => {
      const wrapper = await show(erasure({ contacts: [{ id: 15, name: 'Pat', conversations: 2 }, { id: 16, name: 'Pat 2', conversations: 1 }] }));
      shopperRequestsApi.act.mockResolvedValue({ data: erasure(doneBy('team')) });

      await part(wrapper, 'delete').trigger('click');

      const dialog = part(wrapper, 'delete-dialog');
      expect(dialog.text()).toContain('Contacts: 2. Conversations: 3.');
      expect(dialog.text()).toContain('This cannot be undone.');
      expect(shopperRequestsApi.act).not.toHaveBeenCalled();
      await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
      await flush();
      expect(shopperRequestsApi.act).toHaveBeenCalledWith(41, 'delete', {});
      expect(part(wrapper, 'done').text()).toContain('Done by Alex Example');
      expect(wrapper.text()).not.toContain('pat@example.com');
    });

    it('Hold needs a reason: without one it cannot be confirmed, and the reason is sent as written', async () => {
      const wrapper = await show(erasure());
      shopperRequestsApi.act.mockResolvedValue({
        data: erasure({ state: 'held', hold: { reason: 'open payment dispute', held_at: '2026-11-21T09:00:00Z', held_by: { id: 1, name: 'Alex Example' } } }),
      });

      await part(wrapper, 'hold').trigger('click');
      const confirm = () => wrapper.find('[data-testid="dialog-confirm"]');
      expect(confirm().attributes('disabled')).toBeDefined();
      await part(wrapper, 'reason').setValue('   ');
      expect(confirm().attributes('disabled')).toBeDefined();
      await confirm().trigger('click');
      expect(shopperRequestsApi.act).not.toHaveBeenCalled();

      await part(wrapper, 'reason').setValue('  open payment dispute ');
      expect(confirm().attributes('disabled')).toBeUndefined();
      await confirm().trigger('click');
      await flush();

      expect(shopperRequestsApi.act).toHaveBeenCalledWith(41, 'hold', { reason: 'open payment dispute' });
      expect(part(wrapper, 'held-reason').text()).toBe('Reason: open payment dispute');
    });

    it('Lift hold says when the data is deleted: on the date, or at the next daily run once it has passed', async () => {
      const held = { state: 'held', hold: { reason: 'r', held_at: '2026-11-21T09:00:00Z', held_by: null } };
      let wrapper = await show(erasure(held));
      await part(wrapper, 'lift').trigger('click');
      expect(part(wrapper, 'lift-dialog').text()).toContain(`deleted automatically on ${dateTime('2099-12-04T10:00:00Z')}`);

      wrapper = await show(erasure({ ...held, delete_after: '2020-01-01T00:00:00Z' }));
      await part(wrapper, 'lift').trigger('click');
      expect(part(wrapper, 'lift-dialog').text()).toContain('next daily run');
    });

    it('Mark answered asks first', async () => {
      const wrapper = await show(dataRequest());
      shopperRequestsApi.act.mockResolvedValue({ data: dataRequest(doneBy('team')) });

      await part(wrapper, 'answered').trigger('click');
      expect(part(wrapper, 'answered-dialog').text()).toContain('email and phone are then removed');
      await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
      await flush();

      expect(shopperRequestsApi.act).toHaveBeenCalledWith(42, 'answered', {});
      expect(actionsOf(wrapper)).toEqual([]);
    });

    it('says why an action was refused, and reads the request again when it changed meanwhile', async () => {
      const wrapper = await show(erasure());
      shopperRequestsApi.act.mockRejectedValue({ response: { status: 409, data: { error: 'wrong_state', state: 'done' } } });
      shopperRequestsApi.read.mockResolvedValue({ data: erasure(doneBy('automatic')) });

      await part(wrapper, 'delete').trigger('click');
      await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
      await flush();
      await flush();

      expect(part(wrapper, 'delete-dialog').text()).toContain('The request has changed meanwhile');
      expect(shopperRequestsApi.read).toHaveBeenCalledTimes(2);
      expect(part(wrapper, 'done').text()).toContain('Deleted automatically');
    });
  });

  it('tells a user who may not open the request so', async () => {
    dashboard.store = storeWith([{ id: 7, custom_attributes: { inclamo_shopper_request_id: 41 } }]);
    shopperRequestsApi.read.mockRejectedValue({ response: { status: 403, data: { error: 'forbidden' } } });
    const wrapper = mount(ShopperRequestSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();

    expect(part(wrapper, 'failed').text()).toContain('Only an administrator of this account');
  });

  it('shows nothing for a conversation that is not such a ticket', async () => {
    dashboard.store = storeWith([{ id: 7, custom_attributes: {} }]);
    const wrapper = mount(ShopperRequestSection, { props: { conversationId: 7 }, global: { stubs } });
    await flush();

    expect(wrapper.find('[data-testid="inclamo-shopper-request"]').exists()).toBe(false);
    expect(shopperRequestsApi.read).not.toHaveBeenCalled();
  });

  describe('in the sidebar', () => {
    const entry = () => sidebarSections.find(section => section.name === 'inclamo_shopper_request');
    const visibleFor = (id, conversations) =>
      mount({ render: () => h('span', entry().visible(id) ? 'shown' : 'hidden') }, { global: { mocks: { $store: storeWith(conversations) } } }).text();

    it('is a section of its own, titled in the interface language', () => {
      expect(entry()).toMatchObject({ openKey: 'is_inclamo_shopper_request_open', component: ShopperRequestSection });
      expect(entry().title()).toBe('Data request');
    });

    it('is shown on a ticket about a shopper\'s data and on no other conversation', () => {
      const conversations = [
        { id: 7, custom_attributes: { inclamo_shopper_request_id: 41 } },
        { id: 8, custom_attributes: { inclamo_call_outcome: 'resolved' } },
        { id: 9 },
      ];

      expect(visibleFor(7, conversations)).toBe('shown');
      expect(visibleFor(8, conversations)).toBe('hidden');
      expect(visibleFor(9, conversations)).toBe('hidden');
      expect(visibleFor(10, conversations)).toBe('hidden');
    });
  });
});
