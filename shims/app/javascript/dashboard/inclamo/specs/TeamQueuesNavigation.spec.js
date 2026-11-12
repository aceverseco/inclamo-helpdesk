import { mount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import InclamoAPI from '../api';
import { emitter } from 'shared/helpers/mitt';
import { loadTeamQueues, resetTeamQueues } from '../teamQueues';
import Navigation from '../workspace/Navigation.vue';
import ChatListHeader from 'dashboard/components/ChatListHeader.vue';

const { route, push } = vi.hoisted(() => ({ route: { name: 'home', path: '/', params: {}, query: {} }, push: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => route, useRouter: () => ({ push }) }));
vi.mock('../api', () => ({ default: { getTeamQueues: vi.fn() } }));
vi.mock('../workspace/useQueueCounts', async () => {
  const { ref } = await import('vue');
  return { useQueueCounts: () => ref(null) };
});
vi.mock('dashboard/components-next/sidebar/provider', () => ({ useSidebarContext: () => ({ isAllowed: () => true, resolvePath: () => '' }) }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return { useMapGetter: () => ref({ id: 1, accounts: [{ id: 1, role: 'agent' }] }), useStore: () => ({}) };
});
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return { useAccount: () => ({ accountId: ref(1), accountScopedRoute: (name, params) => ({ name, params: { accountId: 1, ...params } }) }) };
});
vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref } = await import('vue');
  return { useUISettings: () => ({ uiSettings: ref({}), updateUISettings: vi.fn() }) };
});

const queue = (id, key, name, count) => ({ id, key, name, position: id, hidden: false, ready: true, query: { payload: [] }, count });
const RouterLink = { name: 'RouterLink', props: ['to'], template: '<a :data-folder="to.params && to.params.id"><slot /></a>' };
const row = (wrapper, key) => wrapper.find(`[data-testid="inclamo-team-queue-${key}"]`);
const settle = async () => {
  await new Promise(resolve => setTimeout(resolve, 0));
  await nextTick();
};

describe('team queues in the workspace navigation', () => {
  const show = () => mount(Navigation, { props: { items: [] }, global: { stubs: { RouterLink } } });

  beforeEach(async () => {
    vi.clearAllMocks();
    resetTeamQueues();
    Object.assign(route, reactive({ name: 'home', params: {} }));
    InclamoAPI.getTeamQueues.mockResolvedValue({
      data: { queues: [queue(4, 'return', 'Return', 3), queue(1, 'urgent', 'Urgent', 0), queue(9, null, 'Wholesale', null)], limit: 20 },
    });
    await loadTeamQueues();
  });

  it('lists the queues in the order the account set, with their names and counts', () => {
    const wrapper = show();
    const rows = wrapper.findAll('.team-queue-nav .nav-row');

    expect(rows.map(one => one.find('span').text())).toEqual(['Return', 'Urgent', 'Wholesale']);
    expect(row(wrapper, 'return').find('.nav-count').text()).toBe('3');
    expect(row(wrapper, 'urgent').find('.nav-count').text()).toBe('0');
    expect(row(wrapper, '9').find('.nav-count').text()).toBe('—');
  });

  it('opens a queue on the folder route under its own id', () => {
    const wrapper = show();

    expect(row(wrapper, 'return').attributes('data-folder')).toBe('q-4');
  });

  it('marks the queue that is open, in its list and inside one of its conversations', () => {
    Object.assign(route, { name: 'folder_conversations', params: { id: 'q-1' } });
    let wrapper = show();
    expect(row(wrapper, 'urgent').classes()).toContain('selected');
    expect(row(wrapper, 'urgent').attributes('aria-current')).toBe('page');
    expect(row(wrapper, 'return').classes()).not.toContain('selected');

    Object.assign(route, { name: 'conversations_through_folders', params: { id: 'q-4', conversation_id: '7' } });
    wrapper = show();
    expect(row(wrapper, 'return').classes()).toContain('selected');
  });

  it('shows no team queue group while there is none', async () => {
    InclamoAPI.getTeamQueues.mockResolvedValue({ data: { queues: [], limit: 20 } });
    await loadTeamQueues();

    expect(show().find('.team-queue-nav').exists()).toBe(false);
  });

  it('leaves a queue that was hidden meanwhile for the main list, with the message', async () => {
    const toasts = [];
    emitter.on('newToastMessage', toast => toasts.push(toast.message));
    Object.assign(route, { name: 'folder_conversations', params: { id: 'q-1' } });
    show();

    InclamoAPI.getTeamQueues.mockResolvedValue({ data: { queues: [queue(4, 'return', 'Return', 3)], limit: 20 } });
    await loadTeamQueues();
    await settle();

    expect(push).toHaveBeenCalledWith({ name: 'home', params: { accountId: 1 } });
    expect(toasts).toEqual(['This queue is not available. Showing all conversations.']);
    emitter.all.delete('newToastMessage');
  });
});

describe('the conversation list header on a team queue', () => {
  const header = props =>
    mount(ChatListHeader, {
      props: {
        pageTitle: 'Urgent',
        hasAppliedFilters: false,
        hasActiveFolders: true,
        isOnExpandedLayout: false,
        conversationStats: { allCount: 2 },
        isListLoading: false,
        ...props,
      },
      global: {
        mocks: { $t: key => key },
        stubs: { NextButton: { props: ['icon'], template: '<button :data-icon="icon" />' }, SwitchLayout: true, ConversationBasicFilter: true },
      },
    });
  const icons = wrapper => wrapper.findAll('button[data-icon]').map(one => one.attributes('data-icon'));

  it('offers no edit or delete control', () => {
    expect(icons(header({ folderLocked: true }))).toEqual([]);
  });

  it('keeps both controls for a native folder', () => {
    expect(icons(header({ folderLocked: false }))).toEqual(['i-lucide-pen-line', 'i-lucide-trash-2']);
  });
});
