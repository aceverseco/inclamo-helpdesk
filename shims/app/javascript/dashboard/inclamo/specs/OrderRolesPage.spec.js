import { mount, flushPromises } from '@vue/test-utils';
import OrderRolesPage from '../components/OrderRolesPage.vue';
import InclamoAPI from '../api';

vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', () => ({ default: { template: '<div><slot name="body" /></div>' } }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../api', () => ({ default: { getRoles: vi.fn(), giveRole: vi.fn(), takeRole: vi.fn() } }));

const member = { user_id: 2, name: 'Agent', email: 'agent@example.test', switchable: true, can_act: false };

describe('OrderRolesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    InclamoAPI.getRoles.mockResolvedValue({ data: { members: [{ ...member }] } });
  });

  it('shows a failed change and restores the saved checkbox value', async () => {
    InclamoAPI.giveRole.mockRejectedValue(new Error('network'));
    const wrapper = mount(OrderRolesPage);
    await flushPromises();
    const checkbox = wrapper.find('input');
    await checkbox.setValue(true);
    await flushPromises();

    expect(wrapper.find('[data-testid="inclamo-role-error"]').text()).toContain('could not be confirmed');
    expect(checkbox.element.checked).toBe(false);
    expect(checkbox.element.disabled).toBe(false);
  });

  it('allows a retry after a failed change and clears the error on success', async () => {
    InclamoAPI.giveRole.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce({ data: { members: [{ ...member, can_act: true }] } });
    const wrapper = mount(OrderRolesPage);
    await flushPromises();
    await wrapper.find('input').setValue(true);
    await flushPromises();
    await wrapper.find('input').setValue(true);
    await flushPromises();

    expect(InclamoAPI.giveRole).toHaveBeenCalledTimes(2);
    expect(wrapper.find('input').element.checked).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-role-error"]').exists()).toBe(false);
  });
});
