import { t, has } from './i18n';

export const money = (amount, currency) => {
  if (amount === undefined || amount === null || amount === '') return '';
  const value = Number(amount);
  if (Number.isNaN(value) || !currency) return `${amount} ${currency || ''}`.trim();
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(value);
  } catch (error) {
    return `${amount} ${currency}`;
  }
};

export const date = value => {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '' : parsed.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

export const dateTime = value => {
  if (!value) return '';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime())
    ? ''
    : parsed.toLocaleString(undefined, { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
};

export const status = value => {
  if (!value) return '';
  if (has(`STATUS.${value}`)) return t(`STATUS.${value}`);
  const words = String(value).toLowerCase().replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
};

// A new id for one confirmation; a repeated request carries the same one.
export const newActionId = () => {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `a-${Date.now().toString(16)}-${Math.random().toString(16).slice(2, 14)}`;
};
