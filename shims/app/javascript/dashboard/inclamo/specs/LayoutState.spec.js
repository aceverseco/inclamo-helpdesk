import { mount, flushPromises } from '@vue/test-utils';
import { defineComponent, h, nextTick, reactive, ref } from 'vue';
import { stateFor, useWorkspaceLayout } from '../widgets/layoutState';

const route = reactive({ params: { accountId: '41' } });
const user = ref({ id: 5 });
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/composables/store', () => ({ useMapGetter: () => user }));

const Host = defineComponent({
  setup() {
    useWorkspaceLayout();
    return () => h('span');
  },
});

describe('shared workspace layout', () => {
  const get = vi.fn();
  beforeEach(() => {
    get.mockReset().mockResolvedValue({ data: { revision: 1 } });
    vi.stubGlobal('axios', { get });
  });
  afterEach(() => vi.unstubAllGlobals());

  it('counts a host once when the signed-in user goes away before the host unmounts', async () => {
    const first = mount(Host);
    await flushPromises();
    const state = stateFor('41', 5);
    expect(state.users).toBe(1);

    user.value = null;
    await nextTick();
    expect(state.users).toBe(0);
    first.unmount();
    expect(state.users).toBe(0);

    user.value = { id: 5 };
    get.mockClear();
    const second = mount(Host);
    await flushPromises();
    expect(state.users).toBe(1);
    expect(get).toHaveBeenCalledWith('/api/v1/accounts/41/inclamo/workspace_layout');
    second.unmount();
    expect(state.users).toBe(0);
  });
});
