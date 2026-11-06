import { mount } from '@vue/test-utils';
import SlaPoliciesPage from '../components/SlaPoliciesPage.vue';
import InclamoAPI from '../api';
import settingsPages from '../settingsPages';
import { SLA_POLICIES_ROUTE } from '../routes';
import { stubs, flush } from './helpers';

// Chatwoot's settings frame reaches its router, whose settings routes read
// this registry: the frame is replaced so the registry can be imported here.
vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', () => ({ default: { name: 'SettingsLayout', template: '<div><slot name="header" /><slot name="body" /></div>' } }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', () => ({ default: { name: 'BaseSettingsHeader', props: ['title', 'description'], template: '<h1>{{ title }}</h1>' } }));
vi.mock('../api', () => ({
  default: {
    getSlaPolicies: vi.fn(),
    createSlaPolicy: vi.fn(),
    updateSlaPolicy: vi.fn(),
    deleteSlaPolicy: vi.fn(),
    reorderSlaPolicies: vi.fn(),
    getSlaSummary: vi.fn(),
  },
}));

const standard = { id: 1, name: 'Standard', position: 0, first_response_seconds: 7200, resolution_seconds: 172800, business_hours_only: false, all_inboxes: true, inbox_ids: [] };
const vip = { id: 2, name: 'VIP', position: 1, first_response_seconds: 900, resolution_seconds: null, business_hours_only: true, all_inboxes: false, inbox_ids: [11] };
const inboxes = [{ id: 10, name: 'Chat', business_hours: false }, { id: 11, name: 'Email', business_hours: true }];
const summaryRow = (id, overrides = {}) => ({ id, name: 'x', conversations: 0, first_response: null, resolution: null, ...overrides });

const show = async (policies = [standard, vip]) => {
  InclamoAPI.getSlaPolicies.mockResolvedValue({ data: { policies, inboxes } });
  InclamoAPI.getSlaSummary.mockResolvedValue({ data: { days: 7, policies: policies.map(policy => summaryRow(policy.id)) } });
  const wrapper = mount(SlaPoliciesPage, { global: { stubs } });
  await flush();
  return wrapper;
};
const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);

describe('SlaPoliciesPage', () => {
  beforeEach(() => vi.clearAllMocks());

  it('is a settings page for administrators only', () => {
    const page = settingsPages.find(entry => entry.name === SLA_POLICIES_ROUTE);
    expect(page).toMatchObject({ path: 'sla', permissions: ['administrator'], component: SlaPoliciesPage });
    expect(page.label()).toBe('SLA');
  });

  it('lists the policies in order with their targets and inboxes', async () => {
    const wrapper = await show();

    expect(find(wrapper, 'inclamo-sla-policy-1').text()).toContain('First response 2 h · Resolution 2 d');
    expect(find(wrapper, 'inclamo-sla-policy-1').text()).toContain('All inboxes');
    expect(find(wrapper, 'inclamo-sla-policy-2').text()).toContain('First response 15 min');
    expect(find(wrapper, 'inclamo-sla-policy-2').text()).toContain('Email · business hours only');
    expect(find(wrapper, 'inclamo-sla-up-1').attributes('disabled')).toBeDefined();
    expect(find(wrapper, 'inclamo-sla-down-2').attributes('disabled')).toBeDefined();
  });

  it('creates a policy from a target in hours and one in days, for all inboxes', async () => {
    const wrapper = await show([]);
    expect(find(wrapper, 'inclamo-sla-empty').exists()).toBe(true);
    InclamoAPI.createSlaPolicy.mockResolvedValue({ data: { policy: standard } });

    await find(wrapper, 'inclamo-sla-add').trigger('click');
    await find(wrapper, 'inclamo-sla-name').setValue('Standard');
    await find(wrapper, 'inclamo-sla-first-value').setValue('2');
    await find(wrapper, 'inclamo-sla-first-unit').setValue('hours');
    await find(wrapper, 'inclamo-sla-resolution-value').setValue('2');
    await find(wrapper, 'inclamo-sla-resolution-unit').setValue('days');
    await find(wrapper, 'inclamo-sla-form').trigger('submit');
    await flush();

    expect(InclamoAPI.createSlaPolicy).toHaveBeenCalledWith({
      name: 'Standard', first_response_seconds: 7200, resolution_seconds: 172800, business_hours_only: false, all_inboxes: true, inbox_ids: [],
    });
    expect(find(wrapper, 'inclamo-sla-form').exists()).toBe(false);
  });

  it('says a target is needed and does not save a policy without one', async () => {
    const wrapper = await show([]);

    await find(wrapper, 'inclamo-sla-add').trigger('click');
    await find(wrapper, 'inclamo-sla-name').setValue('Empty');
    await find(wrapper, 'inclamo-sla-form').trigger('submit');
    await flush();

    expect(find(wrapper, 'inclamo-sla-form-error').text()).toContain('A target is needed');
    expect(InclamoAPI.createSlaPolicy).not.toHaveBeenCalled();
  });

  it('refuses a target of zero and chosen inboxes with none chosen', async () => {
    const wrapper = await show([]);

    await find(wrapper, 'inclamo-sla-add').trigger('click');
    await find(wrapper, 'inclamo-sla-name').setValue('Zero');
    await find(wrapper, 'inclamo-sla-first-value').setValue('0');
    await find(wrapper, 'inclamo-sla-chosen-inboxes').setValue(true);
    await find(wrapper, 'inclamo-sla-form').trigger('submit');
    await flush();

    const text = find(wrapper, 'inclamo-sla-form-error').text();
    expect(text).toContain('more than zero');
    expect(text).toContain('Choose at least one inbox');
    expect(InclamoAPI.createSlaPolicy).not.toHaveBeenCalled();
  });

  it('shows what the server refused', async () => {
    const wrapper = await show([]);
    InclamoAPI.createSlaPolicy.mockRejectedValue({ response: { status: 422, data: { messages: ['One of the chosen inboxes is not in this account.'] } } });

    await find(wrapper, 'inclamo-sla-add').trigger('click');
    await find(wrapper, 'inclamo-sla-name').setValue('Remote');
    await find(wrapper, 'inclamo-sla-first-value').setValue('30');
    await find(wrapper, 'inclamo-sla-first-unit').setValue('minutes');
    await find(wrapper, 'inclamo-sla-form').trigger('submit');
    await flush();

    expect(find(wrapper, 'inclamo-sla-form-error').text()).toContain('not in this account');
  });

  it('edits a policy in its units and for chosen inboxes', async () => {
    const wrapper = await show();
    InclamoAPI.updateSlaPolicy.mockResolvedValue({ data: { policy: vip } });

    await find(wrapper, 'inclamo-sla-edit-2').trigger('click');
    expect(find(wrapper, 'inclamo-sla-first-value').element.value).toBe('15');
    expect(find(wrapper, 'inclamo-sla-first-unit').element.value).toBe('minutes');
    expect(find(wrapper, 'inclamo-sla-business-hours').element.checked).toBe(true);
    await find(wrapper, 'inclamo-sla-inbox-10').find('input').setValue(true);
    await find(wrapper, 'inclamo-sla-form').trigger('submit');
    await flush();

    expect(InclamoAPI.updateSlaPolicy).toHaveBeenCalledWith(2, expect.objectContaining({
      first_response_seconds: 900, resolution_seconds: null, business_hours_only: true, all_inboxes: false, inbox_ids: [11, 10],
    }));
  });

  it('moves a policy up the list', async () => {
    const wrapper = await show();
    InclamoAPI.reorderSlaPolicies.mockResolvedValue({ data: { policies: [{ ...vip, position: 0 }, { ...standard, position: 1 }] } });

    await find(wrapper, 'inclamo-sla-up-2').trigger('click');
    await flush();

    expect(InclamoAPI.reorderSlaPolicies).toHaveBeenCalledWith([2, 1]);
    expect(wrapper.findAll('[data-testid="inclamo-sla-policy-name"]').map(node => node.text())).toEqual(['VIP', 'Standard']);
  });

  it('deletes a policy only after the second click', async () => {
    const wrapper = await show();
    InclamoAPI.deleteSlaPolicy.mockResolvedValue({});

    await find(wrapper, 'inclamo-sla-delete-1').trigger('click');
    expect(InclamoAPI.deleteSlaPolicy).not.toHaveBeenCalled();
    expect(find(wrapper, 'inclamo-sla-delete-ask-1').text()).toContain('Timers it started on open conversations stop');
    await find(wrapper, 'inclamo-sla-delete-confirm-1').trigger('click');
    await flush();

    expect(InclamoAPI.deleteSlaPolicy).toHaveBeenCalledWith(1);
    expect(InclamoAPI.getSlaPolicies).toHaveBeenCalledTimes(2);
  });

  it('shows the summary per policy and switches to 30 days', async () => {
    InclamoAPI.getSlaPolicies.mockResolvedValue({ data: { policies: [standard], inboxes } });
    InclamoAPI.getSlaSummary.mockResolvedValue({
      data: {
        days: 7,
        policies: [summaryRow(1, { conversations: 2, first_response: { total: 2, met: 1, missed: 1, running: 0, met_percent: 50 }, resolution: { total: 2, met: 0, missed: 0, running: 2, met_percent: 0 } })],
      },
    });
    const wrapper = mount(SlaPoliciesPage, { global: { stubs } });
    await flush();

    const text = find(wrapper, 'inclamo-sla-summary-1').text();
    expect(text).toContain('2 conversations');
    expect(text).toContain('first response: 50 % met (1 met, 1 missed, 0 running)');
    expect(InclamoAPI.getSlaSummary).toHaveBeenCalledWith(7);

    await find(wrapper, 'inclamo-sla-days-30').trigger('click');
    await flush();
    expect(InclamoAPI.getSlaSummary).toHaveBeenLastCalledWith(30);
  });

  it('says when the policies cannot be loaded', async () => {
    InclamoAPI.getSlaPolicies.mockRejectedValue(new Error('offline'));
    const wrapper = mount(SlaPoliciesPage, { global: { stubs } });
    await flush();

    expect(find(wrapper, 'inclamo-sla-failed').exists()).toBe(true);
  });
});
