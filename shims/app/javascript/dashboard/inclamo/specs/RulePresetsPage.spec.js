import { mount } from '@vue/test-utils';
import RulePresetsPage from '../components/RulePresetsPage.vue';
import settingsPages from '../settingsPages';
import InclamoAPI from '../api';
import { stubs, flush } from './helpers';

// Chatwoot's settings layout imports its way back to the settings routes and
// so to the registry of pages. The dashboard enters that circle from the
// routes; a test enters it from a page and would find the registry half
// built. The frame is replaced before anything is loaded.
vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', async () => ({ default: (await import('./helpers')).SettingsLayoutStub }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', async () => ({ default: (await import('./helpers')).SettingsHeaderStub }));

vi.mock('../api', () => ({
  default: {
    getRulePresets: vi.fn(),
    switchRulePreset: vi.fn(),
    getRoles: vi.fn(),
  },
}));

const preset = (key, overrides = {}) => ({
  key,
  name: { vip: 'VIP customers first', not_shipped: 'Order not shipped yet', no_orders: 'No orders yet' }[key],
  about: `About ${key}.`,
  needs_value: key === 'vip',
  on: false,
  rule_id: null,
  rule_name: null,
  value: null,
  ...overrides,
});
const answer = (overrides = {}, more = {}) => ({
  data: { store_connected: true, currency: 'EUR', presets: ['vip', 'not_shipped', 'no_orders'].map(key => preset(key, overrides[key])), ...more },
});
const show = async data => {
  InclamoAPI.getRulePresets.mockResolvedValue(data);
  const wrapper = mount(RulePresetsPage, { global: { stubs } });
  await flush();
  return wrapper;
};
const find = (wrapper, id) => wrapper.find(`[data-testid="inclamo-preset-${id}"]`);

describe('RulePresetsPage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists the three presets, off, with a value field only where the rule needs one', async () => {
    const wrapper = await show(answer());

    expect(wrapper.text()).toContain('VIP customers first');
    expect(wrapper.text()).toContain('Order not shipped yet');
    expect(wrapper.text()).toContain('No orders yet');
    ['vip', 'not_shipped', 'no_orders'].forEach(key => expect(find(wrapper, `${key}-switch`).element.checked).toBe(false));
    expect(find(wrapper, 'vip-value').exists()).toBe(true);
    expect(find(wrapper, 'vip').text()).toContain('EUR');
    expect(find(wrapper, 'not_shipped-value').exists()).toBe(false);
    expect(find(wrapper, 'no_orders-value').exists()).toBe(false);
    expect(wrapper.find('[data-testid="inclamo-presets-not-connected"]').exists()).toBe(false);
  });

  it('switches a preset on with the amount that was entered, and names the rule it became', async () => {
    const wrapper = await show(answer());
    InclamoAPI.switchRulePreset.mockResolvedValue(answer({ vip: { on: true, rule_id: 12, rule_name: 'VIP customers first', value: '500' } }));

    await find(wrapper, 'vip-value').setValue('500');
    await find(wrapper, 'vip-switch').trigger('change');
    await flush();

    expect(InclamoAPI.switchRulePreset).toHaveBeenCalledWith('vip', { active: true, value: 500 });
    expect(find(wrapper, 'vip-switch').element.checked).toBe(true);
    expect(find(wrapper, 'vip-rule').text()).toContain('VIP customers first');
    expect(find(wrapper, 'vip-rule').find('a').attributes('data-route')).toBe('automation_list');
  });

  it('switches a preset without a value on with nothing but the switch', async () => {
    const wrapper = await show(answer());
    InclamoAPI.switchRulePreset.mockResolvedValue(answer({ not_shipped: { on: true, rule_id: 13, rule_name: 'Order not shipped yet' } }));

    await find(wrapper, 'not_shipped-switch').trigger('change');
    await flush();

    expect(InclamoAPI.switchRulePreset).toHaveBeenCalledWith('not_shipped', { active: true });
    expect(find(wrapper, 'not_shipped-switch').element.checked).toBe(true);
  });

  it('shows a preset that is on with the amount its rule holds, and switches it off', async () => {
    const on = { vip: { on: true, rule_id: 12, rule_name: 'Our best customers', value: '800' } };
    const wrapper = await show(answer(on));
    InclamoAPI.switchRulePreset.mockResolvedValue(answer({ vip: { ...on.vip, on: false } }));

    expect(find(wrapper, 'vip-switch').element.checked).toBe(true);
    expect(find(wrapper, 'vip-value').element.value).toBe('800');
    expect(find(wrapper, 'vip-rule').text()).toContain('Our best customers');

    await find(wrapper, 'vip-switch').trigger('change');
    await flush();

    expect(InclamoAPI.switchRulePreset).toHaveBeenCalledWith('vip', { active: false });
    expect(find(wrapper, 'vip-switch').element.checked).toBe(false);
    // The rule is still there, deactivated, and the page still names it.
    expect(find(wrapper, 'vip-rule').exists()).toBe(true);
  });

  it('saves a new amount of a preset that is on when the field is left', async () => {
    const wrapper = await show(answer({ vip: { on: true, rule_id: 12, rule_name: 'VIP customers first', value: '500' } }));
    InclamoAPI.switchRulePreset.mockResolvedValue(answer({ vip: { on: true, rule_id: 12, rule_name: 'VIP customers first', value: '750' } }));

    await find(wrapper, 'vip-value').setValue('750');
    await find(wrapper, 'vip-value').trigger('change');
    await flush();

    expect(InclamoAPI.switchRulePreset).toHaveBeenCalledWith('vip', { active: true, value: 750 });
  });

  it('does not save an amount typed for a preset that is off', async () => {
    const wrapper = await show(answer());

    await find(wrapper, 'vip-value').setValue('750');
    await find(wrapper, 'vip-value').trigger('change');
    await flush();

    expect(InclamoAPI.switchRulePreset).not.toHaveBeenCalled();
  });

  it('shows the server\'s reason when a switch is refused, and leaves the switch off', async () => {
    const wrapper = await show(answer());
    InclamoAPI.switchRulePreset.mockRejectedValue({ response: { data: { error: 'value_required', message: 'Enter an amount, zero or more, before switching this rule on.' } } });

    const toggle = find(wrapper, 'vip-switch');
    toggle.element.checked = true;
    await toggle.trigger('change');
    await flush();

    expect(find(wrapper, 'vip-error').text()).toBe('Enter an amount, zero or more, before switching this rule on.');
    expect(find(wrapper, 'vip-switch').element.checked).toBe(false);
    expect(find(wrapper, 'not_shipped-error').exists()).toBe(false);
  });

  it('says so in its own words when the switch failed without an answer', async () => {
    const wrapper = await show(answer());
    InclamoAPI.switchRulePreset.mockRejectedValue(new Error('network'));

    await find(wrapper, 'no_orders-switch').trigger('change');
    await flush();

    expect(find(wrapper, 'no_orders-error').text()).toBe('The rule could not be switched. Try again.');
  });

  it('says the rules act only with a store when none is connected', async () => {
    const wrapper = await show(answer({}, { store_connected: false, currency: null }));

    expect(wrapper.find('[data-testid="inclamo-presets-not-connected"]').exists()).toBe(true);
    expect(find(wrapper, 'vip-switch').attributes('disabled')).toBeUndefined();
  });

  it('says the rules could not be loaded when the request fails', async () => {
    InclamoAPI.getRulePresets.mockRejectedValue(new Error('network'));
    const wrapper = mount(RulePresetsPage, { global: { stubs } });
    await flush();

    expect(wrapper.find('[data-testid="inclamo-presets-failed"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-presets-page"]').exists()).toBe(false);
  });

  it('is a page of the account settings for administrators only', () => {
    const page = settingsPages.find(entry => entry.path === 'preset-rules');

    expect(page.component).toBe(RulePresetsPage);
    expect(page.permissions).toEqual(['administrator']);
    expect(page.label()).toBe('Preset rules');
  });
});
