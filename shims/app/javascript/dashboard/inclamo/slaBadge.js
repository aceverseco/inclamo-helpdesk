// What the SLA badge of a conversation shows (capability sla-badge): the one
// target that needs attention, and how pressing it is. Used by the badge on a
// list row and in the conversation header, so the two cannot disagree.
//
// The rule: while the first response is not reached, that target. After it,
// the resolution target, but only once it is soon or overdue: a resolution a
// day away on every row would be noise. Nothing for a conversation without a
// timer, with a stopped timer, or resolved.

// "Soon": the last quarter of the target, and never less than its last five
// minutes (a target shorter than five minutes is soon from the start).
export const SOON_SHARE = 0.25;
export const SOON_FLOOR_SECONDS = 300;

export const soonFrom = targetSeconds => Math.min(targetSeconds, Math.max(targetSeconds * SOON_SHARE, SOON_FLOOR_SECONDS));

// A target that can still change: not reached, and its policy still there.
const open = target => Boolean(target) && target.state !== 'stopped' && target.took_seconds == null;

// `passed`: seconds since the timer was read, counted only while it counts.
const pressing = (target, passed) => {
  if (!open(target)) return null;
  const moved = target.counting ? passed : 0;
  if (target.state === 'missed') return { look: 'overdue', seconds: (target.over_seconds || 0) + moved, paused: false };
  const left = (target.remaining_seconds || 0) - moved;
  if (target.state === 'running' && left <= 0) return { look: 'overdue', seconds: -left, paused: false };
  return { look: left <= soonFrom(target.target_seconds) ? 'soon' : 'calm', seconds: left, paused: target.state === 'paused' };
};

// `known`: { timer, readAt } as the timer store keeps it. Answers null or
// { target: 'first_response' | 'resolution', look: 'calm' | 'soon' | 'overdue', seconds, paused }.
export const badgeOf = (known, { now = Date.now(), resolved = false } = {}) => {
  const timer = known?.timer;
  if (!timer || timer.stopped || resolved) return null;
  const passed = Math.max(0, Math.floor((now - (known.readAt || now)) / 1000));
  const first = pressing(timer.first_response, passed);
  if (first) return { target: 'first_response', ...first };
  const resolution = pressing(timer.resolution, passed);
  if (resolution && resolution.look !== 'calm') return { target: 'resolution', ...resolution };
  return null;
};

// When the badge of this timer can next change by something other than the
// clock the browser counts itself: milliseconds from `now`, or null when
// nothing is left to watch. At most a minute, as the list promises.
export const REFRESH_MS = 60_000;
export const nextReadIn = (known, now = Date.now()) => {
  const timer = known?.timer;
  if (!timer || timer.stopped) return null;
  const targets = [timer.first_response, timer.resolution].filter(open);
  if (targets.length === 0) return null;
  const waits = [REFRESH_MS - (now - (known.readAt || now))];
  if (timer.next_change_at) waits.push(new Date(timer.next_change_at).getTime() - now + 1000);
  return Math.max(1000, Math.min(...waits));
};
