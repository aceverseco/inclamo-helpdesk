import { mount } from '@vue/test-utils';
import { reactive } from 'vue';
import InclamoAPI from '../api';
import { loadTeamQueues, resetTeamQueues } from '../teamQueues';
import WorkspaceHeader from '../components/WorkspaceHeader.vue';

const { route } = vi.hoisted(() => ({ route: { name: 'home', path: '/app/accounts/1/dashboard', params: {}, query: {} } }));
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../api', () => ({ default: { getTeamQueues: vi.fn() } }));
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  return { useMapGetter: () => ref({ id: 1, name: 'Staff' }) };
});

const stubs = { Avatar: true, WorkspaceTools: true, WidgetHost: true, SupportLauncher: true };
const crumbs = wrapper => wrapper.find('.inclamo-workspace-breadcrumb').text();

describe('the breadcrumb of the workspace header', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    resetTeamQueues();
    Object.assign(route, reactive({ name: 'home', path: '/app/accounts/1/dashboard', params: {} }));
    InclamoAPI.getTeamQueues.mockResolvedValue({
      data: { queues: [{ id: 4, key: 'return', name: 'Returns desk', position: 1, hidden: false, query: { payload: [] }, count: 0 }], limit: 20 },
    });
    await loadTeamQueues();
  });

  it('ends with "All conversations" in the main list', () => {
    const wrapper = mount(WorkspaceHeader, { global: { stubs } });

    expect(crumbs(wrapper)).toContain('All conversations');
    expect(wrapper.find('[data-testid="inclamo-breadcrumb-queue"]').exists()).toBe(false);
  });

  it('ends with the name of the team queue that is open, in its list and inside a conversation', () => {
    Object.assign(route, { name: 'folder_conversations', path: '/app/accounts/1/custom_view/q-4', params: { id: 'q-4' } });
    let wrapper = mount(WorkspaceHeader, { global: { stubs } });
    expect(wrapper.find('[data-testid="inclamo-breadcrumb-queue"]').text()).toBe('Returns desk');
    expect(crumbs(wrapper)).not.toContain('All conversations');

    Object.assign(route, { name: 'conversations_through_folders', path: '/app/accounts/1/custom_view/q-4/conversations/7', params: { id: 'q-4', conversation_id: 7 } });
    wrapper = mount(WorkspaceHeader, { global: { stubs } });
    expect(wrapper.find('[data-testid="inclamo-breadcrumb-queue"]').text()).toBe('Returns desk');
  });

  it('shows no queue name for a native folder', () => {
    Object.assign(route, { name: 'folder_conversations', path: '/app/accounts/1/custom_view/12', params: { id: '12' } });
    const wrapper = mount(WorkspaceHeader, { global: { stubs } });

    expect(wrapper.find('[data-testid="inclamo-breadcrumb-queue"]').exists()).toBe(false);
  });
});
