// Lengths of time for the SLA page and section. Targets are stored in
// seconds; the page offers minutes, hours and days.
import { t } from './i18n';

export const UNITS = { minutes: 60, hours: 3600, days: 86400 };

export const toSeconds = (value, unit) => {
  if (value === '' || value === null || value === undefined) return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number <= 0) return Number.NaN;
  return Math.round(number * UNITS[unit]);
};

// The largest unit that holds the target whole, for the form.
export const fromSeconds = seconds => {
  if (!seconds) return { value: '', unit: 'hours' };
  if (seconds % UNITS.days === 0) return { value: seconds / UNITS.days, unit: 'days' };
  if (seconds % UNITS.hours === 0) return { value: seconds / UNITS.hours, unit: 'hours' };
  return { value: Math.round((seconds / UNITS.minutes) * 100) / 100, unit: 'minutes' };
};

// "2 d 3 h", "1 h 30 min", "45 s": the two largest parts.
export const duration = total => {
  const seconds = Math.max(0, Math.floor(total || 0));
  const parts = [
    ['DAYS', Math.floor(seconds / 86400)],
    ['HOURS', Math.floor((seconds % 86400) / 3600)],
    ['MINUTES', Math.floor((seconds % 3600) / 60)],
    ['SECONDS', seconds % 60],
  ];
  const first = parts.findIndex(([, count]) => count > 0);
  if (first === -1) return t('SLA.SHORT.SECONDS', { count: 0 });
  return parts
    .slice(first, first + 2)
    .filter(([, count]) => count > 0)
    .map(([unit, count]) => t(`SLA.SHORT.${unit}`, { count }))
    .join(' ');
};
