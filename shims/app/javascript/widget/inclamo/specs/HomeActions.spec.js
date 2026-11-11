import { mount, flushPromises } from '@vue/test-utils';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import HomeActions from '../HomeActions.vue';
import { takeStarter } from '../starters';
const mocks = vi.hoisted(() => ({
  dispatch: vi.fn(),
  push: vi.fn(),
  getters: {},
}));
vi.mock('vuex', () => ({ useStore: () => mocks }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: mocks.push }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
beforeEach(() => {
  mocks.getters = { 'conversationAttributes/getConversationParams': {} };
  mocks.dispatch.mockResolvedValue(true);
  mocks.push.mockResolvedValue();
  window.chatwootWebChannel = {
    preChatFormEnabled: false,
    allowMessagesAfterResolved: true,
    inclamoWidget: {
      starters: [
        {
          id: 'order',
          label: 'Order',
          message: 'Where is my order?',
          enabled: true,
        },
      ],
      links: [],
    },
  };
  window.inclamoWidgetPreview = false;
  takeStarter();
});
describe('Customer home actions', () => {
  it('waits for the required pre-chat form instead of sending a message', async () => {
    window.chatwootWebChannel.preChatFormEnabled = true;
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    expect(mocks.push).toHaveBeenCalledWith({ name: 'prechat-form' });
    expect(mocks.dispatch).not.toHaveBeenCalled();
    expect(takeStarter()).toBe('Where is my order?');
    expect(takeStarter()).toBe('');
  });
  it('sends through the native conversation action and suppresses rapid repeated clicks', async () => {
    let finish;
    mocks.dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    await wrapper.find('button').trigger('click');
    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
    expect(mocks.push).not.toHaveBeenCalled();
    finish(true);
    await flushPromises();
    expect(mocks.push).toHaveBeenCalledWith({ name: 'messages' });
  });
  it('shows a failure without retrying an uncertain request', async () => {
    mocks.dispatch.mockResolvedValue(false);
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(mocks.dispatch).toHaveBeenCalledTimes(1);
  });
  it('preserves the restriction on replies to resolved conversations', async () => {
    mocks.getters['conversationAttributes/getConversationParams'] = {
      id: 7,
      status: 'resolved',
    };
    window.chatwootWebChannel.allowMessagesAfterResolved = false;
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    expect(mocks.dispatch).not.toHaveBeenCalled();
    expect(mocks.push).toHaveBeenCalledWith({ name: 'messages' });
  });
  it('opens a published article without sending or creating a conversation', async () => {
    window.chatwootWebChannel.inclamoWidget = {
      links: [
        {
          id: 'help',
          label: 'Returns',
          kind: 'article',
          url: '/hc/shop/articles/returns',
          enabled: true,
        },
      ],
    };
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    expect(mocks.dispatch).not.toHaveBeenCalled();
    expect(mocks.push).toHaveBeenCalledWith({
      name: 'article-viewer',
      query: {
        link: expect.stringContaining(
          '/hc/shop/articles/returns?show_plain_layout=true'
        ),
      },
    });
  });
  it('opens HTTPS links without delivering messages, including an uppercase scheme', async () => {
    window.chatwootWebChannel.inclamoWidget = {
      links: [
        {
          id: 'external',
          label: 'Help page',
          kind: 'url',
          url: 'HTTPS://example.test/returns',
          enabled: true,
        },
      ],
    };
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    const wrapper = mount(HomeActions);
    await wrapper.find('button').trigger('click');
    expect(open).toHaveBeenCalledWith(
      'https://example.test/returns',
      '_blank',
      'noopener,noreferrer'
    );
    expect(mocks.dispatch).not.toHaveBeenCalled();
    open.mockRestore();
  });
});
