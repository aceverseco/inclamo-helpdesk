// Dates, times and money are written the way the interface language writes
// them, not the browser's.
import { formatLanguage } from './i18n';

export const money = (amount, currency) => {
  if (amount === undefined || amount === null || amount === '') return '';
  const value = Number(amount);
  if (Number.isNaN(value) || !currency) return `${amount} ${currency || ''}`.trim();
  try {
    return new Intl.NumberFormat(formatLanguage(), { style: 'currency', currency }).format(value);
  } catch (error) {
    return `${amount} ${currency}`;
  }
};

export const date = value => {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toLocaleDateString(formatLanguage(), { year: 'numeric', month: 'short', day: 'numeric' });
};

export const dateTime = value => {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? ''
    : parsed.toLocaleString(formatLanguage(), { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
};

// A new id for one confirmation; a repeated request carries the same one.
export const newActionId = () => {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `a-${Date.now().toString(16)}-${Math.random().toString(16).slice(2, 14)}`;
};
