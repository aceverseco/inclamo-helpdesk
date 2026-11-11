// Authenticated, isolated renderer. It never loads the public visitor bootstrap.
import { createApp, reactive, ref, h, nextTick } from 'vue';
import { createI18n } from 'vue-i18n';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { directive as onClickaway } from 'vue3-click-away';
import { plugin, defaultConfig } from '@formkit/vue';
import { domPurifyConfig } from 'shared/helpers/HTMLSanitizer';
import {
  startsWithPlus,
  isPhoneNumberValidWithDialCode,
} from 'shared/helpers/Validators';
import App from '../widget/App.vue';
import store from '../widget/store';
import router from '../widget/router';
import messages from '../widget/i18n';
import { IFrameHelper } from '../widget/helpers/utils';
import { API } from '../widget/helpers/axios';
import { bubbleSVG, createBubbleIcon } from '../sdk/bubbleHelpers';
import { decorateLauncher, resolveSettings } from '../sdk/inclamoWidget';
import sdkCSS from '../sdk/sdk.css?inline';
import customCSS from '../sdk/inclamoWidget.css?inline';

const previewOrigin = new URL(document.baseURI).origin;
window.chatwootWebChannel = reactive(window.chatwootWebChannel);
window.$chatwoot = {
  position: 'right',
  type: 'standard',
  baseUrl: previewOrigin,
  inclamoWidget: {},
};
const open = ref(true);
const note = ref('');
const mobile = ref(false);
const nativeApp = ref(null);
IFrameHelper.sendMessage = message => {
  if (message.event === 'closeWindow') open.value = false;
};
router.beforeEach(to => {
  if (to.name === 'article-viewer') {
    note.value = 'Preview only · Help article opens here on your website.';
    return false;
  }
  return true;
});
const i18n = createI18n({
  legacy: false,
  locale: window.chatwootWebChannel.locale || 'en',
  messages,
});
const nativeDispatch = store.dispatch.bind(store);
let messageId = 1;
const push = content => {
  messageId += 1;
  store.commit('conversation/pushMessageToConversation', {
    id: messageId,
    content,
    message_type: 0,
    created_at: Date.now() / 1000,
    status: 'sent',
    content_type: 'text',
    content_attributes: {},
  });
};
// No production HTTP adapter is reachable from preview components.
API.defaults.adapter = async () => {
  throw new Error('Network delivery is disabled in widget preview');
};
store.dispatch = (type, payload) => {
  if (type.startsWith('appConfig/')) return nativeDispatch(type, payload);
  if (
    type === 'conversation/createConversation' ||
    type === 'conversation/sendMessage'
  ) {
    push(payload.message || payload.content);
    store.commit('conversationAttributes/SET_CONVERSATION_ATTRIBUTES', {
      id: 1,
      status: 'open',
    });
    router.replace({ name: 'messages' });
    return Promise.resolve(true);
  }
  if (type === 'conversation/clearConversations')
    store.commit('conversation/clearConversations');
  return Promise.resolve();
};
const Shell = {
  setup() {
    return () => [
      h(
        'div',
        {
          id: 'cw-widget-holder',
          class: ['woot-widget-holder', !open.value && 'woot--hide'],
        },
        [
          h('div', { class: 'preview-topline' }, [
            h('span', 'Preview'),
            h(
              'button',
              {
                'aria-label': 'Close preview',
                onClick: () => {
                  open.value = false;
                },
              },
              '×'
            ),
          ]),
          h('div', { class: 'preview-app' }, [h(App, { ref: nativeApp })]),
        ]
      ),
      h('div', {
        id: 'cw-bubble-holder',
        class: [
          'woot--bubble-holder',
          mobile.value && open.value && 'woot-hidden',
        ],
      }),
      note.value &&
        h('div', { class: 'preview-note', role: 'status' }, note.value),
    ];
  },
};
const app = createApp(Shell);
app
  .use(i18n)
  .use(store)
  .use(router)
  .use(VueDOMPurifyHTML, domPurifyConfig)
  .directive('on-clickaway', onClickaway);
app.use(
  plugin,
  defaultConfig({
    rules: {
      startsWithPlus: ({ value }) => startsWithPlus(value),
      isValidPhoneNumber: ({ value }) => isPhoneNumberValidWithDialCode(value),
    },
  })
);
const styles = document.createElement('style');
styles.textContent =
  sdkCSS +
  customCSS +
  `
html,body,#app {height:100%;margin:0} body {background:#f3f5f8 !important;overflow:hidden}
#cw-widget-holder {position:absolute !important;inset:12px 12px auto !important;bottom:calc(min(var(--inclamo-widget-y,20px),calc(100dvh - 350px)) + 84px) !important;width:auto !important;height:auto !important;min-height:0 !important;max-height:none !important;overflow:hidden;border-radius:14px;box-shadow:0 4px 18px #101b3d16;display:flex;flex-direction:column}
body[data-mobile="true"] #cw-widget-holder {inset:12px !important}
#cw-widget-holder.woot--hide {display:none !important}
#cw-widget-holder>.preview-app {flex:1;min-height:0;overflow:hidden}
.preview-topline {display:flex;align-items:center;justify-content:space-between;padding:4px 10px;background:white;color:#6b7280;font:11px system-ui;flex-shrink:0}.preview-topline button {font-size:22px;width:28px;cursor:pointer}
#cw-bubble-holder .woot-widget-bubble {display:flex !important;align-items:center;justify-content:center}
.preview-note {position:absolute;bottom:84px;left:18px;right:18px;padding:12px;background:white;border:1px solid #d5dfec;border-radius:10px;font:12px system-ui}
`;
document.head.append(styles);
app.mount('#app');
document.addEventListener('click', event => {
  if (event.target.closest('a')) {
    event.preventDefault();
    note.value = 'Preview only · Links do not leave this editor.';
  }
});
function launcher() {
  const holder = document.getElementById('cw-bubble-holder');
  holder.replaceChildren();
  const button = createBubbleIcon({
    className: 'woot-widget-bubble',
    path: bubbleSVG,
    target: document.createElement('button'),
  });
  button.style.background = window.chatwootWebChannel.widgetColor;
  button.onclick = () => {
    open.value = !open.value;
    note.value = '';
  };
  holder.append(button);
  // The editor is a presentation preview, not a merchant page pathname.
  decorateLauncher({ checkVisibility: false });
  const label = button.querySelector('#woot-widget--expanded__text');
  if (label)
    label.textContent = window.$chatwoot.launcherTitle || 'Chat with us';
}
window.addEventListener('inclamo-preview-link', event => {
  note.value = `Preview link: ${event.detail.label}`;
});
window.addEventListener('message', async event => {
  if (
    event.origin !== previewOrigin ||
    event.source !== window.parent ||
    event.data?.type !== 'inclamo-widget-preview'
  )
    return;
  const value = event.data;
  Object.assign(window.chatwootWebChannel, value.channel, {
    websiteName: value.native.name,
    welcomeTitle: value.native.welcome_title,
    welcomeTagline: value.native.welcome_tagline,
    widgetColor: value.native.widget_color,
    replyTime: value.native.reply_time,
    avatarUrl: value.avatar || '',
    portal: value.portal,
    inclamoWidget: { ...value.settings, icon_url: value.icon },
  });
  Object.assign(window.$chatwoot, resolveSettings(window.chatwootWebChannel), {
    inclamoWidget: window.chatwootWebChannel.inclamoWidget,
  });
  mobile.value = value.mobile;
  document.body.dataset.mobile = String(value.mobile);
  if (nativeApp.value) nativeApp.value.isMobile = value.mobile;
  store.commit(
    'article/setArticles',
    (value.articles || []).map(article => ({
      ...article,
      link: `/hc/${value.portal?.slug}/articles/${article.slug}`,
    }))
  );
  i18n.global.locale.value = window.$chatwoot.locale;
  await store.dispatch('appConfig/setWidgetColor', value.native.widget_color);
  await store.dispatch('appConfig/setAppConfig', {
    darkMode: window.$chatwoot.darkMode,
    position: value.settings.position,
    showUnreadMessagesDialog: false,
  });
  document.documentElement.style.setProperty(
    '--widget-color',
    value.native.widget_color
  );
  store.commit(
    'agent/setAgents',
    value.online
      ? [
          {
            id: 1,
            name: 'Support',
            availability_status: 'online',
            avatar_url: '',
          },
        ]
      : []
  );
  store.commit('agent/setHasFetched', true);
  if (
    value.screen === 'messages' &&
    !store.getters['conversation/getConversationSize']
  )
    push('This is a preview message.');
  await router.replace({ name: value.screen });
  note.value = '';
  await nextTick();
  launcher();
});
window.parent.postMessage({ type: 'inclamo-preview-ready' }, previewOrigin);
