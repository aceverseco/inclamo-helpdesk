// Stands in for Chatwoot's useUISettings.js (kept beside this file as
// useUISettings.chatwoot.js): the overlay's sections of the customer panel
// (dashboard/inclamo/sidebarSections) come first in its default order.
// Everything else is Chatwoot's.
import { computed } from 'vue';
import sidebarSections from 'dashboard/inclamo/sidebarSections';
import {
  DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER as CHATWOOT_ORDER,
  useUISettings as useChatwootUISettings,
} from './useUISettings.chatwoot';

export const DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER = Object.freeze([
  ...sidebarSections.map(({ name }) => ({ name })),
  ...CHATWOOT_ORDER,
]);

export function useUISettings() {
  const settings = useChatwootUISettings();

  // As Chatwoot orders the panel, over the longer default: an order the agent
  // saved is kept, and a section it does not name yet is added at its end.
  const conversationSidebarItemsOrder = computed(() => {
    const saved = settings.uiSettings.value.conversation_sidebar_items_order;
    if (!saved) return [...DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER];
    const order = [...saved];
    DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER.forEach(item => {
      if (!order.find(one => one.name === item.name)) order.push(item);
    });
    return order;
  });

  return { ...settings, conversationSidebarItemsOrder };
}

// The rest is Chatwoot's, as it is.
export {
  DEFAULT_CONTACT_SIDEBAR_ITEMS_ORDER,
} from './useUISettings.chatwoot';
