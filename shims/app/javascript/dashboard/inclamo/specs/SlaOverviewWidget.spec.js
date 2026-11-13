import { nextTick } from 'vue';
import { mount, RouterLinkStub } from '@vue/test-utils';
import SlaOverviewWidget from '../widgets/SlaOverviewWidget.vue';
import InclamoAPI from '../api';
import { registry, productLayout, manifest } from '../widgets/registry';

vi.mock('../api', () => ({ default: { getSlaOverview: vi.fn() } }));
const role = { value: 'agent' };
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: name => (name === 'getCurrentRole' ? role : { value: 4 }),
}));

const queue = (id, key, name, overdue, soon, other, more = {}) => ({ id, key, name, total: overdue + soon + other, overdue, soon, other, capped: false, ...more });
const answer = (queues, policies = true, totals = { overdue: 0, soon: 0 }) => ({ data: { queues, totals, policies, cap: 2000 } });
const mounted = [];
const settle = async () => {
  await vi.advanceTimersByTimeAsync(0);
  await nextTick();
};
// The widget as it sits in the header: the summary only.
const place = async () => {
  const wrapper = mount(SlaOverviewWidget, { attachTo: document.body, global: { stubs: { RouterLink: RouterLinkStub } } });
  mounted.push(wrapper);
  await settle();
  return wrapper;
};
const toggle = wrapper => wrapper.find('[data-testid="inclamo-sla-overview-toggle"]');
// With its queues opened, as after a click on the summary.
const show = async () => {
  const wrapper = await place();
  await toggle(wrapper).trigger('click');
  await settle();
  return wrapper;
};
const entry = (wrapper, key) => wrapper.find(`[data-testid="inclamo-sla-overview-queue"][data-queue="${key}"]`);
const count = (wrapper, key, level) => entry(wrapper, key).find(`[data-level="${level}"]`);

describe('SlaOverviewWidget', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    role.value = 'agent';
    vi.useFakeTimers({ toFake: ['setInterval', 'setTimeout', 'clearInterval', 'clearTimeout', 'Date'] });
  });
  afterEach(() => {
    mounted.splice(0).forEach(wrapper => wrapper.unmount());
    vi.useRealTimers();
  });

  it('is a workspace-header widget of the product layout', () => {
    expect(registry.get('sla-overview')).toMatchObject({ placement: 'workspace-header', label: 'WIDGETS.SLA_OVERVIEW' });
    expect(productLayout().placements['workspace-header'].map(one => one.id)).toEqual(['sla-overview', 'notifications']);
    expect(manifest.widgets.filter(one => one.id === 'sla-overview')).toHaveLength(1);
  });

  it('shows a summary in the header: each overdue and each soon conversation once', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(4, 'delivery', 'Delivery', 2, 1, 4), queue(8, 'return', 'Return', 1, 0, 0)], true, { overdue: 2, soon: 1 }));

    const wrapper = await place();

    expect(toggle(wrapper).text()).toContain('SLA');
    expect(toggle(wrapper).find('[data-total="overdue"]').text()).toBe('2');
    expect(toggle(wrapper).find('[data-total="soon"]').text()).toBe('1');
    expect(toggle(wrapper).attributes('aria-label')).toBe('SLA overview: 2 overdue, 1 due soon. Show the queues.');
    expect(toggle(wrapper).attributes('aria-expanded')).toBe('false');
    expect(wrapper.find('[data-testid="inclamo-sla-overview-queues"]').exists()).toBe(false);
  });

  it('opens the queues on the summary, with fresh numbers, and closes on Escape, on a click outside and on a queue', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(4, 'delivery', 'Delivery', 2, 1, 4)], true, { overdue: 2, soon: 1 }));
    const wrapper = await show();
    const list = () => wrapper.find('[data-testid="inclamo-sla-overview-queues"]');

    expect(list().exists()).toBe(true);
    expect(toggle(wrapper).attributes('aria-expanded')).toBe('true');
    expect(InclamoAPI.getSlaOverview).toHaveBeenCalledTimes(2);

    await wrapper.trigger('keydown', { key: 'Escape' });
    expect(list().exists()).toBe(false);

    await toggle(wrapper).trigger('click');
    document.body.click();
    await settle();
    expect(list().exists()).toBe(false);

    await toggle(wrapper).trigger('click');
    await settle();
    await entry(wrapper, 'delivery').trigger('click');
    expect(list().exists()).toBe(false);
  });

  it('lists the queues in the order given, each with its three numbers', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(1, 'urgent', 'Urgent', 0, 0, 2), queue(4, 'delivery', 'Delivery', 2, 1, 4)]));

    const wrapper = await show();

    expect(wrapper.findAll('[data-testid="inclamo-sla-overview-queue"]').map(one => one.attributes('data-queue'))).toEqual(['urgent', 'delivery']);
    expect(['overdue', 'soon', 'other'].map(level => count(wrapper, 'delivery', level).text())).toEqual(['2', '1', '4']);
    expect(entry(wrapper, 'delivery').text()).toContain('Delivery');
  });

  it('names each number in words, for pointing and for assistive technology', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(4, 'delivery', 'Delivery', 2, 1, 4)]));

    const wrapper = await show();

    expect(count(wrapper, 'delivery', 'overdue').attributes('title')).toBe('2 overdue');
    expect(count(wrapper, 'delivery', 'soon').attributes('title')).toBe('1 due soon');
    expect(count(wrapper, 'delivery', 'other').attributes('title')).toBe('4 others');
    expect(entry(wrapper, 'delivery').attributes('aria-label')).toBe('Delivery: 2 overdue, 1 due soon, 4 others. Open the queue.');
  });

  it('shows a zero, subdued, instead of hiding it', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(5, 'damage', 'Damage', 0, 0, 3)]));

    const wrapper = await show();

    expect(count(wrapper, 'damage', 'overdue').text()).toBe('0');
    expect(count(wrapper, 'damage', 'overdue').classes()).toContain('zero');
    expect(count(wrapper, 'damage', 'other').classes()).not.toContain('zero');
  });

  it("opens the queue from its entry: the queue's own route", async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(5, 'damage', 'Damage', 1, 0, 0)]));

    const wrapper = await show();

    expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({ name: 'folder_conversations', params: { accountId: 4, id: 'q-5' } });
  });

  it('marks a queue longer than the server counts, and one it could not count', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(
      answer([queue(4, 'delivery', 'Delivery', 3, 0, 2500, { capped: true }), { id: 9, key: null, name: 'Own', total: null, overdue: null, soon: null, other: null, capped: false }])
    );

    const wrapper = await show();

    expect(count(wrapper, 'delivery', 'overdue').text()).toBe('3+');
    expect(count(wrapper, 'delivery', 'other').text()).toBe('2500');
    expect(count(wrapper, '9', 'overdue').text()).toBe('–');
    expect(entry(wrapper, '9').attributes('aria-label')).toBe('Own: could not be counted. Open the queue.');
  });

  it('refreshes every minute without a reload', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(8, 'return', 'Return', 0, 1, 0)]));
    const wrapper = await show();
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(8, 'return', 'Return', 1, 0, 0)]));

    await vi.advanceTimersByTimeAsync(60_000);
    await nextTick();

    expect(InclamoAPI.getSlaOverview).toHaveBeenCalledTimes(3);
    expect(count(wrapper, 'return', 'overdue').text()).toBe('1');
  });

  it('keeps the last numbers when a refresh fails', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(8, 'return', 'Return', 1, 0, 0)]));
    const wrapper = await show();
    InclamoAPI.getSlaOverview.mockRejectedValue(new Error('offline'));

    await vi.advanceTimersByTimeAsync(60_000);
    await nextTick();

    expect(count(wrapper, 'return', 'overdue').text()).toBe('1');
    expect(wrapper.find('[data-testid="inclamo-sla-overview-failed"]').exists()).toBe(false);
  });

  it('says so inside the widget when the first read fails, and tries again on request', async () => {
    InclamoAPI.getSlaOverview.mockRejectedValue(new Error('offline'));
    const wrapper = await show();
    expect(wrapper.find('[data-testid="inclamo-sla-overview-failed"]').text()).toContain('could not be loaded');

    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(8, 'return', 'Return', 1, 0, 0)]));
    await wrapper.find('[data-testid="inclamo-sla-overview-failed"] button').trigger('click');
    await vi.advanceTimersByTimeAsync(0);
    await nextTick();

    expect(entry(wrapper, 'return').exists()).toBe(true);
  });

  it('explains an account without SLA policies, with the settings link for an administrator only', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([queue(8, 'return', 'Return', 0, 0, 1)], false));

    const forAgent = await show();
    expect(forAgent.find('[data-testid="inclamo-sla-overview-no-policies"]').text()).toContain('No SLA policy yet');
    expect(forAgent.find('[data-testid="inclamo-sla-overview-set-up"]').exists()).toBe(false);
    expect(forAgent.find('[data-testid="inclamo-sla-overview-queue"]').exists()).toBe(false);

    role.value = 'administrator';
    const forAdmin = await show();
    expect(forAdmin.findComponent(RouterLinkStub).props('to')).toEqual({ name: 'inclamo_sla_policies', params: { accountId: 4 } });
  });

  it('stops refreshing when it leaves the header', async () => {
    InclamoAPI.getSlaOverview.mockResolvedValue(answer([]));
    const wrapper = await place();
    wrapper.unmount();

    await vi.advanceTimersByTimeAsync(180_000);

    expect(InclamoAPI.getSlaOverview).toHaveBeenCalledTimes(1);
  });
});
