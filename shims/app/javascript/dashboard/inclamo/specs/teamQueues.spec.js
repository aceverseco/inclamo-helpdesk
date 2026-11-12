import InclamoAPI from '../api';
import { emitter } from 'shared/helpers/mitt';
import {
  isTeamQueueId,
  loadTeamQueues,
  resetTeamQueues,
  resolveTeamQueue,
  teamQueueAvailable,
  teamQueueRouteId,
  teamQueues,
} from '../teamQueues';

vi.mock('../api', () => ({ default: { getTeamQueues: vi.fn() } }));

const open = { attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: 'and' };
const queue = (id, key, overrides = {}) => ({
  id,
  key,
  name: { urgent: 'Urgent', return: 'Return', cancellation: 'Cancellation' }[key],
  position: id,
  hidden: false,
  ready: true,
  query: { payload: [open, { attribute_key: 'labels', filter_operator: 'equal_to', values: [key], query_operator: null }] },
  count: 2,
  ...overrides,
});
const answer = (...queues) => ({ data: { queues, limit: 20 } });

describe('team queues', () => {
  const toasts = [];
  const onToast = toast => toasts.push(toast);

  beforeEach(() => {
    vi.clearAllMocks();
    resetTeamQueues();
    toasts.length = 0;
    emitter.on('newToastMessage', onToast);
  });
  afterEach(() => emitter.off('newToastMessage', onToast));

  it('tell their ids apart from native folder ids', () => {
    expect(teamQueueRouteId({ id: 12 })).toBe('q-12');
    expect(isTeamQueueId('q-12')).toBe(true);
    expect(isTeamQueueId('12')).toBe(false);
    expect(isTeamQueueId(12)).toBe(false);
  });

  it('resolve a queue id to a folder with the queue name and conditions, and leave native ids alone', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent'), queue(2, 'return')));
    await loadTeamQueues();

    const folder = resolveTeamQueue('q-2');
    expect(folder).toEqual({ id: 'q-2', name: 'Return', query: queue(2, 'return').query, teamQueue: true });
    expect(resolveTeamQueue('2')).toBeUndefined();
    expect(resolveTeamQueue(2)).toBeUndefined();
    expect(resolveTeamQueue('q-9')).toBeUndefined();
  });

  it('keep the same folder object across refreshes until the name or the conditions change', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent')));
    await loadTeamQueues();
    const first = resolveTeamQueue('q-1');

    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent', { count: 5 })));
    await loadTeamQueues();
    expect(resolveTeamQueue('q-1')).toBe(first);
    expect(teamQueues.value[0].count).toBe(5);

    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent', { name: 'Hot' })));
    await loadTeamQueues();
    expect(resolveTeamQueue('q-1')).not.toBe(first);
    expect(resolveTeamQueue('q-1').name).toBe('Hot');
  });

  it('keep the last known queues and counts when a refresh fails', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent')));
    await loadTeamQueues();
    InclamoAPI.getTeamQueues.mockRejectedValue(new Error('offline'));
    await loadTeamQueues();

    expect(teamQueues.value).toHaveLength(1);
    expect(teamQueues.value[0].count).toBe(2);
  });

  it('never list a hidden queue', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent'), queue(3, 'cancellation', { hidden: true })));
    await loadTeamQueues();

    expect(teamQueues.value.map(one => one.key)).toEqual(['urgent']);
    expect(resolveTeamQueue('q-3')).toBeUndefined();
  });

  it('let the route guard open an available queue, loading the queues first', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent')));

    expect(await teamQueueAvailable('q-1')).toBe(true);
    expect(InclamoAPI.getTeamQueues).toHaveBeenCalledTimes(1);
    expect(toasts).toHaveLength(0);
  });

  it('refuse a hidden or unknown queue with the not-available message', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue(answer(queue(1, 'urgent'), queue(3, 'cancellation', { hidden: true })));

    expect(await teamQueueAvailable('q-3')).toBe(false);
    expect(await teamQueueAvailable('q-77')).toBe(false);
    expect(toasts.map(toast => toast.message)).toEqual([
      'This queue is not available. Showing all conversations.',
      'This queue is not available. Showing all conversations.',
    ]);
  });
});
