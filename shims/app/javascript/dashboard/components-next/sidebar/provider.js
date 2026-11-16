// Stands in for Chatwoot's sidebar/provider.js (kept as provider.chatwoot.js):
// the navigation's default width is the workspace's, 218px.
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useSidebarResize as useChatwootSidebarResize } from './provider.chatwoot';

const DEFAULT_WIDTH = 218;

export function useSidebarResize() {
  const { uiSettings, updateUISettings } = useUISettings();
  const resize = useChatwootSidebarResize();

  if (!uiSettings.value.sidebar_width) resize.sidebarWidth.value = DEFAULT_WIDTH;

  const snapToExpanded = () => {
    resize.sidebarWidth.value = DEFAULT_WIDTH;
    updateUISettings({ sidebar_width: DEFAULT_WIDTH });
  };

  return { ...resize, snapToExpanded, DEFAULT_WIDTH };
}

// The rest is Chatwoot's, as it is.
export {
  usePopoverState,
  useSidebarContext,
  provideSidebarContext,
} from './provider.chatwoot';
