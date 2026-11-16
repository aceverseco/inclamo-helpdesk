import { h } from 'vue';
import { mount } from '@vue/test-utils';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';

// The overlay's stand-ins that render Chatwoot's component unchanged, with a
// label of the workspace theme on its root (docs/chatwoot-files.md).
const standIns = {
  SettingsWrapper: () => import('dashboard/routes/dashboard/settings/SettingsWrapper.vue'),
  SettingsHeader: () => import('dashboard/routes/dashboard/settings/SettingsHeader.vue'),
  ConversationSidebar: () => import('dashboard/components/widgets/conversation/ConversationSidebar.vue'),
  menuItem: () => import('dashboard/components/widgets/conversation/contextMenu/menuItem.vue'),
};

describe('stand-ins that render Chatwoot\'s component', () => {
  // The router calls a function it is given as a page to load, so a stand-in
  // written as a function would never be rendered as a page.
  it.each(Object.keys(standIns))('%s is a component, not a function', async name => {
    const component = (await standIns[name]()).default;

    expect(typeof component).toBe('object');
    expect(component.setup).toBeTypeOf('function');
  });

  it('pass props through and put the label on the root of Chatwoot\'s component', async () => {
    const MenuItem = (await standIns.menuItem()).default;

    const wrapper = mount(MenuItem, {
      props: { option: { label: 'Assign to me' }, variant: 'default' },
      attrs: { class: 'from-parent' },
      global: { stubs: { 'fluent-icon': true, Avatar: true, Icon: true } },
    });

    expect(wrapper.attributes('data-inclamo-control')).toBe('context-menu-item');
    expect(wrapper.classes()).toEqual(expect.arrayContaining(['menu', 'from-parent']));
    expect(wrapper.text()).toContain('Assign to me');
  });

  it('are rendered by the router as a page with the pages nested in it', async () => {
    const SettingsWrapper = (await standIns.SettingsWrapper()).default;
    const router = createRouter({
      history: createMemoryHistory(),
      routes: [{ path: '/settings', component: SettingsWrapper, children: [{ path: '', component: { render: () => h('p', 'The page') } }] }],
    });
    router.push('/settings');
    await router.isReady();

    const wrapper = mount({ render: () => h(RouterView) }, { global: { plugins: [router] } });
    await new Promise(resolve => { setTimeout(resolve, 0); });

    expect(wrapper.find('.inclamo-settings-page').exists()).toBe(true);
    expect(wrapper.find('.inclamo-settings-page').text()).toContain('The page');
  });
});
