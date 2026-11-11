<script setup>
/* global axios */
import { t } from '../i18n';
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import {
  useRoute,
  useRouter,
  onBeforeRouteLeave,
  onBeforeRouteUpdate,
} from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { Button } from '../ui/button';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../ui/tabs';
import Appearance from './Appearance.vue';
import HomeEditor from './HomeEditor.vue';
import Behavior from './Behavior.vue';
import Preview from './Preview.vue';

const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const websites = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::WebWidget')
);
const selected = computed(() =>
  String(route.query.inbox || websites.value[0]?.id || '')
);
const saved = ref(null);
const draft = ref(null);
const html = ref('');
const initial = ref('');
const error = ref('');
const loading = ref(false);
const busy = ref(false);
const published = ref(false);
const copied = ref(false);
const tab = ref('appearance');
const dirty = computed(
  () => draft.value && JSON.stringify(draft.value) !== initial.value
);
const url = computed(
  () =>
    `/api/v1/accounts/${accountId.value}/inclamo/website_widgets/${selected.value}`
);
const inboxUrl = computed(
  () => `/app/accounts/${accountId.value}/settings/inboxes/${selected.value}`
);
let generation = 0;
async function load() {
  generation += 1;
  const mine = generation;
  saved.value = null;
  draft.value = null;
  html.value = '';
  error.value = '';
  busy.value = false;
  published.value = false;
  loading.value = false;
  if (
    !selected.value ||
    !websites.value.some(i => String(i.id) === selected.value)
  ) {
    if (selected.value && websites.value.length)
      error.value = 'Choose a website in this account.';
    return;
  }
  loading.value = true;
  try {
    const [config, preview] = await Promise.all([
      axios.get(url.value),
      axios.get(`${url.value}/preview`, { responseType: 'text' }),
    ]);
    if (mine !== generation) return;
    saved.value = config.data;
    html.value = preview.data;
    draft.value = structuredClone({
      settings: config.data.settings,
      native: config.data.native,
    });
    initial.value = JSON.stringify(draft.value);
  } catch (e) {
    if (mine === generation)
      error.value =
        e.response?.data?.error || 'Could not load widget settings.';
  } finally {
    if (mine === generation) loading.value = false;
  }
}
// A direct URL can arrive before the native inbox store has finished loading.
const selectedExists = computed(() =>
  websites.value.some(i => String(i.id) === selected.value)
);
watch([accountId, selected, selectedExists], load, { immediate: true });
async function publish() {
  busy.value = true;
  error.value = '';
  published.value = false;
  const mine = generation;
  try {
    const configuration = JSON.parse(JSON.stringify(draft.value));
    ['icon_image', 'avatar_image'].forEach(key => {
      if (configuration[key]) delete configuration[key].preview;
    });
    const { data } = await axios.patch(url.value, {
      configuration: { ...configuration, revision: saved.value.revision },
    });
    if (mine !== generation) return;
    saved.value = data;
    draft.value = structuredClone({
      settings: data.settings,
      native: data.native,
    });
    initial.value = JSON.stringify(draft.value);
    published.value = true;
  } catch (e) {
    if (mine === generation)
      error.value =
        e.response?.data?.error || 'Could not save. Your draft is still here.';
  } finally {
    if (mine === generation) busy.value = false;
  }
}
async function chooseImage(key, event) {
  const mine = generation;
  const file = event.target.files?.[0];
  if (!file) return;
  if (file.size > 1048576) {
    error.value = 'Choose an image up to 1 MB.';
    return;
  }
  const preview = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
  if (mine !== generation || !draft.value) return;
  draft.value[key] = { data: preview.split(',')[1], preview };
  delete draft.value[key === 'icon_image' ? 'remove_icon' : 'remove_avatar'];
  if (key === 'icon_image') draft.value.settings.icon = 'custom';
}
function removeImage(kind) {
  delete draft.value[kind === 'icon' ? 'icon_image' : 'avatar_image'];
  draft.value[`remove_${kind}`] = true;
  if (kind === 'icon') draft.value.settings.icon = 'chat';
}
function canLeave() {
  // Native confirmation keeps the draft in place until the administrator decides.
  // eslint-disable-next-line no-alert
  return !dirty.value || window.confirm('Discard unsaved widget changes?');
}
onBeforeRouteLeave(canLeave);
onBeforeRouteUpdate((to, from) => to.fullPath === from.fullPath || canLeave());
function beforeUnload(e) {
  if (dirty.value) {
    e.preventDefault();
    e.returnValue = '';
  }
}
onMounted(() => window.addEventListener('beforeunload', beforeUnload));
onBeforeUnmount(() => {
  generation += 1;
  window.removeEventListener('beforeunload', beforeUnload);
});
const snippet = computed(() =>
  saved.value
    ? `<script>\n(function(d,t){\n  var base=${JSON.stringify(window.location.origin)};\n  var s=d.createElement(t);s.src=base+'/packs/js/sdk.js';s.async=true;\n  s.onload=function(){window.chatwootSDK.run({baseUrl:base,websiteToken:${JSON.stringify(saved.value.website_token)}})};\n  d.head.appendChild(s);\n})(document,'script');\n<${'/'}script>`
    : ''
);
async function copy() {
  await navigator.clipboard.writeText(snippet.value);
  copied.value = true;
}
const customLauncher =
  "window.chatwootSettings = { hideMessageBubble: true };\n// After chatwoot:ready, call this from your button:\nwindow.$chatwoot.toggle('open');";
</script>

<template>
  <div class="inclamo-widget-editor">
    <header class="widget-editor-header">
      <div>
        <span class="widget-eyebrow">
          {{ t('WEBSITE_WIDGET.CUSTOMER_EXPERIENCE') }}
        </span>
        <h1>{{ t('WEBSITE_WIDGET.WEBSITE_WIDGET') }}</h1>
        <p>{{ t('WEBSITE_WIDGET.MAKE_YOUR_WEBSITE_CHAT_FEEL_AT_HOME') }}</p>
      </div>
      <Button :disabled="!dirty || busy || loading" @click="publish">
        {{
          busy ? t('WEBSITE_WIDGET.SAVING') : t('WEBSITE_WIDGET.SAVE_CHANGES')
        }}
      </Button>
    </header>
    <div class="widget-toolbar">
      <label>
        {{ t('WEBSITE_WIDGET.WEBSITE') }}
        <select
          :value="selected"
          :disabled="busy"
          @change="
            router.replace({
              query: { ...route.query, inbox: $event.target.value },
            })
          "
        >
          <option
            v-for="inbox in websites"
            :key="inbox.id"
            :value="String(inbox.id)"
          >
            {{ inbox.name }}
          </option>
        </select>
      </label>
      <span v-if="dirty" class="widget-draft-status">
        {{ t('WEBSITE_WIDGET.UNSAVED_CHANGES') }}
      </span>
      <span v-else-if="published" role="status">
        {{ t('WEBSITE_WIDGET.CHANGES_SAVED') }}
      </span>
    </div>
    <p v-if="error" role="alert" class="widget-error">
      {{ error }}
      <Button variant="outline" @click="canLeave() && load()">
        {{ t('WEBSITE_WIDGET.RELOAD_SAVED_SETTINGS') }}
      </Button>
    </p>
    <p v-if="loading" role="status">{{ t('WEBSITE_WIDGET.LOADING_WIDGET') }}</p>
    <div v-else-if="!websites.length" class="widget-empty">
      <h2>{{ t('WEBSITE_WIDGET.CONNECT_YOUR_FIRST_WEBSITE') }}</h2>
      <p>
        {{
          t(
            'WEBSITE_WIDGET.A_WEBSITE_INBOX_COLLECTS_CONVERSATIONS_FROM_YOUR_CHAT_WIDGET'
          )
        }}
      </p>
      <router-link
        :to="`/app/accounts/${accountId}/settings/inboxes/new/website`"
      >
        {{ t('WEBSITE_WIDGET.ADD_WEBSITE_CHANNEL') }}
      </router-link>
    </div>
    <div v-else-if="draft && saved" class="widget-editor-layout">
      <Tabs v-model="tab" class="widget-editor-main">
        <TabsList class="widget-tabs">
          <TabsTrigger value="appearance">
            {{ t('WEBSITE_WIDGET.APPEARANCE') }}
          </TabsTrigger>
          <TabsTrigger value="home">
            {{ t('WEBSITE_WIDGET.HOME_SCREEN') }}
          </TabsTrigger>
          <TabsTrigger value="behavior">
            {{ t('WEBSITE_WIDGET.BEHAVIOR') }}
          </TabsTrigger>
          <TabsTrigger value="installation">
            {{ t('WEBSITE_WIDGET.INSTALLATION') }}
          </TabsTrigger>
        </TabsList>
        <TabsContent value="appearance">
          <Appearance
            v-model:draft="draft"
            :saved="saved"
            @image="chooseImage"
            @remove="removeImage"
          />
        </TabsContent>
        <TabsContent value="home">
          <HomeEditor v-model:draft="draft" :saved="saved" />
        </TabsContent>
        <TabsContent value="behavior">
          <Behavior
            v-model:draft="draft"
            :saved="saved"
            :inbox-url="inboxUrl"
          />
        </TabsContent>
        <TabsContent value="installation">
          <section class="widget-form-stack">
            <h2>{{ t('WEBSITE_WIDGET.INSTALL_ONCE_CUSTOMIZE_HERE') }}</h2>
            <p>
              {{
                t(
                  'WEBSITE_WIDGET.ADD_THIS_SNIPPET_BEFORE_THE_CLOSING_BODY_TAG_ON_YOUR_WEBSITE_SAVE'
                )
              }}
            </p>
            <pre>{{ snippet }}</pre>
            <Button variant="outline" @click="copy">
              {{
                copied
                  ? t('WEBSITE_WIDGET.COPIED')
                  : t('WEBSITE_WIDGET.COPY_INSTALLATION_CODE')
              }}
            </Button>
            <h3>{{ t('WEBSITE_WIDGET.ALREADY_INSTALLED') }}</h3>
            <p>
              {{
                t(
                  'WEBSITE_WIDGET.EXISTING_INSTALLATIONS_KEEP_WORKING_SETTINGS_EXPLICITLY_WRITTEN_I'
                )
              }}
              <code>{{ t('WEBSITE_WIDGET.WINDOW_CHATWOOTSETTINGS') }}</code>
              {{
                t(
                  'WEBSITE_WIDGET.TAKE_PRIORITY_OVER_THIS_EDITOR_REMOVE_THOSE_PRESENTATION_OPTIONS_'
                )
              }}
            </p>
            <h3>{{ t('WEBSITE_WIDGET.OPEN_CHAT_FROM_YOUR_OWN_BUTTON') }}</h3>
            <pre>{{ customLauncher }}</pre>
            <p>
              {{
                t(
                  'WEBSITE_WIDGET.SET_THE_HIDE_OPTION_BEFORE_LOADING_THE_WIDGET_YOUR_OWN_BUTTON_CAN'
                )
              }}
            </p>
            <router-link
              :to="`${inboxUrl}/configuration`"
              class="widget-native-link"
            >
              {{ t('WEBSITE_WIDGET.DOMAINS_AND_IDENTITY_VERIFICATION') }}
            </router-link>
          </section>
        </TabsContent>
      </Tabs>
      <Preview :draft="draft" :saved="saved" :html="html" />
    </div>
  </div>
</template>

<style>
.inclamo-widget-editor {
  width: 100%;
  color: rgb(var(--slate-12));
  font-size: 14px;
}
.widget-editor-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 24px;
}
.widget-eyebrow {
  letter-spacing: 0.13em;
  font-size: 10px;
  font-weight: 600;
  color: rgb(var(--slate-10));
}
.widget-editor-header h1 {
  font-size: 26px;
  margin: 6px 0;
  letter-spacing: -0.035em;
  font-weight: 600;
}
.widget-editor-header p,
.widget-section-heading p {
  color: rgb(var(--slate-11));
  font-size: 13px;
  margin: 4px 0;
}
.widget-toolbar {
  display: flex;
  align-items: center;
  gap: 20px;
  margin-bottom: 24px;
}
.widget-toolbar label {
  display: flex;
  align-items: center;
  gap: 12px;
}
.widget-draft-status {
  color: rgb(var(--inclamo-orange));
  font-size: 12px;
}
.widget-editor-layout {
  display: grid;
  grid-template-columns: minmax(280px, 1fr) 410px;
  gap: 28px;
  align-items: start;
}
.widget-editor-main {
  min-width: 0;
}
.widget-tabs {
  display: flex;
  width: 100%;
  height: auto;
  flex-wrap: wrap;
  padding: 4px;
  margin-bottom: 24px;
}
.widget-tabs [role='tab'] {
  flex: 1;
  padding: 8px;
}
.widget-form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 24px 20px;
}
.widget-form-stack {
  display: flex;
  flex-direction: column;
  gap: 20px;
}
.widget-field {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
  font-size: 13px;
  font-weight: 500;
}
.widget-field input,
.widget-field textarea,
.widget-field select {
  font-weight: 400;
  width: 100%;
  box-sizing: border-box;
}
.inclamo-widget-editor select,
.inclamo-widget-editor textarea,
.widget-field input[type='number'] {
  padding: 9px 12px;
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  background: rgb(var(--inclamo-field));
  color: inherit;
  margin: 0;
  font-size: 13px;
}
.widget-field small,
.widget-form-stack > small {
  color: rgb(var(--slate-11));
  font-size: 12px;
  font-weight: 400;
}
.widget-image-sample {
  width: 64px;
  height: 64px;
  object-fit: contain;
  background: white;
  border: 1px solid rgb(var(--border-weak));
  border-radius: 10px;
}
.widget-section-heading {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding-top: 18px;
  border-top: 1px solid rgb(var(--border-weak));
}
.widget-section-heading h3,
.widget-form-stack h2,
.widget-form-stack h3 {
  font-size: 15px;
  font-weight: 600;
  margin: 0;
}
.widget-entry {
  padding: 16px;
  border: 1px solid rgb(var(--border-weak));
  border-radius: 12px;
  display: grid;
  gap: 14px;
}
.widget-entry-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.widget-entry-actions label {
  margin-inline-end: auto;
  font-size: 12px;
}
.widget-entry-actions input,
.widget-preview-controls input {
  vertical-align: middle;
  margin-inline-end: 6px;
}
.widget-rule {
  display: flex;
  gap: 8px;
}
.widget-native-link {
  display: flex;
  justify-content: space-between;
  padding: 14px 0;
  border-bottom: 1px solid rgb(var(--border-weak));
}
.widget-preview-panel {
  position: sticky;
  top: 0;
  border: 1px solid rgb(var(--border-weak));
  border-radius: 16px;
  padding: 14px;
  background: rgb(var(--surface-1));
  overflow: hidden;
}
.widget-preview-heading {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
  margin-bottom: 12px;
}
.widget-preview-heading span,
.widget-preview-note {
  font-size: 11px;
  color: rgb(var(--slate-10));
}
.widget-preview-controls {
  display: flex;
  justify-content: center;
  align-items: center;
  gap: 8px;
  margin-bottom: 10px;
}
.widget-preview-panel iframe {
  display: block;
  height: 650px;
  max-width: 100%;
  margin: auto;
  border: 0;
  border-radius: 12px;
  background: #f4f5f7;
}
.widget-preview-note {
  text-align: center;
  margin-top: 10px;
}
.widget-error {
  border: 1px solid #e9b2ad;
  padding: 12px;
  border-radius: 8px;
  margin-bottom: 16px;
}
.widget-empty {
  padding: 24px;
  background: rgb(var(--inclamo-field));
  border-radius: 12px;
  color: rgb(var(--slate-11));
}
.widget-form-stack pre {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  padding: 16px;
  background: rgb(var(--inclamo-field));
  border-radius: 12px;
  font-size: 11px;
}
@media (max-width: 1100px) {
  .widget-editor-layout {
    grid-template-columns: 1fr;
  }
  .widget-preview-panel {
    position: static;
    max-width: 410px;
  }
}
@media (max-width: 550px) {
  .widget-form-grid {
    grid-template-columns: 1fr;
  }
  .widget-editor-header {
    align-items: flex-start;
  }
  .widget-editor-header h1 {
    font-size: 22px;
  }
  .widget-toolbar {
    flex-wrap: wrap;
  }
}
</style>

<style>
.widget-field input[type='file'] {
  font-size: 12px;
  color: rgb(var(--slate-11));
}
.widget-field input[type='file']::file-selector-button {
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  background: rgb(var(--inclamo-field));
  color: rgb(var(--slate-12));
  padding: 8px 10px;
  margin-inline-end: 8px;
  cursor: pointer;
}
.widget-field input[type='color'] {
  height: 36px;
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  padding: 3px;
  background: rgb(var(--inclamo-field));
}
</style>
