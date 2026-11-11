<script setup>
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
const props = defineProps({ chat: { type: Object, required: true } });
const { t: nativeT } = useI18n();
async function copyId() {
  await copyTextToClipboard(String(props.chat.id));
  useAlert(nativeT('CONVERSATION.HEADER.COPY_ID_SUCCESS'));
}
</script>
<template>
  <div class="inclamo-conversation-context">
    <button type="button" @click="copyId">#{{ chat.id }}</button>
    <span class="inclamo-context-divider" />
    <span class="inclamo-context-status"
      ><i aria-hidden="true" />{{
        nativeT(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${chat.status}.TEXT`)
      }}</span
    >
    <span v-if="chat.priority" class="inclamo-context-priority"
      ><span class="i-lucide-flag" aria-hidden="true" />{{
        chat.priority
      }}</span
    >
    <span v-if="chat.meta?.assignee?.name" class="inclamo-context-assignee"
      ><Avatar
        :name="chat.meta.assignee.name"
        :src="chat.meta.assignee.thumbnail"
        :size="18"
        rounded-full
      />{{ chat.meta.assignee.name }}</span
    >
  </div>
</template>
