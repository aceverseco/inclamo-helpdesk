import { mount } from '@vue/test-utils';
import DiscountSettingsPage from '../components/DiscountSettingsPage.vue';
import InclamoAPI from '../api';
import { stubs, flush } from './helpers';

vi.mock('../api', () => ({
  default: {
    getDiscountPresets: vi.fn(),
    createDiscountPreset: vi.fn(),
    updateDiscountPreset: vi.fn(),
    deleteDiscountPreset: vi.fn(),
    getDiscountGrants: vi.fn(),
    giveDiscountGrant: vi.fn(),
    takeDiscountGrant: vi.fn(),
    getConnection: vi.fn(),
    getRoles: vi.fn(),
  },
}));

const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const findAll = (wrapper, id) => wrapper.findAll(`[data-testid="${id}"]`);

const sorry = { id: 1, name: 'Sorry', kind: 'percentage', value: '10', expires_in_days: 30, usage_limit: 1, audience: 'customer' };
const thanks = { id: 2, name: 'Thanks', kind: 'amount', value: '200', expires_in_days: null, usage_limit: 3, audience: 'anyone' };
const members = [
  { user_id: 1, name: 'Admin Example', email: 'admin@example.com', role: 'administrator', can_give: true, switchable: false },
  { user_id: 2, name: 'Agent Example', email: 'agent@example.com', role: 'agent', can_give: false, switchable: true },
];

const show = async (presets = [sorry, thanks]) => {
  InclamoAPI.getDiscountPresets.mockResolvedValue({ data: { presets } });
  InclamoAPI.getDiscountGrants.mockResolvedValue({ data: { members } });
  InclamoAPI.getConnection.mockResolvedValue({ data: { shop_currency: 'UAH' } });
  const wrapper = mount(DiscountSettingsPage, { global: { stubs } });
  await flush();
  return wrapper;
};

const fill = async (wrapper, fields) => {
  for (const [name, value] of Object.entries(fields)) {
    await find(wrapper, `inclamo-preset-field-${name}`).setValue(value);
  }
};

beforeEach(() => vi.clearAllMocks());

// The page's place in the settings (administrators only) is checked end to
// end: the registry is loaded through the router, and imported alone it meets
// the settings routes half-loaded.
describe('Discount codes settings page', () => {
  it('lists the presets with their conditions', async () => {
    const wrapper = await show();

    expect(findAll(wrapper, 'inclamo-preset-name').map(name => name.text())).toEqual(['Sorry', 'Thanks']);
    const conditions = findAll(wrapper, 'inclamo-preset-conditions').map(line => line.text());
    expect(conditions[0]).toBe('10% off the order · expires in 30 days · usable once · this customer only');
    expect(conditions[1]).toContain('never expires · usable 3 times · anyone, once per buyer');
    expect(conditions[1]).toMatch(/200/);
  });

  it('adds a preset; an empty expiry is sent as never', async () => {
    InclamoAPI.createDiscountPreset.mockResolvedValue({ data: { preset: { ...thanks, id: 3 }, presets: [sorry, thanks, { ...thanks, id: 3, name: 'Late parcel' }] } });
    const wrapper = await show([sorry, thanks]);

    await find(wrapper, 'inclamo-preset-add').trigger('click');
    await fill(wrapper, { name: 'Late parcel', kind: 'amount', value: '200', expires: '', uses: '3', audience: 'anyone' });
    await find(wrapper, 'inclamo-preset-form').trigger('submit');
    await flush();

    expect(InclamoAPI.createDiscountPreset).toHaveBeenCalledWith({ name: 'Late parcel', kind: 'amount', value: '200', expires_in_days: '', usage_limit: '3', audience: 'anyone' });
    expect(find(wrapper, 'inclamo-preset-form').exists()).toBe(false);
    expect(findAll(wrapper, 'inclamo-preset')).toHaveLength(3);
  });

  it('shows why a preset outside the limits is not saved', async () => {
    InclamoAPI.createDiscountPreset.mockRejectedValue({ response: { status: 422, data: { error: 'invalid', fields: { value: ['less_than_or_equal_to'], usage_limit: ['greater_than'] } } } });
    const wrapper = await show();

    await find(wrapper, 'inclamo-preset-add').trigger('click');
    await fill(wrapper, { name: 'Too much', value: '120', uses: '0' });
    await find(wrapper, 'inclamo-preset-form').trigger('submit');
    await flush();

    expect(find(wrapper, 'inclamo-preset-error-value').text()).toBe('A percentage can be at most 100.');
    expect(find(wrapper, 'inclamo-preset-error-usage_limit').text()).toBe('At least 1 use.');
    expect(find(wrapper, 'inclamo-preset-form').exists()).toBe(true);
  });

  it('changes a preset', async () => {
    InclamoAPI.updateDiscountPreset.mockResolvedValue({ data: { presets: [{ ...sorry, value: '15' }, thanks] } });
    const wrapper = await show();

    await findAll(wrapper, 'inclamo-preset-edit')[0].trigger('click');
    expect(find(wrapper, 'inclamo-preset-field-name').element.value).toBe('Sorry');
    await fill(wrapper, { value: '15' });
    await find(wrapper, 'inclamo-preset-form').trigger('submit');
    await flush();

    expect(InclamoAPI.updateDiscountPreset).toHaveBeenCalledWith(1, expect.objectContaining({ value: '15', expires_in_days: '30' }));
    expect(findAll(wrapper, 'inclamo-preset-conditions')[0].text()).toContain('15% off the order');
  });

  it('removes a preset after a confirmation', async () => {
    InclamoAPI.deleteDiscountPreset.mockResolvedValue({ data: { presets: [thanks] } });
    const wrapper = await show();

    await findAll(wrapper, 'inclamo-preset-remove')[0].trigger('click');
    expect(InclamoAPI.deleteDiscountPreset).not.toHaveBeenCalled();
    await find(wrapper, 'inclamo-preset-remove-confirm').trigger('click');
    await flush();

    expect(InclamoAPI.deleteDiscountPreset).toHaveBeenCalledWith(1);
    expect(findAll(wrapper, 'inclamo-preset')).toHaveLength(1);
  });

  it('gives and takes the right to give discounts; administrators always have it', async () => {
    InclamoAPI.giveDiscountGrant.mockResolvedValue({ data: { members: [members[0], { ...members[1], can_give: true }] } });
    InclamoAPI.takeDiscountGrant.mockResolvedValue({ data: { members } });
    const wrapper = await show();

    const adminSwitch = find(wrapper, 'inclamo-grant-1').find('input');
    expect(adminSwitch.element.checked).toBe(true);
    expect(adminSwitch.attributes('disabled')).toBeDefined();

    await find(wrapper, 'inclamo-grant-2').find('input').trigger('change');
    await flush();
    expect(InclamoAPI.giveDiscountGrant).toHaveBeenCalledWith(2);
    expect(find(wrapper, 'inclamo-grant-2').find('input').element.checked).toBe(true);

    await find(wrapper, 'inclamo-grant-2').find('input').trigger('change');
    await flush();
    expect(InclamoAPI.takeDiscountGrant).toHaveBeenCalledWith(2);
  });

  it('says when there is no preset yet', async () => {
    const wrapper = await show([]);

    expect(find(wrapper, 'inclamo-presets-none').exists()).toBe(true);
  });
});
