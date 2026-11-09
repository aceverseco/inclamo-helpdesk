import { mount, flushPromises } from '@vue/test-utils';
import OrderRolesPage from '../components/OrderRolesPage.vue';
import InclamoAPI from '../api';

vi.mock('dashboard/routes/dashboard/settings/SettingsLayout.vue', () => ({ default: { template: '<div><slot name="body" /></div>' } }));
vi.mock('dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue', () => ({ default: { template: '<div />' } }));
vi.mock('../api', () => ({ default: { getRoles: vi.fn(), setPermission: vi.fn() } }));

const member = { user_id: 2, name: 'Agent', email: 'agent@example.test', switchable: true, can_act: false, permissions: { address: false, refund: false } };
const box = wrapper => wrapper.find('[data-testid="inclamo-permission-2-address"]');
describe('OrderRolesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    InclamoAPI.getRoles.mockResolvedValue({ data: { members: [{ ...member }] } });
  });
  it('shows a failed change and restores the saved checkbox value', async () => {
    InclamoAPI.setPermission.mockRejectedValue(new Error('network'));
    const wrapper = mount(OrderRolesPage);
    await flushPromises();
    await box(wrapper).setValue(true);
    await flushPromises();
    expect(wrapper.find('[data-testid="inclamo-role-error"]').text()).toContain('could not be confirmed');
    expect(box(wrapper).element.checked).toBe(false);
    expect(box(wrapper).element.disabled).toBe(false);
  });
  it('retries one permission without granting unrelated operations', async () => {
    InclamoAPI.setPermission.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce({ data: { members: [{ ...member, permissions: { address: true, refund: false } }] } });
    const wrapper = mount(OrderRolesPage);
    await flushPromises();
    await box(wrapper).setValue(true);
    await flushPromises();
    await box(wrapper).setValue(true);
    await flushPromises();
    expect(InclamoAPI.setPermission).toHaveBeenLastCalledWith(2, 'address', true);
    expect(box(wrapper).element.checked).toBe(true);
    expect(wrapper.find('[data-testid="inclamo-permission-2-refund"]').element.checked).toBe(false);
    expect(wrapper.find('[data-testid="inclamo-role-error"]').exists()).toBe(false);
  });
  it('shows administrator rights as fixed and supports retrying a failed load', async () => {
    InclamoAPI.getRoles.mockRejectedValueOnce(new Error('network')).mockResolvedValueOnce({ data: { members: [{ ...member, switchable: false, permissions: { address: true } }] } });
    const wrapper = mount(OrderRolesPage);
    await flushPromises();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(box(wrapper).element.checked).toBe(true);
    expect(box(wrapper).element.disabled).toBe(true);
  });
});
