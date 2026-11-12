import { mount } from '@vue/test-utils';
import TeamQueuesPage from '../components/TeamQueuesPage.vue';
import settingsPages from '../settingsPages';
import InclamoAPI from '../api';
import { loadTeamQueues } from '../teamQueues';
import { stubs, flush } from './helpers';

vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', async () => ({ default: (await import('./helpers')).SettingsLayoutStub }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', async () => ({ default: (await import('./helpers')).SettingsHeaderStub }));
vi.mock('../teamQueues', () => ({ loadTeamQueues: vi.fn() }));
vi.mock('../api', () => ({
  default: {
    getTeamQueues: vi.fn(),
    updateTeamQueue: vi.fn(),
    reorderTeamQueues: vi.fn(),
    restoreTeamQueue: vi.fn(),
  },
}));

const queue = (id, key, name, overrides = {}) => ({ id, key, name, position: id, hidden: false, ready: true, query: { payload: [] }, count: 0, ...overrides });
const answer = (...queues) => ({ data: { queues, limit: 20 } });
const three = () => answer(queue(1, 'urgent', 'Urgent'), queue(2, 'missing_parts', 'Missing parts'), queue(3, 'cancellation', 'Cancellation', { hidden: true, count: null }));
const show = async () => {
  const wrapper = mount(TeamQueuesPage, { global: { stubs } });
  await flush();
  return wrapper;
};
const find = (wrapper, id) => wrapper.find(`[data-testid="inclamo-team-queue-${id}"]`);

describe('TeamQueuesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    InclamoAPI.getTeamQueues.mockResolvedValue(three());
    InclamoAPI.updateTeamQueue.mockResolvedValue(three());
    InclamoAPI.reorderTeamQueues.mockResolvedValue(three());
    InclamoAPI.restoreTeamQueue.mockResolvedValue(three());
  });

  it('is a settings page for administrators only', () => {
    const page = settingsPages.find(entry => entry.path === 'team-queues');

    expect(page.name).toBe('inclamo_team_queues');
    expect(page.permissions).toEqual(['administrator']);
    expect(page.label()).toBe('Team queues');
  });

  it('lists every queue of the account, the hidden ones included and marked', async () => {
    const wrapper = await show();

    expect(InclamoAPI.getTeamQueues).toHaveBeenCalledWith(true);
    expect(find(wrapper, 'name-urgent').element.value).toBe('Urgent');
    expect(find(wrapper, 'shown-urgent').element.checked).toBe(true);
    expect(find(wrapper, 'shown-cancellation').element.checked).toBe(false);
    expect(find(wrapper, 'hidden-cancellation').exists()).toBe(true);
    expect(find(wrapper, 'hidden-urgent').exists()).toBe(false);
  });

  it('renames a queue and refreshes the navigation', async () => {
    InclamoAPI.updateTeamQueue.mockResolvedValue(answer(queue(1, 'urgent', 'Urgent'), queue(2, 'missing_parts', 'Parts requests')));
    const wrapper = await show();

    await find(wrapper, 'name-missing_parts').setValue('Parts requests');
    await find(wrapper, 'name-missing_parts').trigger('change');
    await flush();

    expect(InclamoAPI.updateTeamQueue).toHaveBeenCalledWith(2, { name: 'Parts requests' });
    // The answer to the change is the list: no second read of it.
    expect(InclamoAPI.getTeamQueues).toHaveBeenCalledTimes(1);
    expect(loadTeamQueues).toHaveBeenCalledTimes(1);
    expect(find(wrapper, 'name-missing_parts').element.value).toBe('Parts requests');
    expect(find(wrapper, 'name-cancellation').exists()).toBe(false);
  });

  it('does not save a name that did not change', async () => {
    const wrapper = await show();

    await find(wrapper, 'name-urgent').trigger('change');
    await flush();

    expect(InclamoAPI.updateTeamQueue).not.toHaveBeenCalled();
  });

  it('hides and shows a queue', async () => {
    const wrapper = await show();

    await find(wrapper, 'shown-urgent').setValue(false);
    await flush();
    expect(InclamoAPI.updateTeamQueue).toHaveBeenCalledWith(1, { hidden: true });

    await find(wrapper, 'shown-cancellation').setValue(true);
    await flush();
    expect(InclamoAPI.updateTeamQueue).toHaveBeenCalledWith(3, { hidden: false });
  });

  it('moves a queue up and down, and not past the ends', async () => {
    const wrapper = await show();

    expect(find(wrapper, 'up-urgent').element.disabled).toBe(true);
    expect(find(wrapper, 'down-cancellation').element.disabled).toBe(true);
    await find(wrapper, 'up-cancellation').trigger('click');
    await flush();
    expect(InclamoAPI.reorderTeamQueues).toHaveBeenCalledWith([1, 3, 2]);

    await find(wrapper, 'down-urgent').trigger('click');
    await flush();
    expect(InclamoAPI.reorderTeamQueues).toHaveBeenLastCalledWith([2, 1, 3]);
  });

  it('restores a ready queue', async () => {
    const wrapper = await show();

    await find(wrapper, 'restore-missing_parts').trigger('click');
    await flush();

    expect(InclamoAPI.restoreTeamQueue).toHaveBeenCalledWith(2);
  });

  it('shows why a change was refused and what the server still holds', async () => {
    InclamoAPI.updateTeamQueue.mockRejectedValue({ response: { data: { message: 'A queue needs a name.' } } });
    const wrapper = await show();

    await find(wrapper, 'name-urgent').setValue('  ');
    await find(wrapper, 'name-urgent').trigger('change');
    await flush();

    expect(wrapper.find('[data-testid="inclamo-team-queues-error"]').text()).toBe('A queue needs a name.');
    expect(find(wrapper, 'name-urgent').element.value).toBe('Urgent');
    expect(InclamoAPI.getTeamQueues).toHaveBeenCalledTimes(2);
    expect(loadTeamQueues).not.toHaveBeenCalled();
  });

  it('says so when the queues cannot be loaded', async () => {
    InclamoAPI.getTeamQueues.mockRejectedValue(new Error('offline'));
    const wrapper = await show();

    expect(wrapper.find('[data-testid="inclamo-team-queues-failed"]').exists()).toBe(true);
  });
});
