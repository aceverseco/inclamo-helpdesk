import { badgeOf, nextReadIn, soonFrom } from '../slaBadge';

const NOW = new Date('2026-11-13T12:00:00Z').getTime();
const target = (overrides = {}) => ({ state: 'running', target_seconds: 900, remaining_seconds: 540, counting: true, ...overrides });
const known = (timer, readAt = NOW) => ({ timer: timer && { policy_name: 'Website chat', stopped: false, next_change_at: null, ...timer }, readAt });
const day = (overrides = {}) => target({ target_seconds: 86_400, remaining_seconds: 72_000, ...overrides });
const badge = (timer, options = {}) => badgeOf(known(timer), { now: NOW, ...options });

describe('badgeOf', () => {
  it('shows the first response while nobody has replied, calm with time to spare', () => {
    expect(badge({ first_response: target({ remaining_seconds: 600 }), resolution: day() })).toEqual({ target: 'first_response', look: 'calm', seconds: 600, paused: false });
  });

  it('counts down from the moment the timer was read', () => {
    const read = known({ first_response: target({ remaining_seconds: 540 }) }, NOW - 60_000);

    expect(badgeOf(read, { now: NOW })).toMatchObject({ look: 'calm', seconds: 480 });
  });

  it('turns soon in the last five minutes of a short target', () => {
    expect(badge({ first_response: target({ remaining_seconds: 301 }) }).look).toBe('calm');
    expect(badge({ first_response: target({ remaining_seconds: 300 }) }).look).toBe('soon');
    expect(badge({ first_response: target({ remaining_seconds: 240 }) }).look).toBe('soon');
  });

  it('turns soon in the last quarter of a long target', () => {
    expect(soonFrom(86_400)).toBe(21_600);
    expect(badge({ first_response: day({ remaining_seconds: 21_601 }) }).look).toBe('calm');
    expect(badge({ first_response: day({ remaining_seconds: 21_600 }) }).look).toBe('soon');
  });

  it('is soon from the start for a target shorter than five minutes', () => {
    expect(soonFrom(120)).toBe(120);
    expect(badge({ first_response: target({ target_seconds: 120, remaining_seconds: 120 }) }).look).toBe('soon');
  });

  it('is overdue, by how much, once the target is missed and unmet', () => {
    expect(badge({ first_response: target({ state: 'missed', remaining_seconds: undefined, over_seconds: 720 }) })).toEqual({
      target: 'first_response',
      look: 'overdue',
      seconds: 720,
      paused: false,
    });
  });

  it('turns overdue by itself when the time read runs out before the next read', () => {
    const read = known({ first_response: target({ remaining_seconds: 30 }) }, NOW - 45_000);

    expect(badgeOf(read, { now: NOW })).toMatchObject({ look: 'overdue', seconds: 15 });
  });

  it('keeps growing the overdue time between reads', () => {
    const read = known({ first_response: target({ state: 'missed', over_seconds: 60 }) }, NOW - 30_000);

    expect(badgeOf(read, { now: NOW }).seconds).toBe(90);
  });

  it('shows no resolution badge while the resolution is far away', () => {
    expect(badge({ first_response: target({ state: 'met', took_seconds: 120, counting: false }), resolution: day({ remaining_seconds: 72_000 }) })).toBeNull();
  });

  it('shows the resolution once it is soon, and when it is overdue', () => {
    const replied = target({ state: 'met', took_seconds: 120, counting: false });

    expect(badge({ first_response: replied, resolution: day({ remaining_seconds: 7_200 }) })).toMatchObject({ target: 'resolution', look: 'soon', seconds: 7_200 });
    expect(badge({ first_response: replied, resolution: day({ state: 'missed', over_seconds: 600 }) })).toMatchObject({ target: 'resolution', look: 'overdue', seconds: 600 });
  });

  it('shows the resolution of a policy without a first-response target only when pressing', () => {
    expect(badge({ resolution: day({ remaining_seconds: 80_000 }) })).toBeNull();
    expect(badge({ resolution: day({ remaining_seconds: 600 }) })).toMatchObject({ target: 'resolution', look: 'soon' });
  });

  it('drops the badge after a late reply: missed, but reached', () => {
    const late = target({ state: 'missed', took_seconds: 1_500, over_seconds: 600, counting: false });

    expect(badge({ first_response: late, resolution: day() })).toBeNull();
  });

  it('shows a paused timer as paused, and does not count it down', () => {
    const read = known({ first_response: target({ state: 'paused', target_seconds: 7_200, remaining_seconds: 1_800, counting: false }) }, NOW - 40_000);

    expect(badgeOf(read, { now: NOW })).toEqual({ target: 'first_response', look: 'soon', seconds: 1_800, paused: true });
  });

  it('shows nothing without a timer, for a stopped timer, a resolved conversation or an unread one', () => {
    expect(badge(null)).toBeNull();
    expect(badgeOf(undefined, { now: NOW })).toBeNull();
    expect(badge({ stopped: true, first_response: target({ state: 'stopped', counting: false }) })).toBeNull();
    expect(badge({ first_response: target() }, { resolved: true })).toBeNull();
  });
});

describe('nextReadIn', () => {
  it('asks again a minute after the read while a target is open', () => {
    expect(nextReadIn(known({ first_response: target() }), NOW)).toBe(60_000);
    expect(nextReadIn(known({ first_response: target() }, NOW - 20_000), NOW)).toBe(40_000);
  });

  it('asks sooner when business hours open or close before that', () => {
    const opensAt = new Date(NOW + 10_000).toISOString();

    expect(nextReadIn(known({ next_change_at: opensAt, first_response: target({ state: 'paused', counting: false }) }), NOW)).toBe(11_000);
  });

  it('never asks more often than once a second', () => {
    expect(nextReadIn(known({ first_response: target() }, NOW - 120_000), NOW)).toBe(1_000);
  });

  it('does not ask again when nothing can change', () => {
    const done = { first_response: target({ state: 'met', took_seconds: 60, counting: false }), resolution: day({ state: 'met', took_seconds: 600, counting: false }) };

    expect(nextReadIn(known(null), NOW)).toBeNull();
    expect(nextReadIn(known(done), NOW)).toBeNull();
    expect(nextReadIn(known({ stopped: true, first_response: target({ state: 'stopped' }) }), NOW)).toBeNull();
  });
});
