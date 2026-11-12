import { reactive } from 'vue';

// This state has no customer composer/store dependency and is never persisted.
export const supportUI = reactive({ sequence: 0, reference: null, capturing: false });
export function openSupport(reference = null) {
  supportUI.reference = reference;
  supportUI.sequence += 1;
}
export const supportURL = accountId => `/api/v1/accounts/${accountId}/inclamo/support`;
export function submissionId() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
export function locationContext(path) {
  if (/\/conversations\/\d+/.test(path)) return 'conversation';
  if (/\/settings(?:\/|$)/.test(path)) return 'settings';
  if (/\/contacts(?:\/|$)/.test(path)) return 'contacts';
  if (/\/reports(?:\/|$)/.test(path)) return 'reports';
  if (/\/(dashboard|inbox)(?:\/|$)/.test(path)) return 'inbox';
  return 'workspace';
}
