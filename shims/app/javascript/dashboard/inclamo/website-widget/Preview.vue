<script setup>
import { t } from '../i18n';
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { Button } from '../ui/button';
const props = defineProps({
  draft: { type: Object, required: true },
  saved: { type: Object, required: true },
  html: { type: String, required: true },
});
const frame = ref(null);
const mobile = ref(false);
const screen = ref('home');
const online = ref(true);
const message = computed(() => ({
  type: 'inclamo-widget-preview',
  settings: JSON.parse(JSON.stringify(props.draft.settings)),
  native: JSON.parse(JSON.stringify(props.draft.native)),
  channel: JSON.parse(JSON.stringify(props.saved.channel)),
  portal: JSON.parse(
    JSON.stringify(
      props.saved.portals.find(p => p.id === props.draft.native.portal_id) ||
        null
    )
  ),
  articles: JSON.parse(
    JSON.stringify(
      props.saved.articles.filter(
        a => a.portal_id === props.draft.native.portal_id
      )
    )
  ),
  avatar:
    props.draft.avatar_image?.preview ||
    (!props.draft.remove_avatar && props.saved.avatar_url),
  icon:
    props.draft.icon_image?.preview ||
    (!props.draft.remove_icon && props.saved.icon_url),
  mobile: mobile.value,
  screen: screen.value,
  online: online.value,
}));
function update() {
  frame.value?.contentWindow?.postMessage(
    message.value,
    window.location.origin
  );
}
function receive(event) {
  if (
    event.origin === window.location.origin &&
    event.source === frame.value?.contentWindow &&
    event.data?.type === 'inclamo-preview-ready'
  )
    update();
}
watch(message, update, { deep: true });
onMounted(() => window.addEventListener('message', receive));
onBeforeUnmount(() => window.removeEventListener('message', receive));
</script>

<template>
  <aside class="widget-preview-panel">
    <div class="widget-preview-heading">
      <strong>{{ t('WEBSITE_WIDGET.PREVIEW') }}</strong>
      <span>{{ t('WEBSITE_WIDGET.LIVE_PREVIEW') }}</span>
    </div>
    <div class="widget-preview-controls">
      <Button
        size="sm"
        :variant="mobile ? 'ghost' : 'secondary'"
        @click="mobile = false"
      >
        {{ t('WEBSITE_WIDGET.DESKTOP') }}
      </Button>
      <Button
        size="sm"
        :variant="mobile ? 'secondary' : 'ghost'"
        @click="mobile = true"
      >
        {{ t('WEBSITE_WIDGET.MOBILE') }}
      </Button>
    </div>
    <div class="widget-preview-controls">
      <label>
        <select
          v-model="screen"
          :aria-label="t('WEBSITE_WIDGET.PREVIEW_SCREEN')"
        >
          <option value="home">{{ t('WEBSITE_WIDGET.HOME') }}</option>
          <option value="messages">
            {{ t('WEBSITE_WIDGET.CONVERSATION') }}
          </option>
        </select>
      </label>
      <label>
        <input v-model="online" type="checkbox" />
        {{ t('WEBSITE_WIDGET.ONLINE') }}
      </label>
    </div>
    <iframe
      ref="frame"
      :srcdoc="html"
      :title="t('WEBSITE_WIDGET.WEBSITE_WIDGET_PREVIEW')"
      :style="{ width: mobile ? '320px' : '380px' }"
      sandbox="allow-scripts allow-same-origin"
      @load="update"
    />
    <p class="widget-preview-note">
      {{ t('WEBSITE_WIDGET.PREVIEW_ONLY_MESSAGES_ARE_NEVER_DELIVERED') }}
    </p>
  </aside>
</template>
