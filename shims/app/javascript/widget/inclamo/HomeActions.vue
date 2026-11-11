<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { selectStarter } from './starters';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const config = computed(() => window.chatwootWebChannel.inclamoWidget || {});
const starters = computed(() =>
  (config.value.starters || []).filter(e => e.enabled)
);
const links = computed(() => (config.value.links || []).filter(e => e.enabled));
const pending = ref(false);
const error = ref(false);
async function start(entry) {
  if (pending.value) return;
  error.value = false;
  const existing =
    store.getters['conversationAttributes/getConversationParams'];
  if (
    existing.status === 'resolved' &&
    !window.chatwootWebChannel.allowMessagesAfterResolved
  ) {
    await router.push({ name: 'messages' });
    return;
  }
  if (!existing.id && window.chatwootWebChannel.preChatFormEnabled) {
    selectStarter(entry.message);
    await router.push({ name: 'prechat-form' });
    return;
  }
  pending.value = true;
  try {
    const sent = existing.id
      ? await store.dispatch('conversation/sendMessage', {
          content: entry.message,
        })
      : await store.dispatch('conversation/createConversation', {
          message: entry.message,
        });
    if (sent === false) {
      error.value = true;
      return;
    }
    await router.push({ name: 'messages' });
  } catch {
    error.value = true;
  } finally {
    pending.value = false;
  }
}
function openLink(entry) {
  if (window.inclamoWidgetPreview) {
    window.dispatchEvent(
      new CustomEvent('inclamo-preview-link', { detail: entry })
    );
    return;
  }
  if (entry.kind === 'article') {
    const url = new URL(entry.url, window.location.origin);
    url.searchParams.set('show_plain_layout', 'true');
    router.push({ name: 'article-viewer', query: { link: url.href } });
  } else {
    const url = new URL(entry.url);
    if (url.protocol === 'https:')
      window.open(url.href, '_blank', 'noopener,noreferrer');
  }
}
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="starters.length || links.length" class="inclamo-home-actions">
    <button
      v-for="entry in starters"
      :key="entry.id"
      type="button"
      :disabled="pending"
      @click="start(entry)"
    >
      <span>{{ entry.label }}</span>
      <span aria-hidden="true" class="starter-arrow" />
    </button>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-10">
      {{ t('COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE') }}
    </p>
    <button
      v-for="entry in links"
      :key="entry.id"
      type="button"
      class="inclamo-help-link"
      @click="openLink(entry)"
    >
      <span>{{ entry.label }}</span>
      <span aria-hidden="true" class="link-arrow" />
    </button>
  </div>
</template>

<style scoped>
.starter-arrow::after {
  content: '\2192';
}
.link-arrow::after {
  content: '\2197';
}
.inclamo-home-actions {
  display: grid;
  gap: 8px;
}
button {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  border: 1px solid
    color-mix(in srgb, var(--widget-color, #1f93ff) 28%, transparent);
  border-radius: 12px;
  padding: 12px 14px;
  background: color-mix(in srgb, var(--widget-color, #1f93ff) 7%, transparent);
  text-align: start;
  font-size: 14px;
  color: inherit;
  overflow-wrap: anywhere;
}
button:hover {
  background: color-mix(in srgb, var(--widget-color, #1f93ff) 15%, transparent);
}
button:focus-visible {
  outline: 2px solid var(--widget-color, #1f93ff);
  outline-offset: 2px;
}
button:disabled {
  opacity: 0.6;
  cursor: wait;
}
.inclamo-help-link {
  background: transparent;
  border-color: transparent;
  text-decoration: underline;
  text-underline-offset: 3px;
}
</style>
