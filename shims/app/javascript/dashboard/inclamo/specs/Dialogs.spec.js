import { mount } from '@vue/test-utils';
import CancelDialog from '../components/CancelDialog.vue';
import RefundDialog from '../components/RefundDialog.vue';
import AddressDialog from '../components/AddressDialog.vue';
import ReplacementDialog from '../components/ReplacementDialog.vue';
import ConnectDialog from '../components/ConnectDialog.vue';
import OrderRolesPage from '../components/OrderRolesPage.vue';
import InclamoAPI from '../api';
import { stubs, order, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    performAction: vi.fn(),
    refundPreview: vi.fn(),
    connect: vi.fn(),
    getRoles: vi.fn(),
    giveRole: vi.fn(),
    takeRole: vi.fn(),
  },
}));

const open = async (component, props = {}, argument) => {
  const wrapper = mount(component, { props: { conversationId: 7, order: order(), ...props }, global: { stubs } });
  await wrapper.vm.open(argument);
  await flush();
  return wrapper;
};
const confirm = async wrapper => {
  await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
  await flush();
};
const sent = () => InclamoAPI.performAction.mock.calls.at(-1)[1];
const accepted = { data: { outcome: 'accepted', action: 'x' } };

describe('CancelDialog', () => {
  it('says that cancelling cannot be undone and sends the choices with one action id', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(CancelDialog);

    expect(wrapper.find('[data-testid="dialog-title"]').text()).toContain('#1001');
    expect(wrapper.find('[data-testid="inclamo-cancel-warning"]').text()).toContain('cannot be undone');
    await wrapper.find('[data-testid="inclamo-cancel-reason"]').setValue('INVENTORY');
    await confirm(wrapper);

    expect(InclamoAPI.performAction).toHaveBeenCalledTimes(1);
    expect(sent()).toMatchObject({ action_name: 'cancel', order_id: 'gid://shopify/Order/1', params: { reason: 'INVENTORY', refund: true, restock: true, notify: false } });
    expect(sent().action_id).toMatch(/^[A-Za-z0-9-]{8,64}$/);
    expect(wrapper.emitted('done')).toHaveLength(1);
    expect(wrapper.find('[data-testid="dialog"]').exists()).toBe(false);
  });

  it('shows the reason of the store when it refuses, and stays open', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'refused', refusal: 'store_refused', store_message: 'Cannot cancel an order with an active return' } });
    const wrapper = await open(CancelDialog);
    await confirm(wrapper);

    expect(wrapper.find('[data-testid="inclamo-action-message"]').text()).toContain('Cannot cancel an order with an active return');
    expect(wrapper.emitted('done')).toBeUndefined();
  });

  it('reports an unknown outcome as unknown and does not let the same dialog act again', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'unknown' } });
    const wrapper = await open(CancelDialog);
    await confirm(wrapper);

    expect(wrapper.find('[data-testid="inclamo-action-message"]').text()).toContain('outcome is unknown');
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
    await confirm(wrapper);
    expect(InclamoAPI.performAction).toHaveBeenCalledTimes(1);
  });

  it('keeps the same action id when the request got no answer, so a retry cannot act twice', async () => {
    InclamoAPI.performAction.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce(accepted);
    const wrapper = await open(CancelDialog);
    await confirm(wrapper);
    const first = InclamoAPI.performAction.mock.calls[0][1].action_id;
    await confirm(wrapper);

    expect(InclamoAPI.performAction.mock.calls[1][1].action_id).toBe(first);
  });

  it('says a cancellation is still running', async () => {
    InclamoAPI.performAction.mockResolvedValue({ data: { outcome: 'running' } });
    const wrapper = await open(CancelDialog);
    await confirm(wrapper);

    expect(wrapper.find('[data-testid="inclamo-action-message"]').text()).toContain('still working');
    expect(wrapper.emitted('done')).toHaveLength(1);
  });
});

describe('RefundDialog', () => {
  const preview = { data: { amount: '20.0', currency: 'EUR', maximum: '54.0', destinations: [{ gateway: 'Visa', amount: '20.0' }], restocked_items: 0, notify: false } };

  it('refuses an amount above the refundable in the form, without asking the store', async () => {
    const wrapper = await open(RefundDialog);
    await wrapper.find('[data-testid="inclamo-refund-mode-amount"]').setValue();
    await wrapper.find('[data-testid="inclamo-refund-amount"]').setValue('60');

    expect(wrapper.find('[data-testid="inclamo-refund-above"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-refund-calculate"]').attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
    expect(InclamoAPI.refundPreview).not.toHaveBeenCalled();
    expect(InclamoAPI.performAction).not.toHaveBeenCalled();
  });

  it('shows the amount and where the money goes before it can be confirmed', async () => {
    InclamoAPI.refundPreview.mockResolvedValue(preview);
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(RefundDialog);
    await wrapper.find('[data-testid="inclamo-refund-mode-amount"]').setValue();
    await wrapper.find('[data-testid="inclamo-refund-amount"]').setValue('20');
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();

    await wrapper.find('[data-testid="inclamo-refund-calculate"]').trigger('click');
    await flush();

    expect(InclamoAPI.refundPreview).toHaveBeenCalledWith(7, 'gid://shopify/Order/1', { mode: 'amount', restock: false, notify: false, amount: '20' });
    const summary = wrapper.find('[data-testid="inclamo-refund-preview"]').text();
    expect(summary).toContain('20');
    expect(summary).toContain('Visa');

    await confirm(wrapper);
    expect(sent()).toMatchObject({ action_name: 'refund', params: { mode: 'amount', amount: '20' } });
    expect(wrapper.emitted('done')).toHaveLength(1);
  });

  it('asks for the calculation again when the amount changes', async () => {
    InclamoAPI.refundPreview.mockResolvedValue(preview);
    const wrapper = await open(RefundDialog);
    await wrapper.find('[data-testid="inclamo-refund-mode-amount"]').setValue();
    await wrapper.find('[data-testid="inclamo-refund-amount"]').setValue('20');
    await wrapper.find('[data-testid="inclamo-refund-calculate"]').trigger('click');
    await flush();

    await wrapper.find('[data-testid="inclamo-refund-amount"]').setValue('25');

    expect(wrapper.find('[data-testid="inclamo-refund-preview"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
  });

  const returning = extra => ({ data: { ...preview.data, restocked_items: 1, restock_locations: [], left_out_items: 0, ...extra } });
  const calculateWithRestock = async wrapper => {
    await wrapper.find('[data-testid="inclamo-refund-restock"]').setValue(true);
    await wrapper.find('[data-testid="inclamo-refund-calculate"]').trigger('click');
    await flush();
  };

  it('names where the items go back, and asks the agent for nothing more', async () => {
    InclamoAPI.refundPreview.mockResolvedValue(returning({ restock_locations: ['Shop location'] }));
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(RefundDialog);
    await calculateWithRestock(wrapper);

    expect(wrapper.find('[data-testid="inclamo-refund-location"]').text()).toContain('Shop location');
    expect(wrapper.find('select').exists()).toBe(false);
    await confirm(wrapper);
    expect(sent().params).toEqual({ mode: 'full', restock: true, notify: false });
  });

  it('says that the items stay out of stock when the app cannot read locations', async () => {
    InclamoAPI.refundPreview.mockResolvedValue(returning({ restocked_items: 0, left_out_items: 1, missing_scopes: ['read_locations'] }));
    const wrapper = await open(RefundDialog);
    await calculateWithRestock(wrapper);

    expect(wrapper.find('[data-testid="inclamo-refund-left-out"]').text()).toContain('read_locations');
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeUndefined();
  });

  it('says how many items stay out of stock because the store names no location for them', async () => {
    InclamoAPI.refundPreview.mockResolvedValue(returning({ restocked_items: 1, restock_locations: ['Shop location'], unplaced_items: 2 }));
    const wrapper = await open(RefundDialog);
    await calculateWithRestock(wrapper);

    expect(wrapper.find('[data-testid="inclamo-refund-unplaced"]').text()).toContain('2');
    expect(wrapper.find('[data-testid="inclamo-refund-location"]').text()).toContain('Shop location');
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeUndefined();
  });
});

describe('AddressDialog', () => {
  it('starts from the current address and sends the new one apart from the recorded parameters', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(AddressDialog);

    expect(wrapper.find('[data-testid="inclamo-address-address1"]').element.value).toBe('1 Example Street');
    expect(wrapper.find('[data-testid="inclamo-address-first_name"]').element.value).toBe('Maya');
    expect(wrapper.find('[data-testid="inclamo-address-last_name"]').element.value).toBe('Example');

    await wrapper.find('[data-testid="inclamo-address-address1"]').setValue('2 Example Avenue');
    await wrapper.find('[data-testid="inclamo-address-zip"]').setValue('62702');
    await confirm(wrapper);

    expect(sent()).toMatchObject({ action_name: 'address', address: { address1: '2 Example Avenue', zip: '62702', city: 'Springfield', country_code: 'US' } });
    expect(sent().params).toBeUndefined();
  });

  it('starts from every field of the address, the company and a name of several words included, and sends a cleared field', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const current = { name: 'Mary Ann Example', first_name: 'Mary Ann', last_name: 'Example', company: 'Example Works', address1: '1 Example Street',
      address2: 'Floor 2', city: 'Springfield', province_code: 'IL', zip: '62701', country_code: 'US', phone: null };
    const wrapper = await open(AddressDialog, { order: order({ shipping_address: current }) });

    expect(wrapper.find('[data-testid="inclamo-address-first_name"]').element.value).toBe('Mary Ann');
    expect(wrapper.find('[data-testid="inclamo-address-last_name"]').element.value).toBe('Example');
    expect(wrapper.find('[data-testid="inclamo-address-company"]').element.value).toBe('Example Works');

    await wrapper.find('[data-testid="inclamo-address-address2"]').setValue('');
    await confirm(wrapper);

    expect(sent().address).toEqual({
      first_name: 'Mary Ann', last_name: 'Example', company: 'Example Works', address1: '1 Example Street', address2: '',
      city: 'Springfield', province_code: 'IL', zip: '62701', country_code: 'US', phone: '',
    });
  });

  it('cannot be confirmed without the street, the city and the country', async () => {
    const wrapper = await open(AddressDialog);
    await wrapper.find('[data-testid="inclamo-address-city"]').setValue('');

    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
  });
});

describe('ReplacementDialog', () => {
  it('starts from every item, lets the agent take away, and says the customer pays nothing', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(ReplacementDialog);

    const intro = wrapper.find('[data-testid="inclamo-replacement-intro"]').text();
    expect(intro).toContain('charged nothing');
    expect(intro).toContain('Stock is taken');
    expect(wrapper.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/1"]').element.value).toBe('2');

    await wrapper.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/1"]').setValue('1');
    await wrapper.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/2"]').setValue('0');
    await confirm(wrapper);

    expect(sent()).toMatchObject({ action_name: 'replacement', params: { items: [{ line_item_id: 'gid://shopify/LineItem/1', quantity: 1 }] } });
  });

  it('never sends more than the original quantity, and nothing when no item is kept', async () => {
    InclamoAPI.performAction.mockResolvedValue(accepted);
    const wrapper = await open(ReplacementDialog);
    await wrapper.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/1"]').setValue('9');
    await wrapper.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/2"]').setValue('0');
    await confirm(wrapper);
    expect(sent().params.items).toEqual([{ line_item_id: 'gid://shopify/LineItem/1', quantity: 2 }]);

    const empty = await open(ReplacementDialog);
    await empty.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/1"]').setValue('0');
    await empty.find('[data-testid="inclamo-replacement-quantity-gid://shopify/LineItem/2"]').setValue('0');
    expect(empty.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
  });
});

describe('ConnectDialog', () => {
  it('sends the domain with the client ID and secret, and reports the connection', async () => {
    InclamoAPI.connect.mockResolvedValue({ data: { connected: true } });
    const wrapper = await open(ConnectDialog);
    await wrapper.find('[data-testid="inclamo-connect-domain"]').setValue('example-store.myshopify.com');
    await wrapper.find('[data-testid="inclamo-connect-client-id"]').setValue('id');
    await wrapper.find('[data-testid="inclamo-connect-client-secret"]').setValue('secret');
    await confirm(wrapper);

    expect(InclamoAPI.connect).toHaveBeenCalledWith({ shop_domain: 'example-store.myshopify.com', client_id: 'id', client_secret: 'secret' });
    expect(wrapper.emitted('connected')).toHaveLength(1);
  });

  it('sends a legacy token instead when that kind is chosen', async () => {
    InclamoAPI.connect.mockResolvedValue({ data: { connected: true } });
    const wrapper = await open(ConnectDialog);
    await wrapper.find('[data-testid="inclamo-connect-domain"]').setValue('example-store.myshopify.com');
    await wrapper.find('[data-testid="inclamo-connect-kind-legacy_token"]').setValue();
    await wrapper.find('[data-testid="inclamo-connect-access-token"]').setValue('token');
    await confirm(wrapper);

    expect(InclamoAPI.connect).toHaveBeenCalledWith({ shop_domain: 'example-store.myshopify.com', access_token: 'token' });
  });

  it('shows what the server says when the store refuses, and saves nothing', async () => {
    InclamoAPI.connect.mockRejectedValue({ response: { data: { error: 'app_not_installed', message: 'The app must be installed on the store first.' } } });
    const wrapper = await open(ConnectDialog);
    await wrapper.find('[data-testid="inclamo-connect-domain"]').setValue('example-store.myshopify.com');
    await wrapper.find('[data-testid="inclamo-connect-client-id"]').setValue('id');
    await wrapper.find('[data-testid="inclamo-connect-client-secret"]').setValue('secret');
    await confirm(wrapper);

    expect(wrapper.find('[data-testid="inclamo-connect-error"]').text()).toBe('The app must be installed on the store first.');
    expect(wrapper.emitted('connected')).toBeUndefined();
  });

  it('shows the secret field as a password field and cannot be confirmed empty', async () => {
    const wrapper = await open(ConnectDialog);

    expect(wrapper.find('[data-testid="inclamo-connect-client-secret"]').attributes('type')).toBe('password');
    expect(wrapper.find('[data-testid="dialog-confirm"]').attributes('disabled')).toBeDefined();
  });
});

describe('OrderRolesPage', () => {
  const show = async () => {
    const wrapper = mount(OrderRolesPage, { global: { stubs } });
    await flush();
    return wrapper;
  };

  const members = [
    { user_id: 1, name: 'Ada Admin', email: 'ada@example.com', role: 'administrator', can_act: true, switchable: false },
    { user_id: 2, name: 'Ben Agent', email: 'ben@example.com', role: 'agent', can_act: false, switchable: true },
  ];

  it('lists who can act; administrators cannot be switched, agents can', async () => {
    InclamoAPI.getRoles.mockResolvedValue({ data: { members } });
    InclamoAPI.giveRole.mockResolvedValue({ data: { members: [members[0], { ...members[1], can_act: true }] } });
    const wrapper = await show();

    const adminSwitch = wrapper.find('[data-testid="inclamo-role-1"] input');
    const agentSwitch = wrapper.find('[data-testid="inclamo-role-2"] input');
    expect(adminSwitch.attributes('disabled')).toBeDefined();
    expect(adminSwitch.element.checked).toBe(true);
    expect(agentSwitch.element.checked).toBe(false);

    await agentSwitch.trigger('change');
    await flush();

    expect(InclamoAPI.giveRole).toHaveBeenCalledWith(2);
    expect(wrapper.find('[data-testid="inclamo-role-2"] input').element.checked).toBe(true);
  });

  it('takes the role away from an agent who has it', async () => {
    InclamoAPI.getRoles.mockResolvedValue({ data: { members: [members[0], { ...members[1], can_act: true }] } });
    InclamoAPI.takeRole.mockResolvedValue({ data: { members } });
    const wrapper = await show();

    await wrapper.find('[data-testid="inclamo-role-2"] input').trigger('change');
    await flush();

    expect(InclamoAPI.takeRole).toHaveBeenCalledWith(2);
  });

  it('says so when the list cannot be loaded', async () => {
    InclamoAPI.getRoles.mockRejectedValue(new Error('down'));
    const wrapper = await show();

    expect(wrapper.find('[data-testid="inclamo-roles-failed"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-roles-page"]').exists()).toBe(false);
  });
});
