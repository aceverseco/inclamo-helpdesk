import InclamoAPI from '../api';
import { forgetTimers, timerOf, wantTimer, readTimer } from '../slaTimers';

vi.mock('../api', () => ({ default: { getConversationSla: vi.fn(), getConversationSlas: vi.fn() } }));

const timer = { policy_name: 'Website chat', first_response: { state: 'running', target_seconds: 900, remaining_seconds: 540, counting: true } };
const settle = ms => vi.advanceTimersByTimeAsync(ms);

describe('slaTimers, read in batches', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    forgetTimers();
    vi.useFakeTimers({ toFake: ['setInterval', 'setTimeout', 'clearInterval', 'clearTimeout', 'Date'] });
    vi.setSystemTime(new Date('2026-11-13T12:00:00Z'));
  });
  afterEach(() => vi.useRealTimers());

  it('reads a page of rows in one request', async () => {
    InclamoAPI.getConversationSlas.mockResolvedValue({ data: { timers: { 3: timer, 4: null }, pending: [] } });

    for (let id = 1; id <= 25; id += 1) wantTimer(id);
    await settle(30);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(1);
    expect(InclamoAPI.getConversationSlas.mock.calls[0][0]).toHaveLength(25);
    expect(timerOf(3).timer).toEqual(timer);
    expect(timerOf(4).timer).toBeNull();
    // Left out of the answer: a conversation this member may not see.
    expect(timerOf(5).timer).toBeNull();
    expect(InclamoAPI.getConversationSla).not.toHaveBeenCalled();
  });

  it('asks once for an id wanted twice, and not at all while it is being read', async () => {
    let answer;
    InclamoAPI.getConversationSlas.mockReturnValue(new Promise(resolve => { answer = resolve; }));

    wantTimer(7);
    wantTimer(7);
    await settle(30);
    wantTimer(7);
    await settle(30);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(1);
    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledWith([7]);

    answer({ data: { timers: { 7: timer }, pending: [] } });
    await settle(0);
    wantTimer(7);
    await settle(30);

    expect(InclamoAPI.getConversationSlas).toHaveBeenCalledTimes(2);
  });

  it('splits more than a hundred ids into several requests', async () => {
    InclamoAPI.getConversationSlas.mockResolvedValue({ data: { timers: {}, pending: [] } });

    for (let id = 1; id <= 130; id += 1) wantTimer(id);
    await settle(30);

    expect(InclamoAPI.getConversationSlas.mock.calls.map(([ids]) => ids.length)).toEqual([100, 30]);
  });

  it('keeps what was known when a read fails, and does not throw', async () => {
    InclamoAPI.getConversationSlas.mockResolvedValueOnce({ data: { timers: { 7: timer }, pending: [] } });
    wantTimer(7);
    await settle(30);
    InclamoAPI.getConversationSlas.mockRejectedValueOnce(new Error('offline'));

    wantTimer(7);
    wantTimer(8);
    await settle(30);

    expect(timerOf(7).timer).toEqual(timer);
    expect(timerOf(8)).toBeUndefined();

    InclamoAPI.getConversationSlas.mockResolvedValueOnce({ data: { timers: { 8: timer }, pending: [] } });
    wantTimer(8);
    await settle(30);
    expect(timerOf(8).timer).toEqual(timer);
  });

  it('reads a timer that is on its way again by itself, until it is there', async () => {
    InclamoAPI.getConversationSlas.mockResolvedValue({ data: { timers: { 9: null }, pending: [9] } });
    InclamoAPI.getConversationSla.mockResolvedValue({ data: { timer, pending: false } });

    wantTimer(9);
    await settle(30);
    expect(timerOf(9).timer).toBeNull();

    await settle(2_000);
    expect(InclamoAPI.getConversationSla).toHaveBeenCalledWith(9);
    expect(timerOf(9).timer).toEqual(timer);
  });

  it('shares its answers with the single read of the sidebar', async () => {
    InclamoAPI.getConversationSlas.mockResolvedValue({ data: { timers: { 7: timer }, pending: [] } });
    wantTimer(7);

    await settle(30);

    expect(timerOf(7).timer).toEqual(timer);
    InclamoAPI.getConversationSla.mockResolvedValue({ data: { timer: null, pending: false } });
    await readTimer(7);
    expect(timerOf(7).timer).toBeNull();
  });
});
