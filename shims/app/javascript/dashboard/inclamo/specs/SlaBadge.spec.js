import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import SlaBadge from '../components/SlaBadge.vue';
import InclamoAPI from '../api';
import { forgetTimers } from '../slaTimers';

vi.mock('../api', () => ({ default: { getConversationSla: vi.fn(), getConversationSlas: vi.fn() } }));

const target = (overrides = {}) => ({ state: 'running', target_seconds: 900, remaining_seconds: 540, counting: true, deadline_at: '2026-11-13T12:09:00Z', ...overrides });
const timer = (overrides = {}) => ({
  policy_name: 'Website chat',
  stopped: false,
  next_change_at: null,
  first_response: target(),
  resolution: target({ target_seconds: 86_400, remaining_seconds: 85_000, deadline_at: '2026-11-14T11:54:00Z' }),
  ...overrides,
});
const answers = timers => InclamoAPI.getConversationSlas.mockResolvedValue({ data: { timers, pending: [] } });
const wait = async ms => {
  await vi.advanceTimersByTimeAsync(ms);
  await nextTick();
};
// A badge left mounted would follow the next test's reads of the same conversation.
const mounted = [];
const put = options => {
  const wrapper = mount(SlaBadge, options);
  mounted.push(wrapper);
  return wrapper;
};
const show = async (data, props = {}) => {
  answers({ 7: data });
  const wrapper = put({ props: { conversationId: 7, status: 'open', activity: 100, ...props } });
  await wait(30);
  return wrapper;
};
const badge = wrapper => wrapper.find('[data-testid="inclamo-sla-badge"]');

describe('SlaBadge', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    forgetTimers();
    vi.useFakeTimers({ toFake: ['setInterval', 'setTimeout', 'clearInterval', 'clearTimeout', 'Date'] });
    vi.setSystemTime(new Date('2026-11-13T12:00:00Z'));
  });
  afterEach(() => {
    mounted.splice(0).forEach(wrapper => wrapper.unmount());
    vi.useRealTimers();
  });

  it('shows the first reply with the time left, in the calm look', async () => {
    const wrapper = await show(timer());

    expect(badge(wrapper).text()).toBe('First reply · 9 min');
    expect(badge(wrapper).attributes('data-look')).toBe('calm');
    expect(badge(wrapper).attributes('aria-label')).toBe('SLA: First reply due in 9 min');
  });

  it('shows nothing without a timer, and nothing for a resolved conversation', async () => {
    expect(badge(await show(null)).exists()).toBe(false);
    forgetTimers();
    expect(badge(await show(timer(), { status: 'resolved' })).exists()).toBe(false);
  });

  it('shows nothing, and does not break, when the timers cannot be read', async () => {
    InclamoAPI.getConversationSlas.mockRejectedValue(new Error('offline'));
    const wrapper = put({ props: { conversationId: 7 } });
    await wait(30);

    expect(badge(wrapper).exists()).toBe(false);
  });

  it('counts down, turns soon and then overdue in words, without a new read', async () => {
    const wrapper = await show(timer({ first_response: target({ remaining_seconds: 330 }) }));
    expect(badge(wrapper).attributes('data-look')).toBe('calm');

    await wait(31_000);
    expect(badge(wrapper).attributes('data-look')).toBe('soon');
    expect(badge(wrapper).text()).toBe('First reply · 4 min');
    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(1);
  });

  it('says overdue and by how much', async () => {
    const wrapper = await show(timer({ first_response: target({ state: 'missed', remaining_seconds: undefined, over_seconds: 720 }) }));

    expect(badge(wrapper).text()).toBe('First reply · overdue 12 min');
    expect(badge(wrapper).attributes('data-look')).toBe('overdue');
    expect(badge(wrapper).attributes('aria-label')).toBe('SLA: First reply overdue by 12 min');
  });

  it('shows seconds only within the last minute', async () => {
    const wrapper = await show(timer({ first_response: target({ remaining_seconds: 45 }) }));

    expect(badge(wrapper).text()).toBe('First reply · 45 s');
  });

  it('shows a paused timer as paused and does not count it down', async () => {
    const wrapper = await show(timer({ first_response: target({ state: 'paused', target_seconds: 7_200, remaining_seconds: 1_800, counting: false }) }));

    expect(badge(wrapper).text()).toBe('First reply · paused, 30 min');
    expect(badge(wrapper).attributes('data-paused')).toBe('true');
    await wait(20_000);
    expect(badge(wrapper).text()).toBe('First reply · paused, 30 min');
  });

  it('reads again after a minute and drops the badge once a person replied', async () => {
    const wrapper = await show(timer());
    answers({ 7: timer({ first_response: target({ state: 'met', took_seconds: 100, counting: false }) }) });

    await wait(60_100);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(2);
    expect(badge(wrapper).exists()).toBe(false);
  });

  it('reads again at once when the conversation changes: a reply, a resolution', async () => {
    const wrapper = await show(timer());
    answers({ 7: timer({ first_response: target({ state: 'met', took_seconds: 100, counting: false }) }) });

    await wrapper.setProps({ activity: 101 });
    await wait(30);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(2);
    expect(badge(wrapper).exists()).toBe(false);
  });

  it('reads once more a few seconds after a change: the timer follows a reply in the background', async () => {
    const wrapper = await show(timer());
    await wrapper.setProps({ activity: 101 });
    await wait(30);
    expect(badge(wrapper).exists()).toBe(true);
    answers({ 7: timer({ first_response: target({ state: 'met', took_seconds: 100, counting: false }) }) });

    await wait(5_100);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(3);
    expect(badge(wrapper).exists()).toBe(false);
  });

  it('does not keep asking for a conversation with nothing to watch', async () => {
    await show(null);

    await wait(180_000);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(1);
  });

  it('on a row, has no details and is not a tab stop', async () => {
    const wrapper = await show(timer());

    await badge(wrapper).trigger('mouseenter');

    expect(wrapper.find('[data-testid="inclamo-sla-badge-details"]').exists()).toBe(false);
    expect(badge(wrapper).attributes('tabindex')).toBeUndefined();
    expect(badge(wrapper).attributes('title')).toBe('SLA: First reply due in 9 min');
  });

  it('in the header, lists every target with its state and deadline on pointing or focus', async () => {
    const wrapper = await show(timer(), { detailed: true });
    expect(badge(wrapper).attributes('tabindex')).toBe('0');

    await badge(wrapper).trigger('focus');

    const details = wrapper.find('[data-testid="inclamo-sla-badge-details"]');
    expect(details.text()).toContain('SLA "Website chat"');
    expect(wrapper.find('[data-testid="inclamo-sla-badge-first_response"]').text()).toMatch(/^First response: 9 min left · due .*2026/);
    expect(wrapper.find('[data-testid="inclamo-sla-badge-resolution"]').text()).toContain('Resolution: 23 h 36 min left');

    await badge(wrapper).trigger('blur');
    expect(wrapper.find('[data-testid="inclamo-sla-badge-details"]').exists()).toBe(false);
  });

  it('stops its clocks when the row leaves the list', async () => {
    const wrapper = await show(timer());
    wrapper.unmount();

    await wait(120_000);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(1);
  });
});
