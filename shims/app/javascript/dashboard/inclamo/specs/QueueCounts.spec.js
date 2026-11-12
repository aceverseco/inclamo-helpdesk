import { effectScope, nextTick, ref } from 'vue';
import ConversationApi from 'dashboard/api/inbox/conversation';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useQueueCounts } from '../workspace/useQueueCounts';
import { loadTeamQueues, resetTeamQueues } from '../teamQueues';

const { subscribeAction, unsubscribe } = vi.hoisted(() => ({
  subscribeAction: vi.fn(),
  unsubscribe: vi.fn(),
}));
vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { meta: vi.fn() },
}));
vi.mock('../teamQueues', () => ({
  loadTeamQueues: vi.fn(),
  resetTeamQueues: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ subscribeAction }),
}));

const response = (all, mine = all, unassigned = 0) => ({
  data: {
    meta: { all_count: all, mine_count: mine, unassigned_count: unassigned },
  },
});
const settle = async () => {
  await Promise.resolve();
  await nextTick();
};

describe('navigation queue counts', () => {
  let scope;
  let accountId;
  const start = () => scope.run(() => useQueueCounts(accountId));

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    subscribeAction.mockReturnValue(unsubscribe);
    ConversationApi.meta.mockResolvedValue(response(8, 5, 3));
    accountId = ref(1);
    scope = effectScope();
  });
  afterEach(() => {
    scope.stop();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('loads account-wide open counts without list filters or interval polling', async () => {
    const counts = start();
    expect(counts.value).toBeNull();
    await settle();
    expect(ConversationApi.meta).toHaveBeenCalledWith({ status: 'open' });
    expect(counts.value).toEqual({
      allCount: 8,
      mineCount: 5,
      unAssignedCount: 3,
    });
    await vi.advanceTimersByTimeAsync(60000);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(1);
  });

  it('clears the old account and ignores late responses even after returning to it', async () => {
    const pending = [];
    ConversationApi.meta.mockImplementation(
      () =>
        new Promise(resolve => {
          pending.push(resolve);
        })
    );
    const counts = start();
    accountId.value = 2;
    await nextTick();
    expect(counts.value).toBeNull();
    accountId.value = 1;
    await nextTick();
    pending[2](response(4));
    await settle();
    pending[0](response(99));
    pending[1](response(25));
    await settle();
    expect(counts.value.allCount).toBe(4);
    expect(unsubscribe).toHaveBeenCalledTimes(2);
  });

  it('coalesces real-time events, keeps counts on failure and accepts a real zero', async () => {
    const counts = start();
    await settle();
    ConversationApi.meta.mockRejectedValueOnce(new Error('offline'));
    for (let i = 0; i < 20; i += 1) emitter.emit('fetch_conversation_stats');
    await vi.advanceTimersByTimeAsync(1000);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(2);
    expect(counts.value.allCount).toBe(8);
    ConversationApi.meta.mockResolvedValue(response(0));
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    await vi.advanceTimersByTimeAsync(1000);
    expect(counts.value.allCount).toBe(0);
  });

  it('refreshes after an event arriving during a request and stops on disposal', async () => {
    let resolve;
    ConversationApi.meta.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const counts = start();
    emitter.emit('fetch_conversation_stats');
    await vi.advanceTimersByTimeAsync(15000);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(1);
    resolve(response(8));
    await settle();
    ConversationApi.meta.mockResolvedValue(response(7));
    await vi.advanceTimersByTimeAsync(1000);
    expect(counts.value.allCount).toBe(7);
    emitter.emit('fetch_conversation_stats');
    scope.stop();
    emitter.emit(BUS_EVENTS.WEBSOCKET_RECONNECT);
    window.dispatchEvent(new Event('focus'));
    await vi.advanceTimersByTimeAsync(30000);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(2);
    expect(unsubscribe).toHaveBeenCalledOnce();
  });

  it('uses the native slower refresh cadence for larger accounts and handles deletion', async () => {
    ConversationApi.meta.mockResolvedValue(response(3000));
    start();
    await settle();
    const { after } = subscribeAction.mock.calls[0][0];
    after({ type: 'deleteConversation' });
    window.dispatchEvent(new Event('focus'));
    await vi.advanceTimersByTimeAsync(14999);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(ConversationApi.meta).toHaveBeenCalledTimes(2);
  });

  it('refreshes the team queues on the same triggers and forgets them on an account switch', async () => {
    start();
    await settle();
    // A first load keeps what the route guard may have read already.
    expect(resetTeamQueues).not.toHaveBeenCalled();
    expect(loadTeamQueues).toHaveBeenCalledTimes(1);
    emitter.emit('fetch_conversation_stats');
    await vi.advanceTimersByTimeAsync(1000);
    expect(loadTeamQueues).toHaveBeenCalledTimes(2);
    accountId.value = 2;
    await settle();
    expect(resetTeamQueues).toHaveBeenCalledTimes(1);
    expect(loadTeamQueues).toHaveBeenCalledTimes(3);
  });
});
