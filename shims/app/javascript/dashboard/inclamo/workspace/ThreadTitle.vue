<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { t } from '../i18n';
const chat = useMapGetter('getSelectedChat');
const title = computed(
  () =>
    chat.value.additional_attributes?.mail_subject ||
    t('WORKSPACE.THREAD_WITH', { name: chat.value.meta?.sender?.name || '' })
);
</script>

<template>
  <li class="inclamo-ref reference-thread-title">
    <div class="conversation-subject">
      <h3>{{ title }}</h3>
    </div>
  </li>
</template>
