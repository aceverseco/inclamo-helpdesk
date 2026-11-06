import { nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import SlaSection from '../components/SlaSection.vue';
import InclamoAPI from '../api';

vi.mock('../api', () => ({ default: { getConversationSla: vi.fn() } }));

const timer = (overrides = {}) => ({
  policy_name: 'Standard',
  business_hours_only: false,
  started_at: '2026-11-06T10:00:00Z',
  stopped: false,
  next_change_at: null,
  first_response: { state: 'running', target_seconds: 7200, remaining_seconds: 5400, counting: true },
  resolution: { state: 'running', target_seconds: 172800, remaining_seconds: 171000, counting: true },
  ...overrides,
});

// The timers are fake, so waiting means moving them on.
const settle = () => vi.advanceTimersByTimeAsync(0);
// Moves the clock on, short of the next read of the timer (every minute).
const wait = async ms => {
  await vi.advanceTimersByTimeAsync(ms);
  await nextTick();
};

const show = async data => {
  InclamoAPI.getConversationSla.mockResolvedValue({ data: { timer: data } });
  const wrapper = mount(SlaSection, { props: { conversationId: 7 } });
  await settle();
  return wrapper;
};
const row = (wrapper, name) => wrapper.find(`[data-testid="inclamo-sla-${name}"]`);

describe('SlaSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers({ toFake: ['setInterval', 'setTimeout', 'clearInterval', 'clearTimeout', 'Date'] });
    vi.setSystemTime(new Date('2026-11-06T10:30:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('says no policy applies when the conversation has no timer', async () => {
    const wrapper = await show(null);

    expect(InclamoAPI.getConversationSla).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="inclamo-sla-none"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-sla-timer"]').exists()).toBe(false);
  });

  it('shows the policy and the time left to each target, counting down', async () => {
    const wrapper = await show(timer());

    expect(wrapper.find('[data-testid="inclamo-sla-policy"]').text()).toBe('Standard');
    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('running');
    expect(row(wrapper, 'first_response').text()).toContain('First response');
    expect(row(wrapper, 'first_response').text()).toContain('1 h 30 min left');
    expect(row(wrapper, 'resolution').text()).toContain('1 d 23 h left');

    await wait(30_000);
    expect(row(wrapper, 'first_response').text()).toContain('1 h 29 min left');
    expect(InclamoAPI.getConversationSla).toHaveBeenCalledTimes(1);
  });

  it('turns a running target into missed when it runs out, and reads the timer again', async () => {
    const wrapper = await show(timer({ first_response: { state: 'running', target_seconds: 600, remaining_seconds: 5, counting: true } }));
    InclamoAPI.getConversationSla.mockResolvedValue({ data: { timer: timer({ first_response: { state: 'missed', target_seconds: 600, over_seconds: 1, counting: true } }) } });

    await wait(5_000);
    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('missed');
    expect(InclamoAPI.getConversationSla).toHaveBeenCalledTimes(1);

    await wait(1_500);
    expect(InclamoAPI.getConversationSla).toHaveBeenCalledTimes(2);
    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('missed');
  });

  it('shows paused timers with the full time left outside business hours', async () => {
    const wrapper = await show(timer({
      business_hours_only: true,
      next_change_at: '2026-11-09T08:00:00Z',
      first_response: { state: 'paused', target_seconds: 7200, remaining_seconds: 7200, counting: false },
      resolution: { state: 'paused', target_seconds: 172800, remaining_seconds: 172800, counting: false },
    }));

    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('paused');
    expect(row(wrapper, 'first_response').text()).toContain('Paused, 2 h left');
    expect(row(wrapper, 'resolution').text()).toContain('Paused, 2 d left');
    expect(wrapper.text()).toContain('business hours only');

    await wait(30_000);
    expect(row(wrapper, 'first_response').text()).toContain('Paused, 2 h left');
  });

  it('shows a met target with the time it took, and the other still running', async () => {
    const wrapper = await show(timer({ first_response: { state: 'met', target_seconds: 7200, took_seconds: 1500, counting: false } }));

    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('met');
    expect(row(wrapper, 'first_response').text()).toContain('Met in 25 min');
    expect(row(wrapper, 'resolution').attributes('data-state')).toBe('running');
  });

  it('shows a missed target and by how much, growing while it counts', async () => {
    const wrapper = await show(timer({ first_response: { state: 'missed', target_seconds: 7200, over_seconds: 3540, counting: true } }));

    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('missed');
    expect(row(wrapper, 'first_response').text()).toContain('Missed by 59 min');
    await wait(30_000);
    expect(row(wrapper, 'first_response').text()).toContain('Missed by 59 min 30 s');
  });

  it('shows the running targets of a deleted policy as stopped', async () => {
    const wrapper = await show(timer({ stopped: true, first_response: { state: 'stopped', target_seconds: 7200, remaining_seconds: 100, counting: false } }));

    expect(row(wrapper, 'first_response').attributes('data-state')).toBe('stopped');
    expect(wrapper.text()).toContain('policy deleted');
  });

  it('leaves out a target the policy does not set', async () => {
    const wrapper = await show(timer({ resolution: null }));

    expect(row(wrapper, 'resolution').exists()).toBe(false);
  });

  it('offers to try again when the timer cannot be read', async () => {
    InclamoAPI.getConversationSla.mockRejectedValue(new Error('offline'));
    const wrapper = mount(SlaSection, { props: { conversationId: 7 } });
    await settle();

    expect(wrapper.find('[data-testid="inclamo-sla-failed"]').exists()).toBe(true);
  });
});
