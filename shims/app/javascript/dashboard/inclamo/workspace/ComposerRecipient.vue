<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { t } from '../i18n';
const chat = useMapGetter('getSelectedChat');
const recipient = computed(
  () => chat.value?.meta?.sender?.email || chat.value?.meta?.sender?.name
);
</script>

<template>
  <span v-if="recipient" class="reference-composer-recipient">
    {{ t('WORKSPACE.TO', { recipient }) }}
  </span>
</template>
